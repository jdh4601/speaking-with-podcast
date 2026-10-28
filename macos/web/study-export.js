// Export runs through the same authenticated queue, with its own progress surface.
(() => {
 const select=document.querySelector('#pod-history');
 const controls=document.createElement('section');controls.className='study-export';controls.setAttribute('aria-label','아이폰 학습 꾸러미');
 controls.innerHTML='<p id="pack-episode" class="pack-episode"></p><div class="pack-actions"><label><input type="checkbox" id="pack-audio" checked> 원문 음성 포함</label><button id="pack-export">아이폰 학습 꾸러미 만들기</button><button id="pack-save" hidden>꾸러미 저장</button></div><progress id="pack-progress" hidden max="100" aria-label="원문 음성 준비 진행 상황"></progress><p id="pack-status" role="status" aria-live="polite"></p><details id="pack-warnings" hidden open><summary></summary><ul></ul></details>';
 select.closest('.review-top').after(controls);
 const get=id=>controls.querySelector(id),button=get('#pack-export'),save=get('#pack-save'),message=get('#pack-status'),warnings=get('#pack-warnings'),bar=get('#pack-progress'),audio=get('#pack-audio');
 let result=null,selected=select.value,exporting=false,saving=false,pendingNative=null,activeJob=null;
 let locked=[];
 function report(text,error=false){message.textContent=text;message.classList.toggle('error',error);}
 function selectedTitle(){return select.selectedOptions[0]?.textContent||'에피소드를 선택하세요';}
 function lockInputs(){locked=[...document.querySelectorAll('#podcast-study .study-source input,#podcast-study .study-source select,#podcast-study .study-source button'),select,audio].map(element=>[element,element.disabled]);for(const [element] of locked)element.disabled=true;}
 function unlockInputs(){for(const [element,disabled] of locked)element.disabled=disabled;locked=[];}
 function clearResult(){result=null;save.hidden=true;warnings.hidden=true;warnings.querySelector('ul').replaceChildren();bar.hidden=true;}
 function syncSelection(){
  get('#pack-episode').textContent=select.value?'내보낼 에피소드 · '+selectedTitle():'학습 기록에서 에피소드를 선택하세요.';
  if(selected!==select.value){selected=select.value;clearResult();if(!exporting&&!saving)report('에피소드를 선택했습니다. 새 꾸러미를 만들어주세요.');}
 }
 function showWarnings(items){
  warnings.querySelector('ul').replaceChildren();warnings.hidden=items.length===0;
  warnings.querySelector('summary').textContent=`원음을 준비하지 못한 표현 ${items.length}개`;
  for(const text of items){const item=document.createElement('li');item.textContent=text;warnings.querySelector('ul').append(item);}
 }
 async function request(path,data){
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),15000);
  try{const response=await fetch('/api/'+path,{method:data?'POST':'GET',headers:{'X-English-Token':window.ENGLISH_TOKEN,'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined,signal:controller.signal});const body=await response.json();if(!response.ok)throw Error(body.error||'내보내기 요청에 실패했습니다.');return body;}finally{clearTimeout(timer);}
 }
 async function followJob(id,title){
  for(;;){
   const value=await request('jobs/'+id);
   if(value.status==='error'){activeJob=null;throw Error(value.error||'꾸러미 준비에 실패했습니다.');}
   if(value.status==='done'){activeJob=null;return value.result;}
   if(value.progress){report(`‘${title}’ · ${value.progress}`);const match=value.progress.match(/(\d+)\/(\d+)/);if(match){bar.value=100*(Number(match[1])-1)/Number(match[2]);}}
   await new Promise(resolve=>setTimeout(resolve,1000));
  }
 }
 button.onclick=async()=>{
  syncSelection();const sessionId=select.value,title=selectedTitle();
  if(!sessionId){report('먼저 학습 기록에서 에피소드를 선택하세요.',true);return;}
  if(exporting||saving||busy){report('진행 중인 작업이 끝난 뒤 꾸러미를 만들어주세요.',true);return;}
  // This shares the podcast form's synchronous busy guard without its
  // extraction-only progress labels. The server also enforces a single job.
  exporting=true;busy=true;button.disabled=true;lockInputs();
  if(!activeJob){clearResult();bar.hidden=false;bar.removeAttribute('value');report(`‘${title}’ 학습 꾸러미 준비 중… 첫 원음 준비는 시간이 걸릴 수 있어요.`);}
  try{
   if(!activeJob){const job=await request('export',{sessionId,includeAudio:audio.checked});activeJob={id:job.job,sessionId,title};}
   const task=activeJob;
   report(`‘${task.title}’ 진행 상황을 확인하는 중…`);
   const value=await followJob(task.id,task.title);
   if(select.value!==task.sessionId){clearResult();syncSelection();report(`‘${task.title}’ 준비가 끝났지만 선택한 에피소드가 바뀌었습니다. 현재 에피소드로 다시 만들어주세요.`);return;}
   result=value;bar.value=100;showWarnings(value.warnings||[]);save.hidden=false;
   report(`‘${task.title}’ · 표현 ${value.cardCount}개 · 원음 ${value.audioCount}개 · ${(value.bytes/1024/1024).toFixed(1)}MB 준비 완료.${value.warnings?.length?' 아래 누락 사유를 확인한 뒤 저장하세요.':''}`);
  }catch(error){
   save.hidden=true;bar.hidden=true;
   report(activeJob?`‘${activeJob.title}’ 연결이 끊겼습니다. Mac에서는 작업이 계속될 수 있어요. ‘진행 상황 다시 확인’을 눌러 같은 작업을 확인하세요.`:error.message,true);
  }finally{exporting=false;busy=false;unlockInputs();button.disabled=false;button.textContent=activeJob?'진행 상황 다시 확인':'아이폰 학습 꾸러미 만들기';syncSelection();}
 };
 save.onclick=async()=>{
  syncSelection();if(!result||exporting||saving)return;
  const value=result,sessionId=select.value;
  saving=true;save.disabled=true;button.disabled=true;lockInputs();
  if(window.webkit?.messageHandlers?.saveStudyPack){
   pendingNative={exportId:value.exportId,sessionId};
   try{window.webkit.messageHandlers.saveStudyPack.postMessage({exportId:value.exportId});}
   catch(error){pendingNative=null;saving=false;save.disabled=false;button.disabled=false;unlockInputs();report(error.message,true);}
   return;
  }
  try{
   const response=await fetch(value.downloadUrl,{headers:{'X-English-Token':window.ENGLISH_TOKEN}});if(!response.ok)throw Error('꾸러미를 읽지 못했습니다. 저장을 다시 시도하세요.');
   const url=URL.createObjectURL(await response.blob()),link=document.createElement('a');link.href=url;link.download=value.filename;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);
   if(select.value===sessionId)report('다운로드를 요청했습니다. 아이폰에서 이 꾸러미를 가져오세요.');
  }catch(error){report(error.message,true);}finally{saving=false;save.disabled=false;button.disabled=false;unlockInputs();syncSelection();}
 };
 window.addEventListener('study-pack-saved',event=>{
  if(!pendingNative)return;
  const task=pendingNative;pendingNative=null;saving=false;save.disabled=false;button.disabled=false;unlockInputs();syncSelection();
  if(task.sessionId!==select.value)return;
  const detail=event.detail||{};
  report(detail.state==='cancelled'?'저장을 취소했습니다. 준비한 꾸러미는 ‘꾸러미 저장’으로 다시 저장할 수 있어요.':detail.message||'저장 결과를 확인하지 못했습니다. 다시 시도하세요.',detail.state==='error');
 });
 select.addEventListener('change',syncSelection);
 window.addEventListener('english-podcasts-change',syncSelection);
 new MutationObserver(syncSelection).observe(select,{childList:true,subtree:true,attributes:true});
 syncSelection();
})();
