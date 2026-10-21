from geometry import line_rectangles, recognise
from test_geometry import cabinet


def test_split_wall_edges_still_define_same_module():
    lines=[]
    for rect in cabinet():
        points=[(rect.x0,rect.y0),(rect.x1,rect.y0),(rect.x1,rect.y1),(rect.x0,rect.y1)]
        for i in range(4):
            a,b=points[i],points[(i+1)%4]
            # Both straight and vertical CAD edges may be split during native import.
            middle=((a[0]+b[0])/2,(a[1]+b[1])/2)
            lines.extend([(a,middle,f'{rect.handle}:{i}a',''),(middle,b,f'{rect.handle}:{i}b','')])
    result=recognise(line_rectangles(lines))
    assert [m['size'] for m in result['modules']]==[[860,582,2110],[860,582,2110],[1720,582,382]]
