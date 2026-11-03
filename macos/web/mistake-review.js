(function(){
const STORAGE_KEY='english-mistake-mastered-v1';
const TOP_CATEGORIES=3;
const pick=selector=>document.querySelector(selector);
const{highlightParts,reviewQueue}=window.ConversationCore;
const panel=pick('#mistake-review');
let sessions=[],queue=[],position=0,mastered=readMastered();

function readMastered(){
 try{
  const saved=JSON.parse(localStorage.getItem(STORAGE_KEY));
  return saved&&typeof saved==='object'?saved:{};
 }catch(error){
  console.error('복습 표시를 읽지 못했습니다.',error);
  return{};
 }
}

function saveMastered(){
 try{
  localStorage.setItem(STORAGE_KEY,JSON.stringify(mastered));
 }catch(error){
  console.error('복습 표시를 저장하지 못했습니다.',error);
 }
}

function showOnly(id){
 for(const name of ['#mistake-card','#mistake-empty','#mistake-error'])pick(name).hidden=name!==id;
}

function renderTop(categories){
 const chips=categories.slice(0,TOP_CATEGORIES).map(item=>{
  const chip=document.createElement('span');
  chip.className='mistake-chip';
  chip.textContent=`${item.name} ${item.total}회`;
  return chip;
 });
 pick('#mistake-top').replaceChildren(...chips);
}

function renderSentence(card){
 const sentence=pick('#mistake-sentence');
 sentence.replaceChildren();
 for(const part of highlightParts(card.sentence,card.wrong)){
  if(!part.marked){sentence.append(part.text);continue}
  const mark=document.createElement('mark');
  mark.className='mistake';
  mark.textContent=part.text;
  sentence.append(mark);
 }
}

function renderCard(){
 pick('#mistake-position').textContent=queue.length?`${position+1} / ${queue.length}`:'';
 if(!queue.length){
  pick('#mistake-empty-text').textContent=sessions.length?'지금 복습할 표현을 모두 외웠습니다.':'아직 분석한 회화가 없습니다.';
  showOnly('#mistake-empty');
  return;
 }
 const card=queue[position];
 pick('#mistake-meaning').textContent=card.translation;
 renderSentence(card);
 pick('#mistake-corrected').textContent=card.corrected;
 pick('#mistake-rule').textContent=`${card.category} · ${card.patternTotal}회 · ${card.rule}`;
 pick('#mistake-answer').hidden=true;
 pick('#mistake-reveal').hidden=false;
 showOnly('#mistake-card');
}

function reveal(){
 pick('#mistake-answer').hidden=false;
 pick('#mistake-reveal').hidden=true;
}

function nextCard(){
 if(!queue.length)return;
 position=(position+1)%queue.length;
 renderCard();
}

function markKnown(){
 const card=queue[position];
 mastered={...mastered,[card.pattern]:card.latestDate};
 saveMastered();
 queue=reviewQueue(sessions,mastered);
 position=queue.length?position%queue.length:0;
 renderCard();
}

async function load(){
 try{
  const response=await fetch('/api/conversations',{headers:{'X-English-Token':window.ENGLISH_TOKEN}});
  const report=await response.json();
  if(!response.ok)throw Error(report.error||'요청에 실패했습니다.');
  sessions=report.conversations;
  queue=reviewQueue(sessions,mastered);
  position=0;
  renderTop(report.frequency.categories);
  renderCard();
 }catch(error){
  pick('#mistake-error-text').textContent=`회화 기록을 불러오지 못했습니다: ${error.message}`;
  showOnly('#mistake-error');
 }
}

pick('#mistake-reveal').onclick=reveal;
pick('#mistake-next').onclick=nextCard;
pick('#mistake-known').onclick=markKnown;
pick('#mistake-retry').onclick=load;
panel.addEventListener('keydown',event=>{
 if(event.target!==panel)return;
 if(event.key===' '){event.preventDefault();reveal()}
 if(event.key==='ArrowRight'){event.preventDefault();nextCard()}
});
load();
})();
