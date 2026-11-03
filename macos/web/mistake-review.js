(function(){
const STORAGE_KEY='english-mistake-mastered-v1';
const TOP_CATEGORIES=3;
const pick=selector=>document.querySelector(selector);
const{highlightParts,reviewQueue,lessonPriorities}=window.ConversationCore;
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
 for(const name of ['#mistake-summary','#mistake-card','#mistake-empty','#mistake-error'])pick(name).hidden=name!==id;
}

function textNode(tag,text,className){
 const node=document.createElement(tag);
 node.textContent=text;
 if(className)node.className=className;
 return node;
}

function highlightedSentence(node,mistake){
 node.replaceChildren(...highlightParts(mistake.sentence,mistake.wrong).map(part=>
  part.marked?textNode('mark',part.text,'mistake'):document.createTextNode(part.text)));
 return node;
}

function setHeading(title,kicker){
 pick('#mistake-title').textContent=title;
 pick('#mistake-kicker').textContent=kicker;
}

function priorityItem(item){
 const row=document.createElement('li');
 const heading=document.createElement('div');
 heading.className='priority-head';
 heading.append(textNode('strong',item.category),textNode('span',`${item.count}회`));
 row.append(
  heading,
  highlightedSentence(textNode('p','','priority-sentence'),item.example),
  textNode('p',item.example.corrected,'priority-corrected'),
  textNode('p',item.example.rule,'priority-rule'),
 );
 return row;
}

function showSummary(){
 const{date,items}=lessonPriorities(sessions);
 setHeading('지난 수업에서 개선할 점',date?`${date} 수업 기준`:'내 회화 기록에서');
 pick('#mistake-position').textContent='';
 if(!items.length){
  pick('#mistake-empty-text').textContent=date?'지난 수업에서 찾은 실수가 없습니다.':'아직 분석한 회화가 없습니다.';
  showOnly('#mistake-empty');
  return;
 }
 pick('#mistake-priorities').replaceChildren(...items.map(priorityItem));
 pick('#mistake-start').disabled=!queue.length;
 pick('#mistake-start').textContent=queue.length?'복습 시작하기':'복습할 표현을 모두 외웠습니다';
 showOnly('#mistake-summary');
}

function startReview(){
 position=0;
 setHeading('자주 틀리는 표현 복습','내 회화 기록에서');
 renderCard();
 panel.focus();
}

function renderCard(){
 pick('#mistake-position').textContent=queue.length?`${position+1} / ${queue.length}`:'';
 if(!queue.length){
  showSummary();
  return;
 }
 const card=queue[position];
 pick('#mistake-meaning').textContent=card.translation;
 highlightedSentence(pick('#mistake-sentence'),card);
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
  showSummary();
 }catch(error){
  pick('#mistake-error-text').textContent=`회화 기록을 불러오지 못했습니다: ${error.message}`;
  showOnly('#mistake-error');
 }
}

pick('#mistake-start').onclick=startReview;
pick('#mistake-stop').onclick=showSummary;
pick('#mistake-reveal').onclick=reveal;
pick('#mistake-next').onclick=nextCard;
pick('#mistake-known').onclick=markKnown;
pick('#mistake-retry').onclick=load;
panel.addEventListener('keydown',event=>{
 if(event.target!==panel||pick('#mistake-card').hidden)return;
 if(event.key===' '){event.preventDefault();reveal()}
 if(event.key==='ArrowRight'){event.preventDefault();nextCard()}
});
load();
})();
