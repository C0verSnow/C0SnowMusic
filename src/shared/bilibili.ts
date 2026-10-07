export interface BilibiliTrack { title:string; bvid:string; cid:number; folder:string; source:string }
export interface BilibiliTelemetry { currentTime:number; duration:number; paused:boolean; readyState:number; error:boolean }
export interface BilibiliAPI {
  options():Promise<{autoplay:boolean; evidence:boolean}>;
  qr():Promise<{image:string}>;
  poll():Promise<{code:number; username?:string}>;
  favorite(folderId?:number):Promise<BilibiliTrack>;
  logout():Promise<void>;
  telemetry(state:BilibiliTelemetry):void;
}
