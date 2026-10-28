// Source text is derived from the transcript by the same function used for audio.
window.SourceSentences=(()=>{
 const pending=new Map(),complete=new Map();
 async function request(path,data){
  const r=await fetch('/api/'+path,{method:data?'POST':'GET',headers:{'X-English-Token':window.ENGLISH_TOKEN,'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});
  const value=await r.json();if(!r.ok)throw Error(value.error||'원문 해석을 가져오지 못했습니다.');return value;
 }
 async function ensure(session){
  if(!session.expressions.some(c=>c.sourceSentence&&!c.sourceSentenceTranslation))return;
  if(!pending.has(session.id)&&!complete.has(session.id)){
   const task=(async()=>{
    const {job}=await request('translate-source',{sessionId:session.id});
    for(let i=0;i<300;i++){
     await new Promise(resolve=>setTimeout(resolve,1000));
     const state=await request('jobs/'+job);
     if(state.status==='error')throw Error(state.error);
     if(state.status==='done'){complete.set(session.id,state.result);return state.result}
    }
    throw Error('원문 해석 준비 시간이 초과되었습니다.');
   })();
   pending.set(session.id,task);task.finally(()=>pending.delete(session.id)).catch(()=>{});
  }
  const translated=complete.get(session.id)||await pending.get(session.id);
  session.expressions.forEach((card,i)=>{
   const next=translated.expressions[i];
   if(next?.sourceSentence===card.sourceSentence&&next.sourceSentenceTranslation)card.sourceSentenceTranslation=next.sourceSentenceTranslation;
  });
 }
 return {ensure};
})();
