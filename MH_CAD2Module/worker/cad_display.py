"""Overlay fronts at their logical datums; keep extra section copies to the right."""


def arrange(views):
    for view in views:
        if view.get('role') in ('front_check','front_unspecified','front_open'):
            view.pop('drawing_x_offset_mm',None);view.pop('display_placement',None)
    fronts=[v for v in views if v.get('role') in ('front_check','front_unspecified','front_open') and not v.get('parent_view_id')]
    if not fronts:return []
    previous=max(fronts,key=lambda v:v['box_mm'][2]+v['x_offset_mm'])
    right=previous['box_mm'][2]+previous['x_offset_mm'];copies=[]
    for source in [v for v in sorted(views,key=lambda v:v['box_mm'][0]) if v.get('role')=='section_vertical' and v['plane']=='YZ']:
        b=source['box_mm'];left=round(right+500,6)
        placement=dict(basis='standing_inspection_row',spacing_mm=500,after_view_id=previous['id'],min_x_mm=left)
        current=dict(id=source['id']+'-XZ',source_view_id=source['id'],plane='XZ',role='section_vertical',
                     alignment='section_display_copy',box_mm=b[:],anchor_box_mm=source['anchor_box_mm'][:],
                     title=source['title'],x_offset_mm=round(left-b[0],6),display_placement=placement)
        copies.append(current)
        right=left+b[2]-b[0];previous=current
    return copies
