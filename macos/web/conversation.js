const {highlightParts,metricTrend}=window.ConversationCore;
const POLL_MS=1500;
const DIRECTION_TEXT={better:'개선',worse:'악화',same:'동일',baseline:'첫 기록: 기준선'};
const FLAG_TITLES={pronunciation:'발음 확인 필요',transcription:'받아쓰기 확인 필요'};
const pick=selector=>document.querySelector(selector);
let report={conversations:[],skipped:0,frequency:{categories:[],patterns:[]}};
let selectedId=null;

async function callApi(path,data){
 const response=await fetch('/api/'+path,{
  method:data?'POST':'GET',
  headers:{'X-English-Token':window.ENGLISH_TOKEN,'Content-Type':'application/json'},
  body:data?JSON.stringify(data):undefined,
 });
 const result=await response.json();
 if(!response.ok)throw Error(result.error||'요청에 실패했습니다.');
 return result;
}

async function waitForJob(job,onProgress){
 for(;;){
  const state=await callApi('jobs/'+job);
  if(state.status==='done')return state.result;
  if(state.status==='error')throw Error(state.error);
  if(state.progress)onProgress(state.progress);
  await new Promise(resolve=>setTimeout(resolve,POLL_MS));
 }
}

function element(tag,text,className){
 const node=document.createElement(tag);
 if(text!==undefined)node.textContent=text;
 if(className)node.className=className;
 return node;
}

function highlighted(tag,sentence,target,markTag,markClass,className){
 const node=element(tag,undefined,className);
 for(const part of highlightParts(sentence,target))
  node.append(part.marked?element(markTag,part.text,markClass):part.text);
 return node;
}

function todayInSeoul(){
 return new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
}

function formatDelta(delta){return`${delta>0?'+':''}${delta}`}

function chart(metric){
 const NS='http://www.w3.org/2000/svg',width=200,height=56,padding=8;
 const svg=document.createElementNS(NS,'svg');
 svg.setAttribute('class','trend-chart');
 svg.setAttribute('viewBox',`0 0 ${width} ${height}`);
 svg.setAttribute('preserveAspectRatio','none');
 svg.setAttribute('role','img');
 svg.setAttribute('aria-label',`${metric.label} 회차별 값: ${metric.values.join(', ')}`);
 const low=Math.min(...metric.values),high=Math.max(...metric.values),span=high-low||1;
 const points=metric.values.map((value,index)=>({
  value,
  x:metric.values.length>1?padding+index*(width-2*padding)/(metric.values.length-1):width/2,
  y:height-padding-(value-low)/span*(height-2*padding),
 }));
 const line=document.createElementNS(NS,'polyline');
 line.setAttribute('points',points.map(point=>`${point.x},${point.y}`).join(' '));
 svg.append(line);
 points.forEach((point,index)=>{
  const mark=document.createElementNS(NS,'circle');
  mark.setAttribute('cx',point.x);mark.setAttribute('cy',point.y);mark.setAttribute('r',4);
  const hit=document.createElementNS(NS,'circle');
  hit.setAttribute('class','hit');hit.setAttribute('cx',point.x);hit.setAttribute('cy',point.y);hit.setAttribute('r',14);
  const tip=document.createElementNS(NS,'title');
  tip.textContent=`${report.conversations[index].date}: ${point.value}${metric.unit}`;
  hit.append(tip);
  svg.append(mark,hit);
 });
 return svg;
}

function renderTrend(){
 const trend=metricTrend(report.conversations),grid=pick('#trend-grid');
 grid.replaceChildren();
 if(!report.conversations.length){grid.append(element('p','분석한 회차가 없습니다.','empty-note'));pick('#trend-table').replaceChildren();return}
 for(const metric of trend){
  const card=element('div',undefined,'trend-card');
  const value=element('strong',String(metric.latest),'trend-value');
  value.append(element('small',metric.unit));
  const change=metric.direction==='baseline'?DIRECTION_TEXT.baseline:`직전 대비 ${formatDelta(metric.delta)} · ${DIRECTION_TEXT[metric.direction]}`;
  card.append(element('span',metric.label,'trend-label'),value,element('span',change,'trend-change'));
  card.append(chart(metric));
  grid.append(card);
 }
 renderTrendTable(trend);
}

function tableOf(headers,rows){
 const table=element('table',undefined,'report-table'),head=element('tr');
 headers.forEach(header=>head.append(element('th',header)));
 table.append(head);
 for(const row of rows){
  const line=element('tr');
  row.forEach(cell=>line.append(cell instanceof Node?cell:element('td',String(cell))));
  table.append(line);
 }
 return table;
}

function renderTrendTable(trend){
 const rows=report.conversations.map(session=>[session.date,...trend.map(metric=>session.metrics[metric.key])]);
 pick('#trend-table').replaceChildren(tableOf(['날짜',...trend.map(metric=>metric.label)],rows));
}

