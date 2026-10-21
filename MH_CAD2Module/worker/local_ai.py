"""Loopback-only AI selection of candidates already measured from CAD.

The model returns an ID, never geometry. Confirmed replay and tested rules win.
"""
from copy import deepcopy
import json
import os
from pathlib import Path
import subprocess
import time
from urllib.parse import urlparse
from urllib.request import Request, build_opener, ProxyHandler, HTTPRedirectHandler

from library import atomic_json
from plan_learning import digest, KINDS

CONFIG = Path(__file__).resolve().parents[1] / 'local_ai.json'
PROMPT_VERSION = 4


def inference_packet(packet):
    """Presentation only: remove float noise and repeated proposal geometry."""
    def clean(value):
        if type(value) is float:return round(value,3)
        if isinstance(value,list):return [clean(v) for v in value]
        if isinstance(value,dict):return {k:clean(v) for k,v in value.items()}
        return value
    result=clean(packet);seen={}
    for candidate in result.get('candidates',[]):
        if 'parts' not in candidate:continue
        shape=digest(candidate['parts'])
        if shape in seen:
            candidate['same_geometry_as']=seen[shape]
            candidate.pop('parts')
        else:seen[shape]=candidate['id']
    return result


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError('AI local không được chuyển hướng sang máy khác.')


