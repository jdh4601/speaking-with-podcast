// Playback always uses a cut of the original recording, never synthesized speech.
window.OriginalAudio=(()=>{
 let serial=0,player=null,url=null,timer=null;const cache=new Map();
 let queue=[],working=false;
 const pending=new Map();
 const keyFor=(session,index)=>session.id+':'+index;
 async function load(session,index){
  const {job}=await request('audio',{sessionId:session.id,index});
  const deadline=Date.now()+900000;
  for(let delay=100;Date.now()<deadline;delay=Math.min(delay*2,1000)){
   const state=await request('jobs/'+job);
   if(state.status==='error')throw Error(state.error);
   if(state.status==='done'){
    const clip=state.result;
    const response=await fetch(clip.clipUrl,{headers:{'X-English-Token':window.ENGLISH_TOKEN}});
    if(!response.ok)throw Error('저장된 원본 음성 구간을 읽지 못했습니다.');
    return {clip,blob:await response.blob()};
   }
   await new Promise(resolve=>setTimeout(resolve,delay));
  }
  throw Error('원본 음성 준비 시간이 초과되었습니다.');
 }
 async function drain(){
  if(working)return;
  working=true;
  while(queue.length){
   const task=queue.shift();
   try{
    const audio=await load(task.session,task.index);
    cache.set(task.key,audio);
    if(cache.size>8)cache.delete(cache.keys().next().value);
    task.resolve(audio);
   }catch(error){task.reject(error)}
   finally{pending.delete(task.key)}
  }
  working=false;
 }
 function prepare(session,index,priority=false){
  const key=keyFor(session,index);
  if(cache.has(key))return Promise.resolve(cache.get(key));
  let task=pending.get(key);
  if(!task){
   task={session,index,key};
   task.promise=new Promise((resolve,reject)=>{task.resolve=resolve;task.reject=reject});
   pending.set(key,task);
   queue.push(task);
  }
  if(priority&&queue.includes(task)){
   queue.splice(queue.indexOf(task),1);
   queue.unshift(task);
  }
  drain();
  return task.promise;
 }
 function clearQueue(){
  for(const task of queue){pending.delete(task.key);task.resolve(null)}
  queue=[];
 }
 function preload(session,index){
  prepare(session,index).catch(()=>{});
  if(index+1<session.expressions.length)prepare(session,index+1).catch(()=>{});
 }
 function stop(){clearQueue();stopPlayback()}
 function stopPlayback(){serial++;if(player){player.pause();player.onended=null;player.onerror=null;player=null}if(timer){clearTimeout(timer);timer=null}if(url){URL.revokeObjectURL(url);url=null}}
 async function request(path,data){const r=await fetch('/api/'+path,{method:data?'POST':'GET',headers:{'X-English-Token':window.ENGLISH_TOKEN,'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});const v=await r.json();if(!r.ok)throw Error(v.error||'원본 음성을 가져오지 못했습니다.');return v}
 async function play(session,index,times=1,onStatus=()=>{}){
  // Keep upcoming clips queued when replaying the visible card.
  stopPlayback();const id=serial,key=keyFor(session,index);
  try{
   let audio=cache.get(key);
   if(!audio){
    onStatus('원문 문장 음성을 준비하고 있어요…');
    audio=await prepare(session,index,true);
   }
   if(id!==serial||!audio)return;
   const {clip,blob}=audio;
   url=URL.createObjectURL(blob);player=new Audio(url);let remaining=times;
   const format=n=>`${Math.floor(n/60)}:${String(Math.floor(n%60)).padStart(2,'0')}`;
   async function start(){if(id!==serial||!player)return;player.currentTime=0;await player.play();if(id!==serial)return;onStatus(`원문 문장 MP3 · ${format(clip.start)} · ${clip.duration.toFixed(1)}초`)}
   player.onended=()=>{if(id!==serial)return;remaining--;if(remaining>0)timer=setTimeout(()=>start().catch(e=>onStatus(e.message,true)),600);else onStatus(`원문 문장 MP3 · ${clip.duration.toFixed(1)}초 · 재생 완료`)};
   player.onerror=()=>onStatus('원본 음성을 재생하지 못했습니다.',true);
   await start();return clip;
  }catch(e){if(id===serial)onStatus(e.message,true);return null}
 }
 window.addEventListener('pagehide',stop);return{play,stop,preload};
})();