function renderRepeatList(selector,items){
 const list=pick(selector);
 list.replaceChildren();
 if(!items.length){list.append(element('li','아직 기록이 없습니다.','empty-note'));return}
 for(const item of items.slice(0,10)){
  const row=element('li');
  row.append(element('span',item.name),element('span',`${item.total}회`,'repeat-count'));
  row.append(element('span',`${item.sessions}개 회차에서 발생 · 최근 회차별 ${item.recent.join(' → ')}`,'repeat-detail'));
  list.append(row);
 }
}

function selectedSession(){return report.conversations.find(session=>session.id===selectedId)}

function renderMistakes(session){
 const box=pick('#session-mistakes');
 box.replaceChildren();
 if(!session)return;
 if(!session.mistakes.length){box.append(element('p','이 회차에서 찾은 실수가 없습니다.','empty-note'));return}
 for(const mistake of session.mistakes){
  const item=element('article',undefined,'mistake-item');
  item.append(highlighted('p',mistake.sentence,mistake.wrong,'mark','mistake','mistake-sentence'));
  item.append(element('p',mistake.corrected,'mistake-corrected'),element('p',mistake.translation,'mistake-translation'));
  const rule=element('p',undefined,'mistake-rule');
  rule.append(element('span',mistake.category,'mistake-tag'),mistake.rule);
  item.append(rule);
  box.append(item);
 }
}

function renderVocabulary(session){
 const box=pick('#session-vocabulary');
 box.replaceChildren();
 if(!session)return;
 if(!session.vocabulary.length){box.append(element('p','정리한 단어가 없습니다.','empty-note'));return}
 const rows=session.vocabulary.map(word=>[word.term,word.meaning,highlighted('td',word.example,word.target,'em','vocab-target')]);
 box.append(tableOf(['단어','뜻','예문'],rows));
}

function renderFlags(session){
 const box=pick('#session-flags');
 box.replaceChildren();
 for(const[kind,title]of Object.entries(FLAG_TITLES)){
  const flags=(session?.reviewFlags||[]).filter(flag=>flag.kind===kind);
  if(!flags.length)continue;
  const list=element('ul',undefined,'flag-list');
  flags.forEach(flag=>list.append(element('li',`"${flag.quote}": ${flag.note}`)));
  box.append(element('h3',title),list);
 }
}

function renderSession(){
 const select=pick('#session-select'),conversations=[...report.conversations].reverse();
 select.replaceChildren(...conversations.map(session=>new Option(session.date,session.id)));
 select.hidden=!conversations.length;
 if(!selectedSession())selectedId=conversations[0]?.id||null;
 if(selectedId)select.value=selectedId;
 const session=selectedSession(),dropped=pick('#dropped-note');
 pick('#session-delete').hidden=!session;
 dropped.hidden=!session?.droppedItems;
 dropped.textContent=session?.droppedItems?`스크립트와 대조되지 않은 분석 항목 ${session.droppedItems}개를 제외했습니다.`:'';
 renderMistakes(session);renderVocabulary(session);renderFlags(session);
}

function render(){
 const skipped=pick('#skipped-note');
 skipped.hidden=!report.skipped;
 skipped.textContent=report.skipped?`읽지 못한 기록 ${report.skipped}개가 있습니다.`:'';
 renderTrend();
 renderRepeatList('#repeat-categories',report.frequency.categories);
 renderRepeatList('#repeat-patterns',report.frequency.patterns);
 renderSession();
}

async function loadReport(){
 const failure=pick('#load-error');
 try{
  report=await callApi('conversations');
  failure.hidden=true;
  render();
 }catch(error){
  failure.textContent=`기록을 불러오지 못했습니다: ${error.message}`;
  failure.hidden=false;
 }
}

async function analyze(){
 const button=pick('#analyze'),status=pick('#analyze-status');
 button.disabled=true;
 status.textContent='분석을 시작합니다.';
 try{
  const{job}=await callApi('conversation-analyze',{script:pick('#script-input').value,date:pick('#session-date').value});
  const saved=await waitForJob(job,message=>{status.textContent=message});
  selectedId=saved.id;
  pick('#script-input').value='';
  status.textContent='분석을 마쳤습니다.';
  await loadReport();
 }catch(error){
  status.textContent=error.message;
 }finally{
  button.disabled=false;
 }
}

async function deleteSelected(){
 const status=pick('#analyze-status');
 pick('#delete-dialog').close();
 try{
  const{job}=await callApi('conversation-delete',{id:selectedId});
  await waitForJob(job,()=>{});
  selectedId=null;
  status.textContent='회차를 삭제했습니다.';
  await loadReport();
 }catch(error){
  status.textContent=error.message;
 }
}

pick('#session-date').value=todayInSeoul();
pick('#analyze').onclick=analyze;
pick('#session-select').onchange=event=>{selectedId=event.target.value;renderSession()};
pick('#session-delete').onclick=()=>pick('#delete-dialog').showModal();
pick('#delete-cancel').onclick=()=>pick('#delete-dialog').close();
pick('#delete-confirm').onclick=deleteSelected;
loadReport();
