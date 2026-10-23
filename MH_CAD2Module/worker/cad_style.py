"""Resolved stroke metadata; geometry still has to prove a closed stock panel."""
import re

FIELDS=('linetype','continuous','color','true_color','lineweight')


def metadata(row):
    return {key:row[key] for key in FIELDS if key in row}


def style_key(row):
    return tuple(row.get(key) for key in ('layer',*FIELDS))


def interrupted(row):
    if row.get('continuous') is False:return True
    name=str(row.get('linetype','')).upper()
    if not name:return False
    return bool(re.search(r'DASH|HIDDEN|CENTER|PHANTOM|DOT',name))


def structural_rows(rows):
    """Unknown style stays usable; explicit interrupted strokes remain context."""
    return [row for row in rows if not interrupted(row)]


def entity_style(entity,layer,inherited=None):
    inherited=inherited or {}
    record=entity.doc.layers.get(layer) if entity.doc and layer in entity.doc.layers else None
    def value(key,default):return record.dxf.get(key,default) if record else default
    line=entity.dxf.get('linetype','BYLAYER')
    if line.upper()=='BYLAYER':line=value('linetype','CONTINUOUS')
    if line.upper()=='BYBLOCK':line=inherited.get('linetype','CONTINUOUS')
    color=entity.dxf.get('color',256)
    if color==256:color=abs(value('color',7))
    if color==0:color=inherited.get('color',7)
    weight=entity.dxf.get('lineweight',-1)
    if weight==-1:weight=value('lineweight',-3)
    if weight==-2:weight=inherited.get('lineweight',-3)
    result=dict(linetype=line,color=color,lineweight=weight)
    rgb=entity.dxf.get('true_color',None)
    if rgb is None:rgb=value('true_color',None) if entity.dxf.get('color',256)==256 else inherited.get('true_color') if entity.dxf.get('color',256)==0 else None
    if rgb is not None:result['true_color']=rgb
    if entity.doc and line in entity.doc.linetypes:
        tags=entity.doc.linetypes.get(line).pattern_tags.tags
        result['continuous']=not any(t.code==49 and t.value<=0 for t in tags)
    return result
