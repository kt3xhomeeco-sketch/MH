// Real renderer checks: visibility is asserted from pixels, not shader strings.
const {app,BrowserWindow}=require('electron');
const fs=require('fs'),path=require('path'),assert=require('assert');
const root=path.resolve(__dirname,'..');
app.whenReady().then(async()=>{
  const win=new BrowserWindow({show:false,width:1200,height:850,webPreferences:{contextIsolation:true,nodeIntegration:false,sandbox:true}});
  try{
    await win.loadFile(path.join(root,'ui','index.html'));
    const report=await win.webContents.executeJavaScript(`(() => {
      const reports=[];
      for(const software of [false,true]){
        const canvas=document.createElement('canvas');
        Object.assign(canvas.style,{position:'fixed',left:'-400px',top:'0',width:'256px',height:'256px'});document.body.append(canvas);
        const viewer=new ModuleViewer(canvas,{software});viewer.view('front');
        const front={key:'front',bounds:[[-90,-20,-90],[90,0,90]],face_count:6,visible:true};
        const back={key:'back',bounds:[[-60,10,-60],[60,30,60]],face_count:6,visible:true};
        const read=()=>{const w=canvas.width,h=canvas.height;if(viewer.gl){const pixels=new Uint8Array(w*h*4);viewer.gl.readPixels(0,0,w,h,viewer.gl.RGBA,viewer.gl.UNSIGNED_BYTE,pixels);return pixels;}return viewer.ctx.getImageData(0,0,w,h).data;};
        const center=()=>{const pixels=read(),index=(Math.floor(canvas.height/2)*canvas.width+Math.floor(canvas.width/2))*4;return Array.from(pixels.slice(index,index+4));};
        viewer.parts=[back,front];viewer.highlighted=new Set(['back']);viewer.draw();const hidden=center();
        viewer.parts=[front,back];viewer.draw();const reversed=center();
        const frames=[];
        for(const camera of ['front','perspective','right','top','left','back','bottom']){
          viewer.view(camera);viewer.parts=[front,back];viewer.draw();const a=read();
          viewer.parts=[back,front];viewer.draw();const b=read();
          let difference=0;for(let i=0;i<a.length;i++)if(a[i]!==b[i])difference++;
          frames.push({camera,difference});
        }
        viewer.view('front');viewer.parts=[front,back];viewer.edges=false;viewer.draw();const withoutEdges=read();
        viewer.edges=true;viewer.draw();const withEdges=read();
        // All projected rear edges lie well inside the front face. Sample them;
        // toggling edges must not expose any of these hidden lines.
        const geometry=viewer.geometry(256,256),hiddenLines=geometry.lines.slice(12),ratio=canvas.width/256;
        let hiddenEdgeDifference=0;
        for(const line of hiddenLines){for(let t=0.1;t<=0.9;t+=0.1){
          const x=Math.round((line.points[0][0]*(1-t)+line.points[1][0]*t)*ratio);
          let y=Math.round((line.points[0][1]*(1-t)+line.points[1][1]*t)*ratio);
          if(viewer.gl)y=canvas.height-1-y;
          const index=(y*canvas.width+x)*4;
          for(let c=0;c<3;c++)if(withEdges[index+c]!==withoutEdges[index+c])hiddenEdgeDifference++;
        }}
        viewer.highlighted=new Set(['front']);viewer.draw();const selected=center();
        viewer.highlighted=new Set(['back']);viewer.xray=true;viewer.draw();const transparent=center();
        const context=viewer.gl?{depthBits:viewer.gl.getParameter(viewer.gl.DEPTH_BITS),error:viewer.gl.getError()}:null;
        reports.push({renderer:canvas.dataset.renderer,hidden,reversed,frames,hiddenEdgeDifference,selected,transparent,context});
        viewer.dispose();canvas.remove();
      }
      return reports;
    })()`);
    for(const result of report){
      assert(result.hidden[0]>result.hidden[1] && result.hidden[1]>result.hidden[2],'Opaque front must hide the selected rear');
      assert.deepEqual(result.hidden,result.reversed);
      assert(result.frames.every(frame=>frame.difference===0),'Opaque rendering must not depend on draw order in any camera');
      assert.equal(result.hiddenEdgeDifference,0,'Rear edges must not bleed through the front');
      assert(result.selected[1]>result.selected[0]*1.5 && result.selected[3]===255,'Selected front is opaque teal');
      assert.notDeepEqual(result.transparent,result.hidden,'X-ray is opt-in and visibly different');
      if(result.context){assert(result.context.depthBits>=16);assert.equal(result.context.error,0);}
    }
    assert(report.some(result=>result.renderer==='software-depth'),'Software fallback was exercised');
    fs.writeFileSync(path.join(root,'outputs','viewer-depth-report.json'),JSON.stringify(report,null,2));
    console.log(JSON.stringify({ok:true,renderers:report.map(result=>result.renderer),cameraChecks:14,hiddenEdgeChecks:'passed'}));
    app.exit(0);
  }catch(error){console.error(error.stack);app.exit(1);}
});