class Runtime:
    def __init__(self, config=CONFIG):
        self.config = json.loads(Path(config).read_text(encoding='utf-8-sig'))
        parsed = urlparse(self.config['endpoint'])
        if (parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or not parsed.port
                or parsed.path or parsed.username or parsed.query or parsed.fragment):
            raise ValueError('AI chỉ được kết nối HTTP tại 127.0.0.1 với cổng riêng.')
        self.endpoint = self.config['endpoint']
        self.folder = Path(self.config['qa_root'])
        self.timeout = min(90, max(5, float(self.config.get('timeout_seconds', 60))))
        self.opener = build_opener(ProxyHandler({}), NoRedirect())
        self.deadline = time.monotonic() + self.timeout
        self.loaded = False

    def api(self, path, payload=None, timeout=3):
        body = None if payload is None else json.dumps(payload).encode('utf-8')
        req = Request(self.endpoint + path, data=body, headers={'Content-Type': 'application/json'})
        with self.opener.open(req, timeout=timeout) as response:
            raw = response.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024:
            raise ValueError('Phản hồi AI quá lớn.')
        return json.loads(raw)

    def ready(self):
        try:
            self.api('/api/version')
        except OSError:
            executable = Path(self.config['executable'])
            if not executable.is_file():
                raise ValueError('Chưa có bộ chạy AI local tại đường dẫn đã cài.')
            env = dict(os.environ, OLLAMA_HOST=self.endpoint.removeprefix('http://'),
                       OLLAMA_MODELS=self.config['model_store'], OLLAMA_NO_CLOUD='1',
                       OLLAMA_CONTEXT_LENGTH='4096', OLLAMA_MAX_LOADED_MODELS='1',
                       OLLAMA_NUM_PARALLEL='1', OLLAMA_GPU_OVERHEAD='536870912')
            log = self.folder / 'logs' / 'server.log'
            log.parent.mkdir(parents=True, exist_ok=True)
            with log.open('ab') as stream:
                subprocess.Popen([str(executable), 'serve'], env=env, stdin=subprocess.DEVNULL,
                                 stdout=stream, stderr=stream, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
            for _ in range(30):
                time.sleep(.2)
                try:
                    self.api('/api/version', timeout=1)
                    break
                except OSError:
                    pass
            else:
                raise TimeoutError('Bộ chạy AI chưa sẵn sàng sau 6 giây.')
        tag = next((m for m in self.api('/api/tags')['models'] if m['name'] == self.config['model']), None)
        if not tag or tag['digest'] != self.config['model_digest']:
            raise ValueError('Mô hình AI thiếu hoặc khác bản đã kiểm tra; không tự tải khi quét.')
        return dict(ready=True, model=tag['name'], digest=tag['digest'],
                    message='AI local sẵn sàng · dữ liệu xử lý trên máy · cao mặt bằng tạm 1600 mm.')

    def infer_json(self, stage, packet, schema, instruction):
        self.ready()
        presented=inference_packet(packet)
        payload = json.dumps(presented, separators=(',', ':'))
        context=max(getattr(self,'context',0),2048 if len(payload)<=2800 else 4096)
        self.context=context
        key = digest(dict(version=PROMPT_VERSION, stage=stage, model=self.config['model_digest'],
                          instruction=instruction,schema=schema,packet=presented,context=context))
        cache = self.folder / 'tests' / 'cache' / f'{key}.json'
        try:
            saved = json.loads(cache.read_text(encoding='utf-8'))
            if saved['checksum'] == digest(saved['answer']):
                return saved['answer'], dict(cached=True, seconds=0, model=self.config['model'])
        except (OSError, ValueError, KeyError, TypeError):
            pass
        if len(payload) > 6000:
            raise ValueError('Dữ liệu AI vượt lượt ngắn; giữ kết quả CAD.')
        remaining = self.deadline - time.monotonic()
        if remaining < 1:
            raise TimeoutError('Đã hết thời gian đối chiếu AI cho sản phẩm này.')
        started = time.monotonic()
        self.loaded = True
        result = self.api('/api/chat', dict(model=self.config['model'], stream=False, format=schema,
                          keep_alive=30, options=dict(temperature=0, seed=0, num_ctx=context, num_predict=128, num_batch=256),
                          messages=[dict(role='system', content=instruction+' Reply ONLY JSON matching the supplied schema.'),
                                    dict(role='user', content=payload)]), timeout=remaining)
        if not isinstance(result, dict) or not result.get('done') or result.get('done_reason') != 'stop':
            raise ValueError('AI chưa trả lời hoàn chỉnh.')
        if result.get('prompt_eval_count',0)>=context-160:
            raise ValueError('Ngữ cảnh AI quá dài để kiểm tra đầy đủ; giữ kết quả CAD.')
        answer = json.loads(result['message']['content'])
        metrics = dict(cached=False, seconds=round(time.monotonic()-started, 2), model=self.config['model'],
                       context=context,tokens=result.get('eval_count'),prompt_tokens=result.get('prompt_eval_count'),total_duration=result.get('total_duration'),
                       load_duration=result.get('load_duration'), eval_duration=result.get('eval_duration'))
        atomic_json(self.folder / 'tests' / 'requests' / f'{key}.json',
                    dict(stage=stage, model_digest=self.config['model_digest'], packet=presented, answer=answer, metrics=metrics))
        # Validate in each public method before publishing an answer to cache.
        return answer, dict(metrics, cache_key=key)

    def remember(self, answer, metrics):
        key = metrics.pop('cache_key', None)
        if key:
            atomic_json(self.folder / 'tests' / 'cache' / f'{key}.json', dict(answer=answer, checksum=digest(answer)))

    def find(self, packet):
        ids = [c['id'] for c in packet['samples']]
        schema = dict(type='object', properties={
            'sample_ids': dict(type='array', items=dict(type='string', enum=ids), maxItems=3, uniqueItems=True),
            'search': dict(type='string', enum=['done','more','parts','curves']),
            'reason': dict(type='string', maxLength=100)},
            required=['sample_ids','search','reason'], additionalProperties=False)
        instruction = ('Find useful cabinet PLAN examples for the target. Numeric cards describe accepted layouts. '
            'Select up to 3 IDs, including near matches or reusable subparts; different sizes, stock or bay count '
            'are NOT rejection reasons. Partial examples supply present parts only. Prefer geometric structure '
            'over size similarity. Search more/parts/curves if this page lacks useful examples; otherwise done. '
            'Do not invent IDs or dimensions. Reason at most 40 characters.')
        answer, metrics = self.infer_json('find_samples',packet,schema,instruction)
        validate_search(answer,ids)
        self.remember(answer,metrics)
        return answer,metrics

    def choose(self, packet):
        ids = [c['id'] for c in packet['candidates']]
        schema = dict(type='object', properties={
            'decision': dict(type='string', enum=['choose', 'reject']),
            'candidate_id': dict(type='string', enum=ids + ['none']),
            'reason': dict(type='string', maxLength=100)},
            required=['decision', 'candidate_id', 'reason'], additionalProperties=False)
        instruction = ('Decide the final cabinet PLAN partition after app measurement and physical evaluation. '
            'Compare selected examples, numeric target geometry and all evaluated proposals. Each proposed face '
            'comes from current CAD; sizes, bay counts and trim may differ from examples. Match construction '
            'and grouping, using reusable example parts when appropriate. No preference for proposal IDs or '
            'names. same_geometry_as references an identical measured geometry. No preference for '
            'baseline merely by name. Never invent coordinates or override failed checks. Choose the best '
            'supported proposal, or reject if evidence cannot distinguish them. Structure scores summarize '
            'sample grouping consistency, not hard rules. Reason at most 40 characters.')
        answer,metrics = self.infer_json('decide_plan',packet,schema,instruction)
        validate_answer(answer,ids)
        self.remember(answer,metrics)
        return answer,metrics

    def release(self):
        if self.loaded:
            try:
                self.api('/api/generate',dict(model=self.config['model'],stream=False,keep_alive=0),timeout=2)
            except (OSError,ValueError):
                pass


def validate_answer(answer, ids):
    if (not isinstance(answer, dict) or set(answer) != {'decision', 'candidate_id', 'reason'}
            or answer['decision'] not in ('choose', 'reject')
            or answer['candidate_id'] not in [*ids, 'none']
            or not isinstance(answer['reason'], str) or len(answer['reason']) > 180
            or (answer['decision'] == 'choose' and answer['candidate_id'] == 'none')):
        raise ValueError('AI trả lời ngoài danh sách phương án đã đo.')


def validate_search(answer, ids):
    if (not isinstance(answer,dict) or set(answer)!={'sample_ids','search','reason'}
            or not isinstance(answer['sample_ids'],list) or len(answer['sample_ids'])>3
            or any(not isinstance(i,str) or i not in ids for i in answer['sample_ids'])
            or len(set(answer['sample_ids']))!=len(answer['sample_ids'])
            or answer['search'] not in ('done','more','parts','curves')
            or not isinstance(answer['reason'],str) or len(answer['reason'])>180):
        raise ValueError('AI tìm mẫu trả dữ liệu/ID ngoài thư viện được cung cấp.')


def status(config=CONFIG):
    try:
        return Runtime(config).ready()
    except (OSError, ValueError, KeyError, TypeError) as error:
        return dict(ready=False, message=f'AI local chưa sẵn sàng: {error}')


def compact(candidate):
    offset = candidate.get('offset', [0, 0])
    parts = []
    for kind in KINDS:
        for p in candidate['state'].get(kind, []):
            part = dict(kind=kind, origin=[p['origin'][i]+offset[i] for i in (0,1)], size=p['size'][:2])
            if p.get('plan_profile'):
                part['profile'] = p['plan_profile']
            parts.append(part)
    return dict(id=candidate['id'], parts=parts)


class Assistant:
    def __init__(self, request, memory, runtime=None):
        self.request = request
        self.enabled = request.get('ai_enabled') is True
        self.memory = memory
        self.config = request.get('ai_config') or CONFIG
        self.runtime = runtime
        self.called = False

    def progress(self, stage, message):
        self.trace.append(dict(stage=stage,message=message))
        path=self.request.get('progress_file')
        if path:
            target=Path(path).resolve()
            if target.is_relative_to((self.memory.root/'jobs').resolve()):
                atomic_json(target,dict(stage=stage,message=message))

    def apply(self, product):
        if not self.enabled or product.get('build_stages', {}).get('elevation') is not False:
            return False
        if product.get('learning', {}).get('mode') in ('plan_exact', 'user_confirmed', 'plan_rule'):
            return False
        if any(i.get('code')=='source_binding_mismatch' for i in product.get('learning',{}).get('issues',[])):
            return False
        if self.called:
            product['local_ai']=dict(status='skipped',message='AI đã xử lý một SP trong lượt này; quét riêng SP để đối chiếu.')
            return False
        from plan_search import Samples, target_card, proposals, physical_check
        original=deepcopy(product);started=time.monotonic();runtime=None;self.trace=[]
        audit=dict(workflow='ai_plan_search_v2');cad=None
        try:
            rules=self.memory.plan_rules()
            cad=rules.measured_features(product)
            target=target_card(product,cad)
            library=Samples(self.memory.root).refresh();revision=library.token
            audit['library_revision']=revision
            if not library.rows:
                product['local_ai']=dict(status='skipped',message='Chưa có mẫu mặt bằng đã xác nhận để AI tìm kiếm.')
                return False
            self.called=True
            runtime=self.runtime or Runtime(self.config)
            self.progress('find_samples','AI đang tìm mẫu đúng/gần giống và các phần có thể dùng lại…')
            seen=[];selected=[];searches=[];metrics=[];mode='similar'
            for _ in range(2):
                page=library.page(target,mode,seen)
                if not page:break
                answer,m=runtime.find(dict(target=target,samples=page,total_samples=len(library.rows),seen=len(seen)))
                validate_search(answer,[c['id'] for c in page]);metrics.append(m)
                searches.append(dict(answer=answer,seen=[c['id'] for c in page]))
                selected=list(dict.fromkeys(selected+answer['sample_ids']))[:3]
                seen.extend(c['id'] for c in page)
                if answer['search']=='done' or len(selected)>=3:break
                mode={'parts':'parts','curves':'curves'}.get(answer['search'],'similar')
            rows=[r for r in library.rows if r['card']['id'] in selected]
            audit.update(searches=searches,calls=metrics,selected_samples=[dict(id=r['card']['id'],event=r['event']['id'],
                code=r['event']['analysis'].get('code'),partial=r['card']['partial']) for r in rows])
            self.progress('evaluate','App đang tạo phương án từ mẫu AI chọn và đo lại trên CAD…')
            options,rejected=proposals(product,cad,rows)
            audit.update(rejected=rejected,proposals=[dict(id=c['id'],method=c['method'],samples=c['samples'],
                checks=c['checks'],evaluation=c['evaluation']) for c in options])
            if not options:raise ValueError('Không có phương án vượt kiểm tra hình học. '+ '; '.join(r['reason'] for r in rejected[:2]))
            self.progress('decide','AI đang đối chiếu các phương án và quyết định cách chia cuối…')
            shown=sorted(options,key=lambda c:c['evaluation']['structure_score'],reverse=True)[:6]
            base=next((c for c in options if c['id']=='baseline'),None)
            if base and base not in shown:shown[-1]=base
            packet=dict(target=target,measured_axes=[sorted({round(v,4) for v in a.values()})[:32] for a in cad['refs']],
                samples=[r['card'] for r in rows],rejected=rejected[:3])
            while shown:
                packet['candidates']=[dict(compact(c),method=c['method'],samples=c['samples'],valid=c['checks']['passed'],
                    evaluation={k:v for k,v in c['evaluation'].items() if k!='note'}) for c in shown]
                if len(json.dumps(packet,separators=(',',':')))<=5500 or len(shown)==1:break
                shown.pop()
            answer,m=runtime.choose(packet)
            validate_answer(answer,[c['id'] for c in shown]);metrics.append(m)
            elapsed=round(time.monotonic()-started,2)
            info=dict(workflow='ai_plan_search_v2',status=answer['decision'],candidate=answer['candidate_id'],reason=answer['reason'],seconds=elapsed,
                model=m.get('model'),cached=all(x.get('cached') for x in metrics),rounds=len(metrics),trace=self.trace,
                selected_samples=[dict(id=r['card']['id'],event=r['event']['id'],code=r['event']['analysis'].get('code'),
                                       partial=r['card']['partial']) for r in rows],
                library_revision=revision,searches=searches,rejected=rejected,calls=metrics,presented=[c['id'] for c in shown],
                proposals=[dict(id=c['id'],method=c['method'],samples=c['samples'],checks=c['checks'],evaluation=c['evaluation']) for c in options],
                message='AI đã tìm mẫu, app đánh giá phương án và AI quyết định kết quả cuối.')
            product['local_ai']=info
            if answer['decision']!='choose':
                product.update(status='needs_review',error='AI chưa chọn được duy nhất cách chia đủ bằng chứng; xem các phương án trong quá trình SP.')
                return False
            chosen=next(c for c in options if c['id']==answer['candidate_id'])
            self.progress('preflight','App đang kiểm tra lần cuối và chuẩn bị dựng Group trên CAD…')
            if library.refresh().token!=revision:raise ValueError('Kinh nghiệm đã thay đổi trong lúc AI chạy; cần quét lại.')
            checked=physical_check(original,chosen['state'],chosen['offset'],cad)
            info['final_check']=checked
            if chosen['id']=='baseline':
                product.update(plan_origin_offset_mm=chosen['offset'],plan_origin_basis='source_plan_envelope')
                info['message']='AI chọn giữ phương án đo từ CAD; đã kiểm tra lần cuối trước khi dựng.'
                return False
            product.update(deepcopy(chosen['state']),status='ready',height_source='provisional_default',
                default_height_mm=1600,plan_origin_offset_mm=chosen['offset'],plan_origin_basis='source_plan_envelope')
            product.pop('error',None)
            product['learning']=dict(mode='local_ai',examples=[r['event']['id'] for r in rows if r['card']['id'] in chosen['samples']],
                method=chosen['method'],message='AI chọn mẫu và cách ghép; kích thước/vị trí đo từ CAD mới, cao tạm 1600 mm.')
            product.setdefault('explanation',[]).append(product['learning']['message'])
            return True
        except (OSError,ValueError,KeyError,TypeError,IndexError,AttributeError) as error:
            product.clear();product.update(original)
            info=dict(audit,status='fallback',seconds=round(time.monotonic()-started,2),trace=self.trace,
                message=f'AI chưa quyết định được: {error}')
            product['local_ai']=info
            if original.get('status')=='ready':
                try:
                    if cad is None:raise ValueError('Chưa xác minh được hình học nguồn.')
                    state={k:original.get(k,[]) for k in (*KINDS,'bounds')}
                    offset=[original['envelope'][i]-cad['base'][i] for i in (0,1)]
                    info['final_check']=physical_check(original,state,offset,cad)
                    info['fallback_to_cad']=True
                    if any(abs(v)>.05 for v in offset):
                        product.update(plan_origin_offset_mm=offset,plan_origin_basis='source_plan_envelope')
                    info['message']+=' Giữ phương án CAD đã vượt kiểm tra hình học.'
                except (ValueError,KeyError,TypeError,IndexError) as check_error:
                    product.update(status='needs_review',error=f'Chưa dựng: {check_error}')
                    info['message']+=' '+product['error']
            return False
        finally:
            if runtime and hasattr(runtime,'release'):runtime.release()
