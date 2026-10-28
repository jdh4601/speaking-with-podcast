const podcastDialog=document.createElement('dialog');podcastDialog.id='podcast-study';podcastDialog.innerHTML=`<div class="study-header"><div><h2>팟캐스트 집중 듣기</h2><span>URL을 넣고 표현 개수를 고르면 바로 학습을 시작합니다</span></div><button id="study-close">닫기 ✕</button></div><div class="study-layout"><section class="study-source"><form id="pod-form"><div class="url-field"><label for="pod-query">YouTube URL</label><input id="pod-query" type="url" required placeholder="https://www.youtube.com/watch?v=…"></div><label class="extract-count" for="pod-count">표현 개수 <select id="pod-count"><option value="10">10개</option><option value="20">20개</option><option value="30">30개</option></select></label><button id="pod-extract" type="submit" class="accent">표현 추출</button></form><div id="pod-progress" hidden><div class="progress-heading"><span id="pod-progress-stage"></span><span id="pod-progress-value"></span></div><progress id="pod-progress-bar" max="100" aria-label="표현 추출 진행 상황" aria-describedby="pod-status"></progress><div class="progress-steps"><span>자막 가져오기</span><span>표현 분석</span><span>결과 준비</span></div></div><p class="pod-status" id="pod-status" role="status"></p></section><section class="study-review"><div class="review-top"><label for="pod-history">학습 기록</label><select id="pod-history"><option value="">에피소드를 선택하세요</option></select></div><div id="pod-empty"><strong>오늘 들은 내용으로 말하기</strong><p>반복해서 쓸 회화 표현을 선택한 개수만큼 고릅니다.<br>원문 인용과 연습용 예문을 구분해 보여줍니다.</p><span>YouTube URL 입력 → 표현 개수 선택 → Enter</span></div><div id="pod-complete" class="study-complete" hidden><span class="completion-mark" aria-hidden="true">✓</span><h3 id="pod-complete-title" tabindex="-1">학습을 마쳤어요</h3><p>이번 에피소드의 표현 복습이 끝났습니다.</p><p id="pod-complete-summary"></p><div class="completion-actions"><button id="pod-restart" class="accent">처음부터 다시 보기</button><a href="library.html">저장한 표현 보기 ↗</a></div></div><div id="pod-deck" hidden><div class="deck-meta"><span id="pod-card-counter"></span><button id="pod-known">저장한 표현 0개</button></div><div class="recall-card"><span class="card-label">뜻을 보고 영어로 말해보세요</span><h3 id="pod-meaning"></h3><button id="pod-reveal">영어 표현 확인</button><div id="pod-answer" hidden><h4 id="pod-expression"></h4><div class="say-row"><button id="pod-speak" aria-keyshortcuts="Enter">원문 문장 듣기</button><button id="pod-repeat">3번 반복</button></div><a id="pod-youtube" target="_blank" rel="noopener" hidden>YouTube에서 해당 구간 보기 ↗</a><label>영상 원문 문장</label><blockquote id="pod-quote"></blockquote><p id="pod-source-translation" class="source-translation"></p><label>새로 만든 연습 예문</label><p id="pod-example"></p><p id="pod-tip"></p></div></div><div class="grade-actions"><button id="pod-again">그냥 넘기기</button><button id="pod-good" class="accent" aria-keyshortcuts="ArrowDown">표현 저장하기</button></div><div class="keyboard-hint">Space 답 확인 · ← → 카드 이동 · ↓ 표현 저장 · Enter 음성 재생</div><div class="deck-nav"><button id="pod-prev">← 이전</button><button id="pod-reset">처음부터 보기</button><button id="pod-next">다음 →</button></div></div></section></div>`;document.body.append(podcastDialog);
const pe=s=>podcastDialog.querySelector(s);let sessions=[],activeSession=null,cardIndex=0,sourceDraft=null,busy=false;
async function api(path,data){const r=await fetch('/api/'+path,{method:data?'POST':'GET',headers:{'X-English-Token':window.ENGLISH_TOKEN,'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});const body=await r.json();if(!r.ok)throw Error(body.error||'요청에 실패했습니다.');return body}
function status(s,error=false){pe('#pod-status').textContent=s;pe('#pod-status').classList.toggle('error',error)}
function setBusy(value){busy=value;['#pod-query','#pod-extract','#pod-count','#pod-history'].forEach(s=>pe(s).disabled=value);pe('#pod-form').setAttribute('aria-busy',String(value));pe('#pod-extract').textContent=value?'추출 중…':'표현 추출'}
function progress(stage,value=null){pe('#pod-progress').hidden=false;pe('#pod-progress-stage').textContent=stage;const bar=pe('#pod-progress-bar');if(value===null){bar.removeAttribute('value');pe('#pod-progress-value').textContent='진행 중'}else{bar.value=value;pe('#pod-progress-value').textContent=value+'%'}}
function extractionProgress(message){
    const chunk=message.match(/전사 분석 (\d+) \/ (\d+)/);
    if(chunk)progress('2 / 3 · 표현 분석',20+Math.floor(65*(Number(chunk[1])-1)/Number(chunk[2])));
    else if(message.includes('분석 완료'))progress('3 / 3 · 결과 준비',90);
    status(message);
}
async function job(kind,data){const {job}=await api(kind,data);for(;;){await new Promise(r=>setTimeout(r,1000));const v=await api('jobs/'+job);if(v.progress)extractionProgress(v.progress);if(v.status==='error')throw Error(v.error);if(v.status==='done')return v.result}}
function canonicalYouTube(value){try{const u=new URL(value);if(u.protocol!=='https:'||!['youtube.com','www.youtube.com','m.youtube.com','youtu.be'].includes(u.hostname))return null;const id=u.hostname==='youtu.be'?u.pathname.slice(1):u.pathname.startsWith('/shorts/')?u.pathname.split('/')[2]:u.searchParams.get('v');return /^[A-Za-z0-9_-]{11}$/.test(id||'')?'https://www.youtube.com/watch?v='+id:null}catch{return null}}
function renderCard(){if(!activeSession)return;pe('#pod-complete').hidden=true;const cards=activeSession.expressions,c=cards[cardIndex];pe('#pod-empty').hidden=true;pe('#pod-deck').hidden=false;pe('#pod-card-counter').textContent=`${cardIndex+1} / ${cards.length}`;const selectedSaved=savedExpressions[activeSession.id]||[];pe('#pod-known').textContent=`저장한 표현 ${Object.values(savedExpressions).reduce((n,items)=>n+items.length,0)}개`;pe('#pod-meaning').textContent=c.meaning;pe('#pod-expression').textContent=c.expression;pe('#pod-quote').textContent=c.sourceSentence||'원문 문장 전체를 확인하지 못했습니다.';pe('#pod-source-translation').textContent=c.sourceSentenceTranslation||(c.sourceSentence?'한글 해석을 준비하는 중…':'');if(c.sourceSentence&&!c.sourceSentenceTranslation){const current=activeSession;window.SourceSentences.ensure(current).then(()=>{if(activeSession===current&&current.expressions[cardIndex]===c)pe('#pod-source-translation').textContent=c.sourceSentenceTranslation||'한글 해석을 확인하지 못했습니다.'}).catch(e=>{if(activeSession===current&&current.expressions[cardIndex]===c)pe('#pod-source-translation').textContent=e.message+' 카드를 다시 열면 재시도합니다.'})}pe('#pod-example').textContent=c.example;pe('#pod-tip').textContent=c.tip;const jump=pe('#pod-youtube');jump.hidden=!c.youtubeUrl;if(c.youtubeUrl){jump.href=c.youtubeUrl;jump.textContent=`YouTube에서 ${Math.floor(c.youtubeStart/60)}:${String(c.youtubeStart%60).padStart(2,'0')} 구간 보기 ↗`}pe('#pod-answer').hidden=true;pe('#pod-reveal').hidden=false;pe('#pod-good').disabled=selectedSaved.includes(cardIndex);pe('#pod-good').textContent=selectedSaved.includes(cardIndex)?'저장됨 ✓':'표현 저장하기';pe('#pod-prev').disabled=cardIndex===0;pe('#pod-next').disabled=false;pe('#pod-next').textContent=cardIndex===cards.length-1?'학습 마치기 →':'다음 →';pe('#pod-again').textContent=cardIndex===cards.length-1?'학습 마치기':'그냥 넘기기';window.OriginalAudio?.stop()}
function setSession(id){activeSession=sessions.find(s=>s.id===id)||null;cardIndex=0;if(!activeSession)return;pe('#pod-history').value=id;renderCard()}
async function loadSessions(){try{sessions=(await api('sessions')).sessions;const select=pe('#pod-history');select.replaceChildren(new Option('에피소드를 선택하세요',''));for(const s of sessions)select.add(new Option(s.title,s.id));if(activeSession)select.value=activeSession.id}catch(e){status(e.message,true)}}
pe('#pod-count').onchange=saveDraft;
pe('#pod-query').oninput=saveDraft;
pe('#pod-form').onsubmit=async event=>{
    event.preventDefault();if(busy)return;
    const url=canonicalYouTube(pe('#pod-query').value.trim());
    if(!url){status('YouTube 영상의 HTTPS URL을 입력하세요.',true);return}
    const count=Number(pe('#pod-count').value);
    setBusy(true);saveDraft();
    try{
        activeSession=null;pe('#pod-complete').hidden=true;pe('#pod-deck').hidden=true;pe('#pod-empty').hidden=false;window.OriginalAudio?.stop();
        progress('1 / 3 · 자막 가져오기');status('YouTube 영어 자막과 시간정보를 가져오는 중…');
        if(!sourceDraft||canonicalYouTube(sourceDraft.url)!==url)sourceDraft=await job('transcript',{url});
        saveDraft();progress('2 / 3 · 표현 분석',20);status(`전사를 분석해 표현 ${count}개를 고르는 중…`);
        const d=await job('extract',{title:sourceDraft.title,transcript:sourceDraft.transcript,url:sourceDraft.url,captionType:sourceDraft.captionType,count});
        progress('3 / 3 · 결과 준비',95);await loadSessions();setSession(d.id);
        window.dispatchEvent(new Event('english-podcasts-change'));
        sourceDraft=null;try{localStorage.removeItem('english-podcast-draft-v1')}catch{}
        progress('추출 완료',100);status(`표현 ${d.expressions.length}개를 추출했습니다. 뜻을 보고 영어로 말해보세요.`);
        pe('#pod-reveal').focus();
    }catch(e){pe('#pod-progress').hidden=true;status(e.message+' URL을 확인하고 다시 시도하세요.',true)}
    finally{setBusy(false)}
};
// Enter from either input control submits the same extraction flow.
pe('#pod-count').onkeydown=event=>{if(event.key==='Enter'){event.preventDefault();pe('#pod-form').requestSubmit()}};
pe('#pod-history').onchange=e=>{if(e.target.value)setSession(e.target.value)};pe('#pod-reveal').onclick=()=>{pe('#pod-answer').hidden=false;pe('#pod-reveal').hidden=true};pe('#pod-prev').onclick=()=>{cardIndex=Math.max(0,cardIndex-1);renderCard()};pe('#pod-next').onclick=nextExpression;
function nextExpression(){
    if(!activeSession)return;
    if(cardIndex<activeSession.expressions.length-1){cardIndex++;renderCard()}
    else finishStudy();
}
function finishStudy(){
    if(!activeSession)return;window.OriginalAudio?.stop();pe('#pod-deck').hidden=true;pe('#pod-complete').hidden=false;
    const count=(savedExpressions[activeSession.id]||[]).filter(i=>Number.isInteger(i)&&i>=0&&i<activeSession.expressions.length).length;
    pe('#pod-complete-summary').textContent=`에피소드 표현 ${activeSession.expressions.length}개 · 저장한 표현 ${count}개`;
    pe('#pod-complete-title').focus();
}
pe('#pod-restart').onclick=()=>{cardIndex=0;renderCard();pe('#pod-reveal').focus()};
pe('#pod-again').onclick=nextExpression;
pe('#pod-good').onclick=()=>{
    if(!activeSession)return;
    const items=savedExpressions[activeSession.id]||[];
    if(!items.includes(cardIndex))items.push(cardIndex);
    savedExpressions[activeSession.id]=items;
    if(!persistSaved())return;
    status('표현을 저장했습니다.');
    nextExpression();
};
pe('#pod-reset').onclick=()=>{if(!activeSession)return;cardIndex=0;renderCard()};

function speak(times){if(!activeSession)return;window.OriginalAudio.play(activeSession,cardIndex,times,status)}
pe('#pod-speak').onclick=()=>speak(1);pe('#pod-repeat').onclick=()=>speak(3);document.querySelector('#podcast-open').onclick=async()=>{podcastDialog.showModal();await loadSessions();if(!busy){const hasDraft=await restoreDraft();if(!hasDraft&&!activeSession&&sessions.length)setSession(sessions[0].id)}try{const health=await api('health');if(!health.codex)status('Codex CLI를 찾지 못했습니다.',true)}catch(e){status(e.message,true)}};pe('#study-close').onclick=()=>podcastDialog.close();podcastDialog.addEventListener('close',()=>window.OriginalAudio?.stop());

// Card shortcuts stay inactive while editing source text or using form controls.
function toggleCardAnswer(){
    const reveal=pe('#pod-answer').hidden;
    pe('#pod-answer').hidden=!reveal;
    pe('#pod-reveal').hidden=reveal;
}
document.addEventListener('keydown',event=>{
    if(!podcastDialog.open||!activeSession||busy||pe('#pod-deck').hidden)return;
    if(event.isComposing||event.altKey||event.ctrlKey||event.metaKey)return;
    if(event.target instanceof Element&&event.target.closest('input,textarea,select,[contenteditable]:not([contenteditable="false"]),[role="textbox"]'))return;
    const isSpace=event.code==='Space'||event.key===' ';
    if(!isSpace&&!['ArrowLeft','ArrowRight','ArrowDown','Enter'].includes(event.key))return;
    event.preventDefault();
    if(event.repeat)return;
    if(isSpace)toggleCardAnswer();
    else if(event.key==='Enter')speak(1);
    else if(event.key==='ArrowDown')pe('#pod-good').click();
    else if(event.key==='ArrowLeft'&&!pe('#pod-prev').disabled)pe('#pod-prev').click();
    else if(event.key==='ArrowRight'&&!pe('#pod-next').disabled)pe('#pod-next').click();
},true);

let savedExpressions={};
try{const value=JSON.parse(localStorage.getItem('english-podcast-saved-v1')||'{}');if(value&&typeof value==='object'&&!Array.isArray(value)){for(const [id,items] of Object.entries(value)){if(Array.isArray(items))savedExpressions[id]=[...new Set(items.filter(i=>Number.isInteger(i)&&i>=0))]}}}catch{}
function persistSaved(){try{localStorage.setItem('english-podcast-saved-v1',JSON.stringify(savedExpressions));window.dispatchEvent(new Event('english-saved-change'));return true}catch{status('표현을 저장하지 못했습니다. 저장소를 확인하세요.',true);return false}}
function showSavedExpressions(){window.location.href='/library.html'}
pe('#pod-known').onclick=showSavedExpressions;

function saveDraft(){try{localStorage.setItem('english-podcast-draft-v1',JSON.stringify({url:pe('#pod-query').value,count:Number(pe('#pod-count').value),source:sourceDraft}))}catch{}}
async function restoreDraft(){
 try{
  let draft=JSON.parse(localStorage.getItem('english-podcast-draft-v1')||'null');
  if(!draft&&!localStorage.getItem('english-podcast-recovered-v1')){draft=await api('draft');localStorage.setItem('english-podcast-recovered-v1','1')}
  if(!draft?.url)return false;
  sourceDraft=draft.source||(draft.transcript?draft:null);
  pe('#pod-query').value=draft.url;pe('#pod-count').value=[10,20,30].includes(draft.count)?draft.count:10;
  activeSession=null;pe('#pod-complete').hidden=true;pe('#pod-deck').hidden=true;pe('#pod-empty').hidden=false;return true;
 }catch{return false}
}

window.addEventListener('english-saved-change',()=>{try{savedExpressions=JSON.parse(localStorage.getItem('english-podcast-saved-v1')||'{}');if(activeSession&&podcastDialog.open&&pe('#pod-complete').hidden)renderCard()}catch{}});
