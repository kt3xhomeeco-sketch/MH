"""Revision-scoped normalized CAD with spatial reads and a bounded resident cache."""
from collections import OrderedDict
from copy import deepcopy
import json
import os
from pathlib import Path
import sqlite3
import uuid

from geometry import Rect, TOL
from library import file_token

SCHEMA=4
_INDEXES=OrderedDict()


class SourceIndex:
    def __init__(self,path):
        self.path=Path(path).resolve()
        self.db=sqlite3.connect(f'{self.path.as_uri()}?mode=ro',uri=True)
        try:
            self.meta=json.loads(self.db.execute('SELECT value FROM metadata').fetchone()[0])
            if self.meta['schema']!=SCHEMA:raise ValueError('CAD index schema changed')
        except Exception:
            self.db.close();raise
        self.regions=OrderedDict();self.full_rects=None

    def select(self,regions):
        key=tuple(tuple(region) for region in regions)
        if key in self.regions:
            self.regions.move_to_end(key)
            return deepcopy(self.regions[key])
        selected={}
        for x0,y0,x1,y1 in regions:
            sql='''SELECT o.id,o.data FROM outlines o JOIN spatial s ON s.id=o.id
                   WHERE s.x0<=? AND s.x1>=? AND s.y0<=? AND s.y1>=?
                   AND o.x0>=? AND o.y0>=? AND o.x1<=? AND o.y1<=?'''
            for identity,data in self.db.execute(sql,(x1,x0,y1,y0,x0,y0,x1,y1)):selected[identity]=data
        rows=[json.loads(selected[i]) for i in sorted(selected)]
        self.regions[key]=rows
        if len(self.regions)>16:self.regions.popitem(last=False)
        return deepcopy(rows)

    def rectangles(self,regions,full=False):
        rows=self.meta['rectangles']
        if full:
            if self.full_rects is None:
                from geometry import line_rectangles
                lines=[]
                for data, in self.db.execute('SELECT data FROM outlines ORDER BY id'):
                    row=json.loads(data)
                    if row.get('entity_type')=='LINE':lines.append((row['points'][0],row['points'][-1],row['handle'],row.get('layer','')))
                recovered=line_rectangles(lines,min_length=100) if len(lines)<=15000 else []
                self.full_rects=rows+[r.as_dict() for r in recovered]
            rows=self.full_rects
        return [Rect(*r['box'],r['handle'],r.get('layer','')) for r in rows
                if any(r['box'][0]>=p[0]-TOL and r['box'][1]>=p[1]-TOL and r['box'][2]<=p[2]+TOL and r['box'][3]<=p[3]+TOL for p in regions)]


def write_index(path,data):
    temporary=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    try:
        db=sqlite3.connect(temporary)
        try:
            db.execute('CREATE TABLE metadata(value TEXT NOT NULL)')
            db.execute('CREATE TABLE outlines(id INTEGER PRIMARY KEY,x0 REAL,y0 REAL,x1 REAL,y1 REAL,data TEXT)')
            db.execute('CREATE VIRTUAL TABLE spatial USING rtree(id,x0,x1,y0,y1)')
            meta={k:v for k,v in data.items() if k!='outlines'}
            meta['schema']=SCHEMA
            db.execute('INSERT INTO metadata VALUES(?)',(json.dumps(meta,ensure_ascii=False),))
            for i,row in enumerate(data['outlines']):
                ps=row['points'];x0=min(p[0] for p in ps);y0=min(p[1] for p in ps);x1=max(p[0] for p in ps);y1=max(p[1] for p in ps)
                db.execute('INSERT INTO outlines VALUES(?,?,?,?,?,?)',(i,x0,y0,x1,y1,json.dumps(row,ensure_ascii=False)))
                db.execute('INSERT INTO spatial VALUES(?,?,?,?,?)',(i,x0,x1,y0,y1))
            db.commit()
        finally:db.close()
        os.replace(temporary,path)
    finally:temporary.unlink(missing_ok=True)


def load_index(revision,builder):
    path=Path(revision['folder'])/f'geometry-index-v{SCHEMA}.sqlite'
    stamp=(str(path),file_token(path) if path.exists() else None)
    if stamp[1] is not None and stamp in _INDEXES:
        _INDEXES.move_to_end(stamp)
        return _INDEXES[stamp],'memory'
    for key in list(_INDEXES):
        if key[0]==str(path):_INDEXES.pop(key).db.close()
    mode='disk'
    try:
        index=SourceIndex(path)
        if index.meta['source_hash']!=revision['hash']:
            index.db.close();raise ValueError('CAD index source mismatch')
    except (OSError,sqlite3.DatabaseError,ValueError,TypeError,KeyError):
        write_index(path,builder())
        index=SourceIndex(path);mode='extracted'
        stamp=(str(path),file_token(path))
    _INDEXES[stamp]=index
    while len(_INDEXES)>2:
        _,old=_INDEXES.popitem(last=False);old.db.close()
    return index,mode
