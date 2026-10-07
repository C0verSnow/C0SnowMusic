<template>
  <section class="bili-page">
    <header><span class="brand">C0SnowMusic</span><span class="badge">B 站音乐</span></header>
    <h1>收藏里的声音，现在播放</h1>
    <p class="intro">用 B 站客户端扫码登录，播放第一个非空收藏夹的第一条视频音轨。</p>
    <div class="bili-grid">
      <article class="card login-card">
        <h2>{{ username ? '已登录 B 站' : '扫码登录' }}</h2>
        <p v-if="username" class="username">{{ username }}</p>
        <img v-if="image && !username" :src="image" alt="B 站登录二维码" width="240" height="240" />
        <div v-else-if="!username" class="qr-placeholder">点击下方按钮生成二维码</div>
        <p role="status" aria-live="polite">{{ status }}</p>
        <button v-if="!username" :disabled="busy || polling" @click="login">{{ image ? '重新生成二维码' : '生成登录二维码' }}</button>
        <button v-else class="secondary" :disabled="busy" @click="logout">退出登录</button>
        <p class="hint">登录信息只保留到本次软件退出。</p>
      </article>
      <article class="card player-card">
        <span class="eyebrow">BILIBILI · 第一 P 音频</span>
        <h2>{{ track?.title || '等待选择收藏夹第一首歌' }}</h2>
        <p v-if="track">收藏夹：{{ track.folder }} · {{ track.bvid }}</p>
        <label>指定收藏夹 ID（不填就自动选择）<input v-model="folder" inputmode="numeric" placeholder="例如 123456789" :disabled="busy" /></label>
        <button :disabled="!username || busy" @click="loadFavorite">{{ busy ? '正在获取音轨…' : '获取收藏夹第一首歌' }}</button>
        <div class="playback">
          <span class="play-state">{{ playing ? '正在播放' : track ? '已暂停 / 等待播放' : '尚未播放' }}</span>
          <strong>{{ formatTime(currentTime) }} <small>/ {{ formatTime(duration) }}</small></strong>
          <audio ref="audio" controls preload="metadata" @timeupdate="update" @loadedmetadata="update" @playing="playing = true" @pause="playing = false" @ended="playing = false" @error="mediaError" />
        </div>
        <button v-if="track" class="secondary" @click="play">播放 / 继续播放</button>
        <p class="hint">第一条视频不可播放时会报错，不会偷偷换成其他歌曲。音轨地址过期时，重新获取即可。</p>
      </article>
    </div>
    <p v-if="error" class="error" role="alert">{{ error }}</p>
  </section>
