import { app, BrowserWindow, ipcMain, net, protocol, session } from 'electron';
import { mkdir, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import QRCode from 'qrcode';
import { BilibiliClient, HEADERS } from './bilibiliClient';
import type { BilibiliTelemetry } from '../../shared/bilibili';

export function initializeBilibili(window:BrowserWindow) {
  // No persist: prefix; cookies only exist for this process.
  const account=session.fromPartition('c0-bilibili-account');
  const client=new BilibiliClient((url,init)=>account.fetch(url,{...init,credentials:'include'}));
  let qrKey='', urls:string[]=[], track:any=null, latest:BilibiliTelemetry|undefined;
  let telemetryAt=0, timer:NodeJS.Timeout|undefined, capturing=false, previous=-1;
  const captures:any[]=[];
  const flag=process.argv.find(a=>a.startsWith('--evidence-dir='));
  const evidenceDir=flag?resolve(flag.slice('--evidence-dir='.length)):undefined;
  const trusted=(event:Electron.IpcMainInvokeEvent|Electron.IpcMainEvent)=>{
    if(event.sender!==window.webContents || event.senderFrame!==window.webContents.mainFrame) throw new Error('无权访问 B 站模块。');
  };
  const stopEvidence=()=>{if(timer) clearInterval(timer); timer=undefined;};
  async function capture(){
    if(capturing || !evidenceDir || !track || !latest || captures.length>=6) return;
    if(Date.now()-telemetryAt>2500 || latest.error || latest.paused || latest.readyState<2 || latest.currentTime<=previous){stopEvidence(); return;}
    capturing=true;
    try {
      await mkdir(evidenceDir,{recursive:true});
      const state={...latest}, capturedAt=new Date().toISOString();
      const png=await window.webContents.capturePage();
      const file=`playback-${String(captures.length+1).padStart(2,'0')}.png`;
      await writeFile(join(evidenceDir,file),png.toPNG());
      captures.push({file,capturedAt,...state}); previous=state.currentTime;
      await writeFile(join(evidenceDir,'manifest.json'),JSON.stringify({app:app.getName(),version:app.getVersion(),track:{title:track.title,bvid:track.bvid,cid:track.cid,folder:track.folder},intervalSeconds:10,captures},null,2));
      console.log(`[Bilibili] screenshot ${captures.length}/6, playback ${state.currentTime.toFixed(1)}s`);
      if(captures.length===6) stopEvidence();
    } catch {stopEvidence(); console.error('[Bilibili] 无法保存截图，请检查目录权限。');}
    finally {capturing=false;}
  }
  protocol.handle('bilibili-media',async request=>{
    if(request.url!=='bilibili-media://audio/current' || !urls.length) return new Response('没有音轨',{status:404});
    for(const url of urls){
      try {
        const headers:Record<string,string>={...HEADERS}, range=request.headers.get('Range');
        if(range) headers.Range=range;
        // Only CDN URLs selected in main; no account cookies. Preserve Range for seeking.
        const response=await net.fetch(url,{headers,credentials:'omit',signal:AbortSignal.timeout(60000)});
        if(response.ok && !response.headers.get('content-type')?.includes('text/')) return response;
        await response.body?.cancel();
      } catch { /* Same track's backup URL; never log signed URLs. */ }
    }
    return new Response('音频地址不可用，请重新获取歌曲。',{status:502});
  });
  ipcMain.handle('bilibili:options',event=>{trusted(event); return {autoplay:process.argv.includes('--bilibili-autoplay'),evidence:Boolean(evidenceDir)};});
  ipcMain.handle('bilibili:qr',async event=>{
    trusted(event);
    const qr=await client.qr(); qrKey=qr.qrcode_key;
    const image=await QRCode.toDataURL(qr.url,{width:280,margin:2});
    if(evidenceDir){await mkdir(evidenceDir,{recursive:true}); await writeFile(join(evidenceDir,'bilibili.png'),Buffer.from(image.split(',')[1],'base64'));}
    return {image};
  });
  ipcMain.handle('bilibili:poll',async event=>{
    trusted(event); if(!qrKey) throw new Error('请先生成二维码。');
    const status=await client.poll(qrKey);
    if(status.code===0){const nav=await client.nav(); qrKey=''; return {code:0,username:nav.uname};}
    return {code:status.code};
  });
  ipcMain.handle('bilibili:favorite',async(event,folderId?:number)=>{
    trusted(event);
    if(folderId!==undefined && (!Number.isSafeInteger(folderId) || folderId<=0)) throw new Error('收藏夹 ID 必须是正整数。');
    track=await client.favorite(folderId); urls=track.urls;
    stopEvidence(); captures.length=0; previous=-1; latest=undefined;
    return {title:track.title,bvid:track.bvid,cid:track.cid,folder:track.folder,source:'bilibili-media://audio/current'};
  });
  ipcMain.handle('bilibili:logout',async event=>{trusted(event); stopEvidence(); urls=[]; track=null; qrKey=''; latest=undefined; await account.clearStorageData();});
  ipcMain.on('bilibili:telemetry',(event,state:BilibiliTelemetry)=>{
    trusted(event);
    if(!state || !Number.isFinite(state.currentTime) || state.currentTime<0 || !Number.isFinite(state.duration)) return;
    latest=state; telemetryAt=Date.now();
    if(evidenceDir && track && !timer && captures.length<6 && !state.paused && !state.error && state.readyState>=2 && state.currentTime>previous){
      timer=setInterval(()=>{void capture();},10000);
    }
  });
  window.on('closed',stopEvidence);
}
