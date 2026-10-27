(()=>{
 const get=s=>document.querySelector(s);const panel=get('#today-review');
 const today=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 let episodes=[],episode=null,index=0,progress={};
 try{progress=JSON.parse(localStorage.getItem('english-today-review-v1')||'{}');if(!progress||typeof progress!=='object')progress={}}catch{}
 const progressKey=()=>today()+':'+episode.id;
 function remember(){if(!episode)return;progress[progressKey()]=index;try{localStorage.setItem('english-today-review-v1',JSON.stringify(progress))}catch{}}
 function saved(){try{return JSON.parse(localStorage.getItem('english-podcast-saved-v1')||'{}')||{}}catch{return {}}}
 function updateSave(){if(!episode)return;const isSaved=(saved()[episode.id]||[]).includes(index);get('#review-save').textContent=isSaved?'저장됨 ✓':'표현 저장하기';get('#review-save').disabled=isSaved}
 function showCard(){
  window.OriginalAudio?.stop();get('#review-content').hidden=!episode;get('#review-empty').hidden=Boolean(episode);get('#review-episode').hidden=!episode;
  if(!episode){get('#review-position').textContent='';get('#review-source-date').textContent='';return}
  index=Math.max(0,Math.min(episode.expressions.length-1,index));const card=episode.expressions[index];
  get('#review-position').textContent=`${index+1} / ${episode.expressions.length}`;
  get('#review-source-date').textContent=new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',month:'long',day:'numeric'}).format(new Date(episode.createdAt*1000))+' 추출';
  get('#review-meaning').textContent=card.meaning;get('#review-expression').textContent=card.expression;get('#review-example').textContent=card.example;get('#review-translation').textContent=card.exampleTranslation||'';
  get('#review-answer').hidden=true;get('#review-reveal').hidden=false;get('#review-audio-status').textContent='';
  get('#review-prev').disabled=index===0;get('#review-next').disabled=index===episode.expressions.length-1;get('#review-skip').disabled=index===episode.expressions.length-1;
  const link=get('#review-youtube');link.hidden=!card.youtubeUrl;if(card.youtubeUrl)link.href=card.youtubeUrl;updateSave();remember();
 }
 function move(delta){if(!episode)return;index=Math.max(0,Math.min(episode.expressions.length-1,index+delta));showCard()}
 function reveal(){if(!episode)return;const show=get('#review-answer').hidden;get('#review-answer').hidden=!show;get('#review-reveal').hidden=show}
 async function load(){try{const response=await fetch('/api/sessions',{headers:{'X-English-Token':window.ENGLISH_TOKEN}});if(!response.ok)throw Error('표현을 불러오지 못했습니다.');const data=await response.json();episodes=(data.sessions||[]).filter(s=>s.expressions?.length);const select=get('#review-episode');select.replaceChildren();for(const s of episodes)select.add(new Option(s.title,s.id));episode=episodes[0]||null;if(episode){select.value=episode.id;const n=progress[progressKey()];index=Number.isInteger(n)?n:0}showCard()}catch(e){get('#review-audio-status').textContent=e.message;get('#review-empty').hidden=false}}
 get('#review-episode').onchange=e=>{episode=episodes.find(s=>s.id===e.target.value)||null;const n=episode?progress[progressKey()]:0;index=Number.isInteger(n)?n:0;showCard()};
 get('#review-reveal').onclick=reveal;get('#review-prev').onclick=()=>move(-1);get('#review-next').onclick=()=>move(1);get('#review-skip').onclick=()=>move(1);
 get('#review-listen').onclick=()=>{if(episode)window.OriginalAudio.play(episode,index,1,(message,error)=>{get('#review-audio-status').textContent=message;get('#review-audio-status').classList.toggle('error',Boolean(error))})};
 get('#review-save').onclick=()=>{if(!episode)return;const all=saved(),items=Array.isArray(all[episode.id])?all[episode.id]:[];if(!items.includes(index))items.push(index);all[episode.id]=items;try{localStorage.setItem('english-podcast-saved-v1',JSON.stringify(all));window.dispatchEvent(new Event('english-saved-change'));if(index<episode.expressions.length-1)move(1);else updateSave()}catch{get('#review-audio-status').textContent='표현을 저장하지 못했습니다.'}};
 get('#review-start').onclick=()=>get('#podcast-open').click();
 panel.addEventListener('keydown',e=>{if(!episode||e.isComposing||e.altKey||e.ctrlKey||e.metaKey||document.querySelector('dialog[open]'))return;if(e.target.closest('input,textarea,select,[contenteditable="true"]'))return;const space=e.code==='Space'||e.key===' ';if(!space&&!['ArrowLeft','ArrowRight'].includes(e.key))return;e.preventDefault();if(e.repeat)return;if(space)reveal();else move(e.key==='ArrowRight'?1:-1)});
 window.addEventListener('english-saved-change',updateSave);window.addEventListener('english-podcasts-change',load);load();
})();
