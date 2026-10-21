'use strict';
// Offline box viewer. Both renderers test depth per pixel; highlights are opaque.
(() => {
  const sides = [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]];
  const edges = [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]];
  const corners = b => [0,1].flatMap(x=>[0,1].flatMap(y=>[0,1].map(z=>[b[x][0],b[y][1],b[z][2]])));
  class Viewer {
    constructor(canvas, options={}) {
      this.canvas=canvas; this.parts=[]; this.highlighted=new Set(); this.colors=new Map(); this.yaw=-0.55; this.pitch=0.42;
      this.zoom=1; this.pan=[0,0]; this.solid=true; this.edges=true; this.xray=false; this.perspective=true;
      this.queued=false; this.lost=false; this.background=[0.973,0.981,0.986,1];
      const gl=options.software ? null : canvas.getContext('webgl',{antialias:true,alpha:false,preserveDrawingBuffer:true,depth:true});
      this.gl=gl; this.ctx=gl ? null : canvas.getContext('2d');
      canvas.dataset.renderer=gl ? 'webgl-depth' : 'software-depth';
      if(gl) this.initGL();
      canvas.addEventListener('webglcontextlost',event=>{event.preventDefault();this.lost=true;});
      canvas.addEventListener('webglcontextrestored',()=>{this.lost=false;this.initGL();this.schedule();});
      this.observer=new ResizeObserver(()=>this.schedule()); this.observer.observe(canvas);
      let last=null;
      canvas.addEventListener('contextmenu',event=>event.preventDefault());
      canvas.addEventListener('pointerdown',event=>{last={x:event.clientX,y:event.clientY,startX:event.clientX,startY:event.clientY,moved:0,pan:event.button===2||event.button===1||event.shiftKey,id:event.pointerId};canvas.setPointerCapture(event.pointerId);});
      canvas.addEventListener('pointermove',event=>{
        if(!last || last.id!==event.pointerId) return;
        const dx=event.clientX-last.x,dy=event.clientY-last.y;
        last.moved+=Math.abs(dx)+Math.abs(dy);
        if(last.pan||event.shiftKey){this.pan[0]+=dx;this.pan[1]+=dy;}
        else{this.yaw+=dx*0.007;this.pitch=Math.max(-1.5,Math.min(1.57,this.pitch+dy*0.007));}
        last.x=event.clientX;last.y=event.clientY;this.schedule();
      });
      canvas.addEventListener('pointerup',event=>{if(last && last.moved<4 && !last.pan && this.onPick){const rect=canvas.getBoundingClientRect();this.onPick(this.pick(event.clientX-rect.left,event.clientY-rect.top));}last=null;});
      ['pointercancel','lostpointercapture'].forEach(name=>canvas.addEventListener(name,()=>{last=null;}));
      canvas.addEventListener('wheel',event=>{event.preventDefault();this.zoom=Math.max(0.3,Math.min(5,this.zoom*Math.exp(-event.deltaY*0.001)));this.schedule();},{passive:false});
    }
    initGL(){
      const gl=this.gl;
      const shader=(type,source)=>{const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s;};
      const vs=shader(gl.VERTEX_SHADER,'attribute vec3 position;attribute vec4 color;varying vec4 tint;void main(){gl_Position=vec4(position,1.0);tint=color;}');
      const fs=shader(gl.FRAGMENT_SHADER,'precision mediump float;varying vec4 tint;void main(){gl_FragColor=tint;}');
      this.program=gl.createProgram();gl.attachShader(this.program,vs);gl.attachShader(this.program,fs);gl.linkProgram(this.program);
      if(!gl.getProgramParameter(this.program,gl.LINK_STATUS))throw Error(gl.getProgramInfoLog(this.program));
      gl.deleteShader(vs);gl.deleteShader(fs);this.buffer=gl.createBuffer();
      this.position=gl.getAttribLocation(this.program,'position');this.color=gl.getAttribLocation(this.program,'color');
    }
    set(parts,highlighted=new Set()) {this.parts=parts||[];this.highlighted=highlighted;this.schedule();}
    fit(){this.zoom=1;this.pan=[0,0];this.schedule();}
    view(name){
      if(name==='front'){this.yaw=0;this.pitch=0;this.perspective=false;}
      else if(name==='back'){this.yaw=Math.PI;this.pitch=0;this.perspective=false;}
      else if(name==='left'){this.yaw=Math.PI/2;this.pitch=0;this.perspective=false;}
      else if(name==='bottom'){this.yaw=0;this.pitch=-Math.PI/2;this.perspective=false;}
      else if(name==='right'){this.yaw=-Math.PI/2;this.pitch=0;this.perspective=false;}
      else if(name==='top'){this.yaw=0;this.pitch=Math.PI/2;this.perspective=false;}
      else{this.yaw=-0.55;this.pitch=0.42;this.perspective=name==='perspective';}
      this.fit();
    }
    schedule(){if(this.queued)return;this.queued=true;requestAnimationFrame(()=>{this.queued=false;this.draw();});}
    geometry(width,height){
      const parts=this.parts.filter(p=>p.visible!==false && p.bounds?.length===2);
      if(!parts.length)return {faces:[],lines:[],grid:[]};
      const low=[0,1,2].map(a=>Math.min(...parts.map(p=>p.bounds[0][a]))),high=[0,1,2].map(a=>Math.max(...parts.map(p=>p.bounds[1][a])));
      const center=high.map((v,a)=>(v+low[a])/2),radius=Math.max(1,Math.hypot(...high.map((v,a)=>v-low[a]))/2),distance=radius*4;
      const rotate=point=>{
        const [x,y,z]=point.map((v,a)=>v-center[a]),right=Math.cos(this.yaw)*x-Math.sin(this.yaw)*y;
        const depth=-Math.sin(this.yaw)*x-Math.cos(this.yaw)*y;
        return [right,Math.cos(this.pitch)*z-Math.sin(this.pitch)*depth,Math.cos(this.pitch)*depth+Math.sin(this.pitch)*z];
      };
      const raw=point=>{const [x,y,depth]=rotate(point),k=this.perspective?distance/(distance-depth):1;
        const near=radius*0.1,far=radius*12;
        const z=this.perspective?(far+near)/(far-near)-2*near*far/((far-near)*(distance-depth)):-depth/(radius*4);
        return [x*k,-y*k,z];};
      const limits=corners([low,high]).map(raw),minX=Math.min(...limits.map(p=>p[0])),maxX=Math.max(...limits.map(p=>p[0]));
      const minY=Math.min(...limits.map(p=>p[1])),maxY=Math.max(...limits.map(p=>p[1]));
      const padding=this.viewportPadding||[0,0],usableWidth=Math.max(180,width-padding[0]-padding[1]);
      const vertical=this.verticalPadding||[0,0],usableHeight=Math.max(130,height-vertical[0]-vertical[1]);
      const scale=Math.min((usableWidth-100)/Math.max(1,maxX-minX),(usableHeight-75)/Math.max(1,maxY-minY))*this.zoom;
      const project=point=>{const p=raw(point);return [(p[0]-(minX+maxX)/2)*scale+(width+padding[0]-padding[1])/2+this.pan[0],(p[1]-(minY+maxY)/2)*scale+(height+vertical[0]-vertical[1])/2+this.pan[1],p[2]];};
      const faces=[],lines=[],grid=[],shades=[0.85,0.96,0.74,0.88,0.78,1];
      for(const part of parts){
        const points=corners(part.bounds).map(project),selected=this.highlighted.has(part.key),base=this.colors.get(part.key)||(selected?[0.25,0.65,0.67]:[0.86,0.80,0.69]);
        if(part.face_count>0)sides.forEach((indices,i)=>{const color=base.map(v=>v*shades[i]).concat(this.xray?0.28:1);
          const p=indices.map(index=>points[index]),ref={part:part.key,axis:Math.floor(i/2),side:i%2};faces.push({points:[p[0],p[1],p[2]],color,ref},{points:[p[0],p[2],p[3]],color,ref});});
        edges.forEach(indices=>lines.push({points:indices.map(index=>points[index]),color:selected?[0,0.39,0.42,1]:[0.40,0.39,0.34,1]}));
      }
      const step=Math.max(25,Math.ceil(radius/8/25)*25),extent=radius*1.35,z=low[2]-0.5;
      for(let i=-10;i<=10;i++){
        grid.push({points:[project([center[0]+i*step,center[1]-extent,z]),project([center[0]+i*step,center[1]+extent,z])],color:[0.88,0.91,0.93,1]});
        grid.push({points:[project([center[0]-extent,center[1]+i*step,z]),project([center[0]+extent,center[1]+i*step,z])],color:[0.88,0.91,0.93,1]});
      }
      return {faces,lines,grid,project};
    }
    pick(x,y){
      const rect=this.canvas.getBoundingClientRect(),mesh=this.geometry(rect.width,rect.height);
      let hit=null,depth=Infinity;
      for(const triangle of mesh.faces){
        const [a,b,c]=triangle.points,den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);if(Math.abs(den)<1e-8)continue;
        const u=((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/den;
        const v=((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/den,w=1-u-v;
        if(u<-1e-6||v<-1e-6||w<-1e-6)continue;
        const z=u*a[2]+v*b[2]+w*c[2];if(z<depth){depth=z;hit=triangle.ref;}
      }
      return hit;
    }
    draw(){
      if(this.lost)return;
      if(this.onViewChange)this.onViewChange();
      const rect=this.canvas.getBoundingClientRect();if(rect.width<1||rect.height<1)return;
      const ratio=this.gl?Math.min(devicePixelRatio||1,2):Math.min(devicePixelRatio||1,1,Math.sqrt(650000/(rect.width*rect.height)));
      const w=Math.max(1,Math.round(rect.width*ratio)),h=Math.max(1,Math.round(rect.height*ratio));
      if(this.canvas.width!==w||this.canvas.height!==h){this.canvas.width=w;this.canvas.height=h;}
      const mesh=this.geometry(rect.width,rect.height);
      if(this.gl)this.drawGL(mesh,w,h,rect.width,rect.height);else this.drawSoftware(mesh,w,h,ratio);
    }
    drawGL(mesh,w,h,cssWidth,cssHeight){
      const gl=this.gl;gl.viewport(0,0,w,h);gl.clearColor(...this.background);gl.clearDepth(1);gl.depthMask(true);gl.colorMask(true,true,true,true);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
      gl.useProgram(this.program);gl.bindBuffer(gl.ARRAY_BUFFER,this.buffer);
      gl.enableVertexAttribArray(this.position);gl.enableVertexAttribArray(this.color);gl.vertexAttribPointer(this.position,3,gl.FLOAT,false,28,0);gl.vertexAttribPointer(this.color,4,gl.FLOAT,false,28,12);
      const batch=(entries,type)=>{if(!entries.length)return;const data=[];entries.forEach(e=>e.points.forEach(p=>data.push(p[0]*2/cssWidth-1,1-p[1]*2/cssHeight,p[2],...e.color)));gl.bufferData(gl.ARRAY_BUFFER,new Float32Array(data),gl.DYNAMIC_DRAW);gl.drawArrays(type,0,data.length/7);};
      gl.enable(gl.DEPTH_TEST);gl.depthFunc(gl.LEQUAL);gl.disable(gl.BLEND);
      if(this.xray){gl.disable(gl.DEPTH_TEST);gl.depthMask(false);gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);mesh.faces.sort((a,b)=>b.points.reduce((s,p)=>s+p[2],0)-a.points.reduce((s,p)=>s+p[2],0));}
      else{gl.enable(gl.POLYGON_OFFSET_FILL);gl.polygonOffset(1,1);if(!this.solid)gl.colorMask(false,false,false,false);}
      batch(mesh.faces,gl.TRIANGLES);gl.colorMask(true,true,true,true);gl.disable(gl.POLYGON_OFFSET_FILL);gl.disable(gl.BLEND);gl.depthMask(false);
      if(this.edges||this.xray)batch(mesh.lines,gl.LINES);
      gl.enable(gl.DEPTH_TEST);batch(mesh.grid,gl.LINES);gl.depthMask(true);
    }
    drawSoftware(mesh,w,h,ratio){
      const image=this.ctx.createImageData(w,h),data=image.data,depth=new Float32Array(w*h);depth.fill(Infinity);
      for(let i=0;i<data.length;i+=4){data[i]=248;data[i+1]=250;data[i+2]=251;data[i+3]=255;}
      const put=(x,y,z,color,line=false)=>{if(x<0||y<0||x>=w||y>=h||z< -1||z>1)return;const index=y*w+x;
        if(!this.xray && z>depth[index]+(line?0.000015:0))return;
        if(!line&&!this.xray)depth[index]=z;
        if(!this.solid&&!line&&!this.xray)return;
        const a=color[3];for(let c=0;c<3;c++)data[index*4+c]=Math.round(color[c]*255*a+data[index*4+c]*(1-a));};
      const point=p=>[p[0]*ratio,p[1]*ratio,p[2]];
      if(this.xray)mesh.faces.sort((a,b)=>b.points.reduce((s,p)=>s+p[2],0)-a.points.reduce((s,p)=>s+p[2],0));
      for(const face of mesh.faces){const [a,b,c]=face.points.map(point),den=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1]);if(Math.abs(den)<1e-9)continue;
        const minX=Math.max(0,Math.floor(Math.min(a[0],b[0],c[0]))),maxX=Math.min(w-1,Math.ceil(Math.max(a[0],b[0],c[0])));
        const minY=Math.max(0,Math.floor(Math.min(a[1],b[1],c[1]))),maxY=Math.min(h-1,Math.ceil(Math.max(a[1],b[1],c[1])));
        for(let y=minY;y<=maxY;y++)for(let x=minX;x<=maxX;x++){
          const u=((b[1]-c[1])*(x+0.5-c[0])+(c[0]-b[0])*(y+0.5-c[1]))/den;
          const v=((c[1]-a[1])*(x+0.5-c[0])+(a[0]-c[0])*(y+0.5-c[1]))/den,t=1-u-v;
          if(u>=-1e-8&&v>=-1e-8&&t>=-1e-8)put(x,y,u*a[2]+v*b[2]+t*c[2],face.color);
        }
      }
      const line=entry=>{const [a,b]=entry.points.map(point),count=Math.ceil(Math.max(Math.abs(b[0]-a[0]),Math.abs(b[1]-a[1])));
        for(let i=0;i<=count;i++){const t=count?i/count:0;put(Math.round(a[0]+(b[0]-a[0])*t),Math.round(a[1]+(b[1]-a[1])*t),a[2]+(b[2]-a[2])*t,entry.color,true);}};
      if(this.edges||this.xray)mesh.lines.forEach(line);
      // Grid also has to be occluded in solid mode.
      const xray=this.xray;this.xray=false;mesh.grid.forEach(line);this.xray=xray;
      this.ctx.putImageData(image,0,0);
    }
    dispose(){this.observer.disconnect();if(this.gl){this.gl.deleteBuffer(this.buffer);this.gl.deleteProgram(this.program);}}
  }
  window.ModuleViewer=Viewer;
})();
