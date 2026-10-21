"""One windowless, serial CAD worker per SketchUp process/library/runtime."""
import argparse
import ctypes
import json
import os
from pathlib import Path
import time

from library import atomic_json
from main import run


def parent_alive(pid):
    if os.name=='nt':
        kernel=ctypes.windll.kernel32
        kernel.OpenProcess.restype=ctypes.c_void_p
        handle=kernel.OpenProcess(0x100000,False,pid)
        if not handle:return False
        try:return kernel.WaitForSingleObject(ctypes.c_void_p(handle),0)==258
        finally:kernel.CloseHandle(ctypes.c_void_p(handle))
    try:os.kill(pid,0);return True
    except ProcessLookupError:return False


def serve(queue,parent,idle_seconds=1800):
    queue=Path(queue).resolve();queue.mkdir(parents=True,exist_ok=True)
    jobs=queue.parent.parent
    atomic_json(queue.parent/'ready.json',dict(pid=os.getpid(),protocol=1))
    last=time.monotonic();count=0
    while parent_alive(parent) and time.monotonic()-last<idle_seconds:
        pending=sorted(queue.glob('*.json'))
        if not pending:time.sleep(.04);continue
        for ticket in pending:
            response=None;started=time.perf_counter()
            try:
                packet=json.loads(ticket.read_text(encoding='utf8'))
                request=Path(packet['request']).resolve();response=Path(packet['response']).resolve()
                if request.parent.parent!=jobs or response.parent!=request.parent or request.name!='request.json' or response.name!='response.json':
                    response=None;raise ValueError('Request outside worker job directory')
                values=json.loads(request.read_text(encoding='utf-8-sig'))
                result=dict(ok=True,**run(values),completed_at=time.time())
            except Exception as error:result=dict(ok=False,error=f'{type(error).__name__}: {error}')
            count+=1
            result['worker']=dict(resident=True,pid=os.getpid(),job_number=count,compute_seconds=round(time.perf_counter()-started,6))
            if response:atomic_json(response,result)
            ticket.unlink(missing_ok=True)
            last=time.monotonic()


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--queue',required=True);parser.add_argument('--parent',type=int,required=True)
    args=parser.parse_args();serve(args.queue,args.parent)
