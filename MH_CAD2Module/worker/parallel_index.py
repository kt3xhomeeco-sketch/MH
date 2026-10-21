"""Indexed parallel faces: probe stock offsets, never scan all later parallels."""
from bisect import bisect_left, bisect_right
from collections import defaultdict
import math

from geometry import TOL
from materials import BOARD_MM, stock_evidence


class ParallelIndex:
    def __init__(self,lines,excluded=()):
        from plan_evidence import edge_key
        self.origin=[min((p[i] for a,b,_ in lines for p in (a,b)),default=0) for i in (0,1)]
        raw=defaultdict(list)
        for a,b,handle in lines:
            if edge_key(a,b) in excluded:continue
            dx,dy=b[0]-a[0],b[1]-a[1]
            if math.hypot(dx,dy)<=TOL:continue
            angle=math.atan2(dy,dx)%math.pi
            if abs(angle-math.pi)<.000005:angle=0
            raw[round(angle,5)].append((a,b,handle,angle,math.hypot(dx,dy)))
        grouped=defaultdict(lambda:defaultdict(list));self.angles={}
        for key,lines_in_direction in raw.items():
            angle=max(lines_in_direction,key=lambda row:row[4])[3];self.angles[key]=angle
            u=(math.cos(angle),math.sin(angle));n=(-u[1],u[0])
            for a,b,handle,_,_length in lines_in_direction:
                points=[[p[i]-self.origin[i] for i in (0,1)] for p in (a,b)]
                offset=round(sum(n[i]*(points[0][i]+points[1][i])/2 for i in (0,1)),6)
                lo,hi=sorted(sum(u[i]*p[i] for i in (0,1)) for p in points)
                grouped[key][offset].append((lo,hi,handle))
        self.groups={};self.probes=0;self.pair_checks=0
        for angle,faces in grouped.items():
            merged={}
            for offset,intervals in faces.items():
                spans=[]
                for lo,hi,handle in sorted(intervals):
                    if spans and lo<=spans[-1][1]+TOL:
                        spans[-1][1]=max(hi,spans[-1][1]);spans[-1][2].add(handle)
                    else:spans.append([lo,hi,{handle}])
                merged[offset]=(spans,[s[1] for s in spans])
            self.groups[angle]=(sorted(merged),merged)

    def point(self,angle,offset,t):
        angle=self.angles[angle]
        u=(math.cos(angle),math.sin(angle));n=(-u[1],u[0])
        return [self.origin[i]+u[i]*t+n[i]*offset for i in (0,1)]

    def covers(self,a,b):
        angle=math.atan2(b[1]-a[1],b[0]-a[0])%math.pi
        if abs(angle-math.pi)<.000005:angle=0
        key=round(angle,5)
        for angle in (key,round(key-.00001,5),round(key+.00001,5)):
            if angle not in self.groups:continue
            radians=self.angles[angle]
            u=(math.cos(radians),math.sin(radians));n=(-u[1],u[0])
            ps=[[p[i]-self.origin[i] for i in (0,1)] for p in (a,b)]
            offset=sum(n[i]*ps[0][i] for i in (0,1))
            lo,hi=sorted(sum(u[i]*p[i] for i in (0,1)) for p in ps)
            offsets,faces=self.groups[angle]
            for d in offsets[bisect_left(offsets,offset-TOL):bisect_right(offsets,offset+TOL)]:
                spans,ends=faces[d];index=bisect_left(ends,lo-TOL)
                if index<len(spans) and spans[index][0]<=lo+TOL and spans[index][1]>=hi-TOL:return True
        return False

    def panels(self,allow_short=False):
        result=[]
        for angle,(offsets,faces) in self.groups.items():
            for offset in offsets:
                for stock in BOARD_MM:
                    self.probes+=1
                    target=offset+stock
                    # Directly probe each allowed offset, not every later line.
                    for other in offsets[bisect_left(offsets,target-TOL):bisect_right(offsets,target+TOL)]:
                        spans,ends=faces[other]
                        for lo,hi,handles in faces[offset][0]:
                            index=bisect_left(ends,lo)
                            while index<len(spans) and spans[index][0]<hi:
                                low,high=max(lo,spans[index][0]),min(hi,spans[index][1]);self.pair_checks+=1
                                measured=other-offset
                                if high-low>(max(3,measured) if allow_short else max(20,2*measured)):
                                    sides=[[self.point(angle,d,t) for t in (low,high)] for d in (offset,other)]
                                    if all(self.covers(sides[0][j],sides[1][j]) for j in (0,1)):
                                        seams=[]
                                        for middle in offsets[bisect_right(offsets,offset+TOL):bisect_left(offsets,other-TOL)]:
                                            if any(s[0]<=low+TOL and s[1]>=high-TOL for s in faces[middle][0]):seams.append(round(middle-offset,3))
                                        result.append(dict(kind='straight',measured_mm=round(measured,6),stock_mm=stock_evidence(measured)['stock_mm'],
                                            length_mm=round(high-low,6),boundary=sides,internal_seams_mm=seams,
                                            direction_rad=self.angles[angle],lamination_candidate=[18,18] if stock==36 else None,
                                            handles=sorted(handles|spans[index][2]),evidence='parallel_faces_and_closed_ends'))
                                index+=1
        return result
