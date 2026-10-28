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
  window.OriginalAudio?.stop();get('#review-complete').hidden=true;get('#review-content').hidden=!episode;get('#review-empty').hidden=Boolean(episode);get('#review-episode').hidden=!episode;
  if(!episode){get('#review-position').textContent='';get('#review-source-date').textContent='';return}
  index=Math.max(0,index);if(index>=episode.expressions.length){finish();return}const card=episode.expressions[index];
  get('#review-position').textContent=`${index+1} / ${episode.expressions.length}`;
  get('#review-source-date').textContent=new Intl.DateTimeFormat('ko-KR',{timeZone:'Asia/Seoul',month:'long',day:'numeric'}).format(new Date(episode.createdAt*1000))+' 추출';
  get('#review-meaning').textContent=card.meaning;get('#review-expression').textContent=card.expression;get('#review-example').textContent=card.sourceSentence||'원문 문장 전체를 확인하지 못했습니다.';get('#review-translation').textContent=card.sourceSentenceTranslation||(card.sourceSentence?'한글 해석을 준비하는 중…':'');
  if(card.sourceSentence&&!card.sourceSentenceTranslation){const current=episode;window.SourceSentences.ensure(current).then(()=>{if(episode===current&&episode.expressions[index]===card)get('#review-translation').textContent=card.sourceSentenceTranslation||'한글 해석을 확인하지 못했습니다.'}).catch(e=>{if(episode===current&&episode.expressions[index]===card)get('#review-translation').textContent=e.message+' 카드를 다시 열면 재시도합니다.'})}
  get('#review-answer').hidden=true;get('#review-reveal').hidden=false;get('#review-audio-status').textContent='';
  get('#review-prev').disabled=index===0;get('#review-next').disabled=false;get('#review-next').textContent=index===episode.expressions.length-1?'학습 마치기 →':'다음 →';get('#review-skip').disabled=false;get('#review-skip').textContent=index===episode.expressions.length-1?'학습 마치기':'그냥 넘기기';
  const link=get('#review-youtube');link.hidden=!card.youtubeUrl;if(card.youtubeUrl)link.href=card.youtubeUrl;updateSave();remember();
 }
 function finish(){
  if(!episode)return;window.OriginalAudio?.stop();index=episode.expressions.length;remember();
  get('#review-content').hidden=true;get('#review-complete').hidden=false;get('#review-position').textContent='완료';
  const count=(saved()[episode.id]||[]).filter(i=>Number.isInteger(i)&&i>=0&&i<episode.expressions.length).length;
  get('#review-complete-summary').textContent=`에피소드 표현 ${episode.expressions.length}개 · 저장한 표현 ${count}개`;
  get('#review-complete-title').focus();
 }
 function move(delta){if(!episode)return;if(index+delta>=episode.expressions.length){finish();return}index=Math.max(0,index+delta);showCard()}
 get('#review-restart').onclick=()=>{index=0;showCard();panel.focus()};
 function reveal(){if(!episode)return;const show=get('#review-answer').hidden;get('#review-answer').hidden=!show;get('#review-reveal').hidden=show}
 async function load(){try{const response=await fetch('/api/sessions',{headers:{'X-English-Token':window.ENGLISH_TOKEN}});if(!response.ok)throw Error('표현을 불러오지 못했습니다.');const data=await response.json();episodes=(data.sessions||[]).filter(s=>s.expressions?.length);const select=get('#review-episode');select.replaceChildren();for(const s of episodes)select.add(new Option(s.title,s.id));episode=episodes[0]||null;if(episode){select.value=episode.id;const n=progress[progressKey()];index=Number.isInteger(n)?n:0}showCard()}catch(e){get('#review-audio-status').textContent=e.message;get('#review-empty').hidden=false}}
 get('#review-episode').onchange=e=>{episode=episodes.find(s=>s.id===e.target.value)||null;const n=episode?progress[progressKey()]:0;index=Number.isInteger(n)?n:0;showCard()};
 get('#review-reveal').onclick=reveal;get('#review-prev').onclick=()=>move(-1);get('#review-next').onclick=()=>move(1);get('#review-skip').onclick=()=>move(1);
 get('#review-listen').onclick=()=>{if(episode)window.OriginalAudio.play(episode,index,1,(message,error)=>{get('#review-audio-status').textContent=message;get('#review-audio-status').classList.toggle('error',Boolean(error))})};
 get('#review-save').onclick=()=>{if(!episode)return;const all=saved(),items=Array.isArray(all[episode.id])?all[episode.id]:[];if(!items.includes(index))items.push(index);all[episode.id]=items;try{localStorage.setItem('english-podcast-saved-v1',JSON.stringify(all));window.dispatchEvent(new Event('english-saved-change'));move(1)}catch{get('#review-audio-status').textContent='표현을 저장하지 못했습니다.'}};
 get('#review-start').onclick=()=>get('#podcast-open').click();
 panel.addEventListener('keydown',e=>{if(!episode||!get('#review-complete').hidden||e.isComposing||e.altKey||e.ctrlKey||e.metaKey||document.querySelector('dialog[open]'))return;if(e.target.closest('input,textarea,select,[contenteditable="true"]'))return;const space=e.code==='Space'||e.key===' ';if(!space&&!['ArrowLeft','ArrowRight','ArrowDown','Enter'].includes(e.key))return;e.preventDefault();if(e.repeat)return;if(space)reveal();else if(e.key==='Enter')get('#review-listen').click();else if(e.key==='ArrowDown')get('#review-save').click();else move(e.key==='ArrowRight'?1:-1)});
 window.addEventListener('english-saved-change',updateSave);window.addEventListener('english-podcasts-change',load);load();
})();
