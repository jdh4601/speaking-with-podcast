(function(){
const STORAGE_KEY='english-mistake-mastered-v1';
const TOP_CATEGORIES=3;
const pick=selector=>document.querySelector(selector);
const{highlightParts,reviewQueue,lessonPriorities,lessonGroups,lessonOptions,metricTrend}=window.ConversationCore;
const panel=pick('#mistake-review');
let sessions=[],queue=[],position=0,mastered=readMastered(),selectedLessonId=null;

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

function highlightedText(node,text,target,markClass){
 node.replaceChildren(...highlightParts(text,target).map(part=>
  part.marked?textNode('mark',part.text,markClass):document.createTextNode(part.text)));
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
  highlightedText(textNode('p','','priority-sentence'),item.example.sentence,item.example.wrong,'mistake'),
  highlightedText(textNode('p','','priority-corrected'),item.example.corrected,item.example.fixed,'fixed'),
  textNode('p',item.example.rule,'priority-rule'),
 );
 return row;
}

function selectedLesson(){
 const lesson=sessions.find(session=>session.id===selectedLessonId)||sessions.at(-1);
 return lesson?[lesson]:[];
}

function renderLessonPicker(){
 const picker=pick('#mistake-lesson');
 picker.replaceChildren(...lessonOptions(sessions).map(option=>new Option(option.label,option.id)));
 const[lesson]=selectedLesson();
 if(lesson)picker.value=lesson.id;
}

function speakingMetricCard(metric){
 const card=document.createElement('section');
 card.className='speaking-metric';
 card.append(textNode('h3',metric.label));
 if(!metric.samples.length){
  card.append(textNode('p','기록 없음','speaking-metric-empty'));
  return card;
 }
 const latest=textNode('p',`${metric.latest}${metric.unit}`,'speaking-metric-value');
 const scroll=document.createElement('div');
 scroll.className='speaking-metric-scroll';
 scroll.setAttribute('aria-label',`${metric.label} 수업별 기록`);
 scroll.setAttribute('role','region');
 scroll.tabIndex=0;
 scroll.append(window.ConversationTrend.chart(metric,{showValues:true}));
 card.append(latest,scroll);
 return card;
}

function showSpeakingTrend(message){
 const grid=pick('#speaking-trend-data'),status=pick('#speaking-trend-status');
 const metrics=message?[]:metricTrend(sessions);
 const hasData=metrics.some(metric=>metric.samples.length);
 grid.replaceChildren(...(hasData?metrics.map(speakingMetricCard):[]));
 grid.hidden=!hasData;
 status.hidden=hasData;
 for(const scroll of grid.querySelectorAll('.speaking-metric-scroll'))scroll.scrollLeft=scroll.scrollWidth;
 if(!hasData)status.textContent=message||'회화 리포트에서 수업을 분석하면 회차별 변화가 표시됩니다.';
}

function showSummary(){
 pick('#mistake-all').hidden=true;
 pick('#mistake-lesson').hidden=!sessions.length;
 const{date,items}=lessonPriorities(selectedLesson());
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
 pick('#mistake-all').hidden=false;
 showOnly('#mistake-summary');
}

function allPriorityRow(mistake){
 const row=document.createElement('li');
 // Records from before the fixed field existed still show the whole correction.
 row.append(
  textNode('mark',mistake.wrong,'mistake'),
  textNode('span',' → ','all-arrow'),
  mistake.fixed?textNode('mark',mistake.fixed,'fixed'):textNode('span',mistake.corrected),
 );
 return row;
}

function allPriorityGroup(group){
 const section=document.createElement('section');
 const heading=document.createElement('div');
 heading.className='priority-head';
 heading.append(textNode('strong',group.category),textNode('span',`${group.mistakes.length}회`));
 const list=document.createElement('ul');
 list.append(...group.mistakes.map(allPriorityRow));
 section.append(heading,list);
 return section;
}

function showAllPriorities(){
 const{date,groups}=lessonGroups(selectedLesson());
 const total=groups.reduce((sum,group)=>sum+group.mistakes.length,0);
 pick('#all-priorities-date').textContent=`${date} 수업 · 총 ${total}건`;
 pick('#all-priorities-list').replaceChildren(...groups.map(allPriorityGroup));
 pick('#all-priorities').showModal();
}

function startReview(){
 pick('#mistake-all').hidden=true;
 pick('#mistake-lesson').hidden=true;
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
 highlightedText(pick('#mistake-sentence'),card.sentence,card.wrong,'mistake');
 highlightedText(pick('#mistake-corrected'),card.corrected,card.fixed,'fixed');
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
  selectedLessonId=null;
  renderLessonPicker();
  showSummary();
  showSpeakingTrend();
 }catch(error){
  showSpeakingTrend('회화 기록을 불러오지 못했습니다.');
  pick('#mistake-error-text').textContent=`회화 기록을 불러오지 못했습니다: ${error.message}`;
  showOnly('#mistake-error');
 }
}

pick('#mistake-start').onclick=startReview;
pick('#mistake-lesson').onchange=event=>{selectedLessonId=event.target.value;showSummary()};
pick('#mistake-all').onclick=showAllPriorities;
pick('#all-priorities-close').onclick=()=>pick('#all-priorities').close();
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