</template>
<script setup lang="ts">
import { nextTick, onActivated, onDeactivated, onMounted, onUnmounted, ref, watch } from 'vue';
import type { BilibiliTrack } from '../../../../shared/bilibili';
import { audioService } from '@/services/audioService';
import { usePlayerStore } from '@/store/modules/player';
defineOptions({name:'Bilibili'});
const playerStore=usePlayerStore();
const audio=ref<HTMLAudioElement>(), track=ref<BilibiliTrack>(), image=ref(''), username=ref(''), folder=ref('');
const status=ref('尚未登录'), error=ref(''), busy=ref(false), polling=ref(false), playing=ref(false);
const currentTime=ref(0), duration=ref(0);
let autoplay=false, generation=0, telemetry:ReturnType<typeof setInterval>|undefined;
const api=()=>window.api.bilibili;
const showError=(e:unknown)=>{error.value=e instanceof Error?e.message:'操作失败，请重试。';};
const formatTime=(t:number)=>`${Math.floor(t/60).toString().padStart(2,'0')}:${Math.floor(t%60).toString().padStart(2,'0')}`;
function update(){const a=audio.value; if(a){currentTime.value=a.currentTime; duration.value=Number.isFinite(a.duration)?a.duration:0;}}
function mediaError(){playing.value=false; error.value='音轨加载或解码失败，请重新获取歌曲后播放。';}
async function play(){
  if(!audio.value || !track.value) return;
  audioService.pause(); playerStore.setIsPlay(false);
  try{await audio.value.play();}catch{error.value='未能开始播放，请点击播放按钮重试，或重新获取歌曲。';}
}
async function loadFavorite(){
  error.value='';
  const id=folder.value.trim()?Number(folder.value):undefined;
  if(id!==undefined && (!/^\d+$/.test(folder.value.trim()) || !Number.isSafeInteger(id) || id<=0)){error.value='收藏夹 ID 必须是正整数。';return;}
  busy.value=true; audio.value?.pause();
  try{
    track.value=await api().favorite(id);
    await nextTick();
    if(audio.value){audio.value.src=track.value.source; audio.value.load(); currentTime.value=0; duration.value=0;}
    if(autoplay) await play();
  }catch(e){showError(e);}finally{busy.value=false;}
}
async function login(){
  const own=++generation; error.value='';busy.value=true;
  try{
    image.value=(await api().qr()).image;
    status.value='请扫码，并在 B 站客户端确认登录';polling.value=true;busy.value=false;
    const deadline=Date.now()+180000;
    while(own===generation && Date.now()<deadline){
      await new Promise(r=>setTimeout(r,1500)); if(own!==generation) return;
      const result=await api().poll();
      if(result.code===0){username.value=result.username || 'B 站用户';image.value='';status.value='登录成功';polling.value=false;if(autoplay) await loadFavorite();return;}
      if(result.code===86038) throw new Error('二维码已过期，请重新生成。');
      if(result.code===86090) status.value='已扫码，请在手机上确认登录';
      else if(result.code!==86101) throw new Error('登录状态异常，请重新生成二维码。');
    }
    if(own===generation) throw new Error('扫码等待超时，请重新生成二维码。');
  }catch(e){if(own===generation){showError(e);status.value='登录未完成';}}
  finally{if(own===generation){busy.value=false;polling.value=false;}}
}
async function logout(){
  ++generation; audio.value?.pause(); audio.value?.removeAttribute('src'); audio.value?.load();
  try{await api().logout();track.value=undefined;username.value='';image.value='';currentTime.value=0;duration.value=0;status.value='已退出登录';error.value='';}catch(e){showError(e);}
}
function startTelemetry(){
  if(telemetry) return;
  telemetry=setInterval(()=>{
    const a=audio.value;
    if(a && track.value){update();api().telemetry({currentTime:a.currentTime,duration:Number.isFinite(a.duration)?a.duration:0,paused:a.paused,readyState:a.readyState,error:Boolean(a.error)});}
  },500);
}
function deactivate(){++generation;polling.value=false;busy.value=false;audio.value?.pause();if(telemetry) clearInterval(telemetry);telemetry=undefined;}
// Avoid two independent players producing audio at the same time.
watch(()=>playerStore.isPlay,value=>{if(value) audio.value?.pause();});
onActivated(startTelemetry);
onDeactivated(deactivate);
onUnmounted(deactivate);
onMounted(async()=>{startTelemetry();try{const options=await api().options();autoplay=options.autoplay;if(autoplay) await login();}catch(e){showError(e);}});
</script>
<style scoped>
.bili-page{height:100%;overflow:auto;padding:32px 38px 80px;background:#0e1826;color:#e6edf6;font-family:system-ui,sans-serif}
header{display:flex;align-items:center;gap:16px;margin-bottom:24px}.brand{font-size:16px;font-weight:750;letter-spacing:1px}.badge{color:#83dce9;background:#143945;padding:6px 12px;border-radius:20px;font-size:13px}h1{font-size:32px;margin:0 0 12px;font-weight:750}.intro,.hint{color:#9aaec3;line-height:1.7}.bili-grid{display:grid;grid-template-columns:280px minmax(280px,1fr);gap:22px;margin-top:28px}.card{padding:24px;border:1px solid #2d4058;border-radius:18px;background:#142236}h2{font-size:21px;line-height:1.5;margin:0 0 14px;font-weight:650}.login-card{text-align:center}.login-card img{background:white;border-radius:8px;margin:0 auto 14px}.qr-placeholder{height:220px;display:grid;place-items:center;color:#8499b0;border:1px dashed #40566d;border-radius:10px;margin-bottom:18px}.username{font-size:24px;color:#83dce9}.eyebrow{font-size:12px;color:#83dce9;letter-spacing:2px;display:block;margin-bottom:18px}label{display:block;color:#aebed0;font-size:13px;margin:24px 0 14px}input{display:block;width:100%;background:#0e1826;border:1px solid #3b5068;border-radius:8px;padding:10px;margin-top:10px;color:white}button{background:#69d4df;border:0;border-radius:8px;padding:11px 16px;color:#09202c;cursor:pointer;font-weight:650}button:disabled{opacity:.4;cursor:default}.secondary{background:#253b53;color:#dde9f5}.playback{padding:24px 0 18px}.play-state{color:#8de1b7;display:block;margin-bottom:10px}strong{font-size:36px;font-variant-numeric:tabular-nums;font-weight:650}small{font-size:20px;color:#9aaec3}audio{display:block;width:100%;margin-top:18px}.hint{font-size:12px;margin-top:20px}.error{margin-top:18px;background:#502b35;color:#ffd8df;padding:14px;border-radius:8px}@media(max-width:760px){.bili-grid{grid-template-columns:1fr}.bili-page{padding:20px}h1{font-size:25px}}
</style>
