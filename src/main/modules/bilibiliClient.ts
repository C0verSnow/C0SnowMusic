// Port of scripts/download_favorite.py; account and signed URLs stay in main.
import { createHash } from 'node:crypto';
const MIXIN = [46,47,18,2,53,8,23,32,15,50,10,31,58,3,45,35,27,43,5,49,33,9,42,19,29,28,14,39,12,38,41,13,37,48,7,16,24,55,40,61,26,17,0,1,60,51,30,4,22,25,54,21,56,62,6,63,57,20,34,52,59,11,36,44];
export const API = 'https://api.bilibili.com';
export const PASSPORT = 'https://passport.bilibili.com';
export const HEADERS = {'User-Agent':'Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36', Referer:'https://www.bilibili.com/'};
export function signWbi(params: Record<string, string | number>, image: string, sub: string, now = Math.floor(Date.now()/1000)) {
  const stem = (url: string) => new URL(url).pathname.split('/').pop()!.split('.')[0];
  const raw = stem(image) + stem(sub);
  if (raw.length !== 64) throw new Error('B 站返回的 WBI key 格式不正确。');
  const key = MIXIN.map(i => raw[i]).join('').slice(0,32);
  const values: Record<string,string|number> = {...params, wts:now};
  const encode = (s:string) => encodeURIComponent(s).replace(/[!'()*]/g,c=>`%${c.charCodeAt(0).toString(16).toUpperCase()}`).replace(/%20/g,'+');
  const query = Object.keys(values).sort().map(k=>`${encode(k)}=${encode(String(values[k]).replace(/[!'()*]/g,''))}`).join('&');
  return `${query}&w_rid=${createHash('md5').update(query+key).digest('hex')}`;
}
export function mediaUrls(track:any): string[] {
  return [...new Set<string>([track.baseUrl || track.base_url,...(track.backupUrl || track.backup_url || [])])].filter(url=>{
    try {const u=new URL(url); return u.protocol==='https:' && /(^|\.)(bilivideo\.com|bilivideo\.cn|akamaized\.net)$/.test(u.hostname);} catch {return false;}
  });
}
export class BilibiliClient {
  constructor(private fetcher:(url:string,init:any)=>Promise<Response>) {}
  async api(path:string, params:Record<string,string|number>|string={},base=API):Promise<any> {
    const query=typeof params==='string'?params:new URLSearchParams(Object.entries(params).map(([k,v])=>[k,String(v)])).toString();
    let response:Response;
    try {response=await this.fetcher(`${base}${path}?${query}`,{headers:HEADERS,signal:AbortSignal.timeout(30000)});} catch {throw new Error('B 站请求失败，请检查网络后重试。');}
    if(!response.ok) throw new Error(`B 站请求失败（HTTP ${response.status}）。`);
    let body:any;
    try {body=await response.json();} catch {throw new Error('B 站返回的数据格式不正确。');}
    if(body.code!==0 || !body.data || typeof body.data!=='object') throw new Error(`B 站接口拒绝请求（${body.code}）。`);
    return body.data;
  }
  qr(){return this.api('/x/passport-login/web/qrcode/generate',{},PASSPORT);}
  poll(key:string){return this.api('/x/passport-login/web/qrcode/poll',{qrcode_key:key},PASSPORT);}
  async nav(){const nav=await this.api('/x/web-interface/nav'); if(!nav.isLogin || !nav.mid) throw new Error('登录已失效，请重新扫码。'); return nav;}
  async firstFavorite(mid:number,folderId?:number){
    let folders:any[];
    if(folderId) folders=[{id:folderId}];
    else {
      const data=await this.api('/x/v3/fav/folder/created/list-all',{up_mid:mid}); folders=data.list || [];
      if(data.count>folders.length){
        folders=[];
        for(let pn=1;;pn++){
          const page=await this.api('/x/v3/fav/folder/created/list',{up_mid:mid,pn,ps:20}); const batch=page.list || []; folders.push(...batch);
          if(!page.has_more) break;
          if(!batch.length) throw new Error('收藏夹分页异常，无法确定第一首歌。');
        }
      }
    }
    for(const folder of folders){
      const data=await this.api('/x/v3/fav/resource/list',{media_id:folder.id,pn:1,ps:20,order:'mtime',platform:'web'});
      if(data.medias?.length){const video=data.medias[0]; if((video.type??2)!==2 || !(video.bvid || video.bv_id)) throw new Error('收藏夹第一条不是可播放的视频。'); return {folder:data.info || folder,video};}
    }
    throw new Error('没有非空收藏夹，请先收藏一条视频。');
  }
  async favorite(folderId?:number){
    const nav=await this.nav(); const {folder,video}=await this.firstFavorite(nav.mid,folderId); const bvid=video.bvid || video.bv_id;
    const details=await this.api('/x/web-interface/view',{bvid}); const page=details.pages?.[0];
    if(!page?.cid) throw new Error('第一条视频已失效或没有可播放的第一 P。');
    const keys=nav.wbi_img; if(!keys?.img_url || !keys?.sub_url) throw new Error('B 站未返回签名 key，请重新登录。');
    const play=await this.api('/x/player/wbi/playurl',signWbi({bvid,cid:page.cid,fnval:4048,fnver:0,fourk:1},keys.img_url,keys.sub_url));
    const tracks=(play.dash?.audio || []).filter((t:any)=>(!t.codecs || t.codecs.startsWith('mp4a')) && mediaUrls(t).length).sort((a:any,b:any)=>(b.bandwidth||0)-(a.bandwidth||0));
    if(!tracks.length) throw new Error('没有可播放的独立 AAC 音轨，可能受版权或账号权限限制。');
    return {title:details.title || video.title,bvid,cid:page.cid,folder:folder.title || String(folder.id),urls:mediaUrls(tracks[0])};
  }
}
