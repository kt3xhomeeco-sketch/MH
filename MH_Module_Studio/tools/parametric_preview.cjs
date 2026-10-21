// Developer-only render of the read-only state captured from the selected native cabinet.
const {app,BrowserWindow}=require('electron');
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..');
app.whenReady().then(async()=>{
 const win=new BrowserWindow({show:false,width:1390,height:1000,webPreferences:{contextIsolation:true,sandbox:true}});
 try{
  await win.loadFile(path.join(root,'ui','parametric.html'));
  const state=JSON.parse(fs.readFileSync(path.join(root,'outputs','parametric-native-window-state.json'),'utf8'));
  await win.webContents.executeJavaScript(`window.receive(${JSON.stringify(state)});`);
  await win.webContents.executeJavaScript('new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))');
  const shot=await win.webContents.capturePage();fs.writeFileSync(path.join(root,'outputs','parametric-window-cabinet.png'),shot.toPNG());
  win.destroy();app.exit(0);
 }catch(error){console.error(error.stack);win.destroy();app.exit(1);}
});
