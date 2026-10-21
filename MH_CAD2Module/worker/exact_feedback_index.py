"""Resident exact-feedback index; invalidate on every event/exclusion file change."""
from collections import OrderedDict
import json

from library import VERSION,file_token

_ROOTS=OrderedDict()


def events_for(root,signature,signature_fn):
    key=str(root.resolve())
    records=_ROOTS.setdefault(key,{})
    _ROOTS.move_to_end(key)
    while len(_ROOTS)>3:_ROOTS.popitem(last=False)
    paths=sorted((root/'experiences').glob('*/*.json'),key=lambda p:p.name,reverse=True)
    live={str(p) for p in paths}
    for old in set(records)-live:records.pop(old)
    excluded={p.stem for p in (root/'experience_exclusions').glob('*.json')}
    for path in paths:
        try:
            stamp=file_token(path)
            cached=records.get(str(path))
            if stamp is None or not cached or cached[0]!=stamp:
                event=json.loads(path.read_text(encoding='utf8'));analysis=event['analysis']
                eligible=(event.get('status')=='accepted' and event.get('parser_version')==VERSION and event.get('input_axes_ignored')
                          and not event.get('scope',{}).get('partial_sample') and analysis.get('build_stages',{}).get('elevation') is False
                          and event.get('signature')==path.parent.name)
                measured=signature_fn(analysis.get('outlines',[])) if eligible else None
                compact={k:event[k] for k in ('id','after','plan_origin_offset_mm','plan_origin_basis') if k in event}
                compact['analysis']={k:analysis[k] for k in ('envelope','source_plan_envelope','plan_origin_basis') if k in analysis}
                cached=(stamp,measured,compact);records[str(path)]=cached
            if cached[1]==signature and cached[2].get('id') not in excluded:yield path,cached[2]
        except (OSError,ValueError,KeyError,TypeError,AttributeError):
            records.pop(str(path),None)
