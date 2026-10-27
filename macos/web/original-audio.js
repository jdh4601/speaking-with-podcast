// Playback always uses a cut of the original recording, never synthesized speech.
window.OriginalAudio=(()=>{
 let serial=0,player=null,url=null,timer=null;const cache=new Map();
 function stop(){serial++;if(player){player.pause();player.onended=null;player.onerror=null;player=null}if(timer){clearTimeout(timer);timer=null}if(url){URL.revokeObjectURL(url);url=null}}
 async function request(path,data){const r=await fetch('/api/'+path,{method:data?'POST':'GET',headers:{'X-English-Token':window.ENGLISH_TOKEN,'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});const v=await r.json();if(!r.ok)throw Error(v.error||'원본 음성을 가져오지 못했습니다.');return v}
 async function play(session,index,times=1,onStatus=()=>{}){
  stop();const id=serial,key=session.id+':'+index;
  try{
   let clip=cache.get(key);
   if(!clip){onStatus('원본 MP3 구간 준비 중… 첫 재생은 시간이 걸릴 수 있어요.');const{job}=await request('audio',{sessionId:session.id,index});let done=false;for(let i=0;i<900;i++){await new Promise(r=>setTimeout(r,1000));if(id!==serial)return;const v=await request('jobs/'+job);if(v.status==='error')throw Error(v.error);if(v.status==='done'){clip=v.result;cache.set(key,clip);done=true;break}}if(!done)throw Error('원본 음성 준비 시간이 초과되었습니다.')}
   if(id!==serial)return;
   const response=await fetch(clip.clipUrl,{headers:{'X-English-Token':window.ENGLISH_TOKEN}});if(!response.ok)throw Error('저장된 원본 음성 구간을 읽지 못했습니다.');const blob=await response.blob();if(id!==serial)return;
   url=URL.createObjectURL(blob);player=new Audio(url);let remaining=times;
   const format=n=>`${Math.floor(n/60)}:${String(Math.floor(n%60)).padStart(2,'0')}`;
   async function start(){if(id!==serial||!player)return;player.currentTime=0;await player.play();onStatus(`원본 MP3 · ${format(clip.start)} · ${clip.duration.toFixed(1)}초`)}
   player.onended=()=>{if(id!==serial)return;remaining--;if(remaining>0)timer=setTimeout(()=>start().catch(e=>onStatus(e.message,true)),600);else onStatus(`원본 MP3 · ${clip.duration.toFixed(1)}초 · 재생 완료`)};
   player.onerror=()=>onStatus('원본 음성을 재생하지 못했습니다.',true);
   await start();return clip;
  }catch(e){if(id===serial)onStatus(e.message,true);return null}
 }
 window.addEventListener('pagehide',stop);return{play,stop};
})();
