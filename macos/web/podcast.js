const podcastDialog=document.createElement('dialog');podcastDialog.id='podcast-study';podcastDialog.innerHTML=`<div class="study-header"><div><h2>팟캐스트 집중 듣기</h2><span>전사 → 회화 표현 추출 → 반복 학습 · Codex CLI</span></div><button id="study-close">닫기 ✕</button></div><div class="study-layout"><section class="study-source"><label for="pod-query">YouTube URL</label><div class="query-row"><input id="pod-query" placeholder="https://www.youtube.com/watch?v=…"><button id="pod-search">스크립트 가져오기</button></div><div id="pod-results"></div><label for="pod-title">학습할 에피소드 제목</label><input id="pod-title" placeholder="제목을 확인하거나 직접 입력하세요"><a id="pod-source" target="_blank" rel="noopener" hidden>원본 열기 ↗</a><label for="pod-transcript">영어 전사 <span id="pod-caption-type">직접 붙여넣기도 가능</span></label><textarea id="pod-transcript" placeholder="공개 영어 자막을 가져오거나 영어 전사를 붙여넣으세요. 자동 자막은 원음과 대조하세요."></textarea><div class="transcript-footer"><span id="pod-char-count">0자</span><label class="extract-count" for="pod-count">표현 개수 <select id="pod-count"><option value="10">10개</option><option value="20">20개</option><option value="30">30개</option></select></label><button id="pod-extract" class="accent">표현 추출</button></div><p class="pod-status" id="pod-status" role="status"></p></section><section class="study-review"><div class="review-top"><label for="pod-history">학습 기록</label><select id="pod-history"><option value="">에피소드를 선택하세요</option></select></div><div id="pod-empty"><strong>오늘 들은 내용으로 말하기</strong><p>반복해서 쓸 회화 표현을 선택한 개수만큼 고릅니다.<br>원문 인용과 연습용 예문을 구분해 보여줍니다.</p><span>YouTube URL 입력 → 시간정보 있는 자막 확인 → 표현 추출</span></div><div id="pod-deck" hidden><div class="deck-meta"><span id="pod-card-counter"></span><button id="pod-known">저장한 표현 0개</button></div><div class="recall-card"><span class="card-label">뜻을 보고 영어로 말해보세요</span><h3 id="pod-meaning"></h3><button id="pod-reveal">영어 표현 확인</button><div id="pod-answer" hidden><h4 id="pod-expression"></h4><div class="say-row"><button id="pod-speak">원본 음성 듣기</button><button id="pod-repeat">3번 반복</button></div><a id="pod-youtube" target="_blank" rel="noopener" hidden>YouTube에서 해당 구간 보기 ↗</a><label>원문에서</label><blockquote id="pod-quote"></blockquote><label>새로 만든 연습 예문</label><p id="pod-example"></p><p id="pod-tip"></p></div></div><div class="grade-actions"><button id="pod-again">그냥 넘기기</button><button id="pod-good" class="accent">표현 저장하기</button></div><div class="keyboard-hint">Space 답 확인 · ← → 카드 이동</div><div class="deck-nav"><button id="pod-prev">← 이전</button><button id="pod-reset">처음부터 보기</button><button id="pod-next">다음 →</button></div></div></section></div>`;document.body.append(podcastDialog);
const pe=s=>podcastDialog.querySelector(s);let sessions=[],activeSession=null,cardIndex=0,currentSource='',captionType='직접 입력한 전사',busy=false;
async function api(path,data){const r=await fetch('/api/'+path,{method:data?'POST':'GET',headers:{'X-English-Token':window.ENGLISH_TOKEN,'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined});const body=await r.json();if(!r.ok)throw Error(body.error||'요청에 실패했습니다.');return body}
function status(s,error=false){pe('#pod-status').textContent=s;pe('#pod-status').classList.toggle('error',error)}
function setBusy(value){busy=value;['#pod-query','#pod-search','#pod-title','#pod-transcript','#pod-extract','#pod-count'].forEach(s=>pe(s).disabled=value);pe('#pod-results').querySelectorAll('button').forEach(b=>b.disabled=value)}
async function job(kind,data){if(busy)throw Error('진행 중인 작업이 있습니다.');setBusy(true);try{const {job}=await api(kind,data);for(;;){await new Promise(r=>setTimeout(r,1000));const v=await api('jobs/'+job);if(v.progress)status(v.progress);if(v.status==='error')throw Error(v.error);if(v.status==='done')return v.result}throw Error('처리 시간이 초과되었습니다. 잠시 후 다시 열어 확인하세요.')}finally{setBusy(false)}}
function updateCharacters(){pe('#pod-char-count').textContent=pe('#pod-transcript').value.length.toLocaleString()+'자'}
async function loadTranscript(url){status('YouTube 영어 자막과 시간정보를 가져오는 중…');try{const d=await job('transcript',{url});pe('#pod-title').value=d.title;pe('#pod-transcript').value=d.transcript;currentSource=d.url;captionType=d.captionType;pe('#pod-source').href=d.url;pe('#pod-source').hidden=false;pe('#pod-caption-type').textContent=d.captionType;updateCharacters();saveDraft();pe('#pod-results').replaceChildren();status('전사와 에피소드를 확인한 뒤 표현을 추출하세요.')}catch(e){status(e.message,true)}}
function canonicalYouTube(value){try{const u=new URL(value);if(u.protocol!=='https:'||!['youtube.com','www.youtube.com','m.youtube.com','youtu.be'].includes(u.hostname))return null;const id=u.hostname==='youtu.be'?u.pathname.slice(1):u.pathname.startsWith('/shorts/')?u.pathname.split('/')[2]:u.searchParams.get('v');return /^[A-Za-z0-9_-]{11}$/.test(id||'')?'https://www.youtube.com/watch?v='+id:null}catch{return null}}
pe('#pod-search').onclick=async()=>{if(busy)return;const url=canonicalYouTube(pe('#pod-query').value.trim());if(!url){status('YouTube 영상의 HTTPS URL을 입력하세요.',true);return}if(currentSource!==url){pe('#pod-title').value='';pe('#pod-transcript').value='';updateCharacters();activeSession=null;pe('#pod-deck').hidden=true;pe('#pod-empty').hidden=false}currentSource=url;pe('#pod-source').href=url;pe('#pod-source').hidden=false;await loadTranscript(url)};

pe('#pod-query').onkeydown=e=>{if(e.key==='Enter')pe('#pod-search').click()};pe('#pod-transcript').oninput=()=>{updateCharacters();captionType='사용자 확인·수정 전사';pe('#pod-caption-type').textContent=captionType;saveDraft()};
function renderCard(){if(!activeSession)return;const cards=activeSession.expressions,c=cards[cardIndex];pe('#pod-empty').hidden=true;pe('#pod-deck').hidden=false;pe('#pod-card-counter').textContent=`${cardIndex+1} / ${cards.length}`;const selectedSaved=savedExpressions[activeSession.id]||[];pe('#pod-known').textContent=`저장한 표현 ${Object.values(savedExpressions).reduce((n,items)=>n+items.length,0)}개`;pe('#pod-meaning').textContent=c.meaning;pe('#pod-expression').textContent=c.expression;pe('#pod-quote').textContent=c.quote;pe('#pod-example').textContent=c.example;pe('#pod-tip').textContent=c.tip;const jump=pe('#pod-youtube');jump.hidden=!c.youtubeUrl;if(c.youtubeUrl){jump.href=c.youtubeUrl;jump.textContent=`YouTube에서 ${Math.floor(c.youtubeStart/60)}:${String(c.youtubeStart%60).padStart(2,'0')} 구간 보기 ↗`}pe('#pod-answer').hidden=true;pe('#pod-reveal').hidden=false;pe('#pod-good').disabled=selectedSaved.includes(cardIndex);pe('#pod-good').textContent=selectedSaved.includes(cardIndex)?'저장됨 ✓':'표현 저장하기';pe('#pod-prev').disabled=cardIndex===0;pe('#pod-next').disabled=cardIndex===cards.length-1;window.OriginalAudio?.stop()}
function setSession(id){activeSession=sessions.find(s=>s.id===id)||null;cardIndex=0;if(!activeSession)return;pe('#pod-title').value=activeSession.title;pe('#pod-transcript').value=activeSession.transcript;currentSource=activeSession.youtubeUrl||activeSession.url;pe('#pod-query').value=activeSession.youtubeUrl||canonicalYouTube(activeSession.url)||'';captionType=activeSession.captionType;pe('#pod-caption-type').textContent=captionType;pe('#pod-source').hidden=!currentSource;if(currentSource)pe('#pod-source').href=currentSource;pe('#pod-history').value=id;updateCharacters();renderCard()}
async function loadSessions(){try{sessions=(await api('sessions')).sessions;const select=pe('#pod-history');select.replaceChildren(new Option('에피소드를 선택하세요',''));for(const s of sessions)select.add(new Option(s.title,s.id));if(activeSession)select.value=activeSession.id}catch(e){status(e.message,true)}}
pe('#pod-count').onchange=saveDraft;
pe('#pod-extract').onclick=async()=>{if(busy)return;const text=pe('#pod-transcript').value.trim();if(text.length<500){status('영어 전사를 500자 이상 입력하세요.',true);return}const count=Number(pe('#pod-count').value);status(`Codex가 전사를 나눠 분석해 표현 ${count}개를 고르는 중…`);try{const d=await job('extract',{title:pe('#pod-title').value,transcript:text,url:currentSource,captionType,count});await loadSessions();setSession(d.id);window.dispatchEvent(new Event('english-podcasts-change'));try{localStorage.removeItem('english-podcast-draft-v1')}catch{}status(`표현 ${d.expressions.length}개를 추출했습니다. 뜻을 보고 영어로 말해보세요.`)}catch(e){status(e.message,true)}};
pe('#pod-history').onchange=e=>{if(e.target.value)setSession(e.target.value)};pe('#pod-reveal').onclick=()=>{pe('#pod-answer').hidden=false;pe('#pod-reveal').hidden=true};pe('#pod-prev').onclick=()=>{cardIndex=Math.max(0,cardIndex-1);renderCard()};pe('#pod-next').onclick=()=>{cardIndex=Math.min(activeSession.expressions.length-1,cardIndex+1);renderCard()};
function nextExpression(){
    if(!activeSession)return;
    if(cardIndex<activeSession.expressions.length-1){cardIndex++;renderCard()}
    else status('마지막 표현까지 확인했습니다. 저장한 표현은 위의 목록에서 다시 볼 수 있어요.');
}
pe('#pod-again').onclick=nextExpression;
pe('#pod-good').onclick=()=>{
    if(!activeSession)return;
    const items=savedExpressions[activeSession.id]||[];
    if(!items.includes(cardIndex))items.push(cardIndex);
    savedExpressions[activeSession.id]=items;
    if(!persistSaved())return;
    status('표현을 저장했습니다.');
    if(cardIndex<activeSession.expressions.length-1)nextExpression();else renderCard();
};
pe('#pod-reset').onclick=()=>{if(!activeSession)return;cardIndex=0;renderCard()};

function speak(times){if(!activeSession)return;window.OriginalAudio.play(activeSession,cardIndex,times,status)}
pe('#pod-speak').onclick=()=>speak(1);pe('#pod-repeat').onclick=()=>speak(3);document.querySelector('#podcast-open').onclick=async()=>{podcastDialog.showModal();await loadSessions();const hasDraft=await restoreDraft();if(!hasDraft&&!activeSession&&sessions.length)setSession(sessions[0].id);try{const health=await api('health');if(!health.codex)status('Codex CLI를 찾지 못했습니다.',true)}catch(e){status(e.message,true)}};pe('#study-close').onclick=()=>podcastDialog.close();podcastDialog.addEventListener('close',()=>window.OriginalAudio?.stop());

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
    if(!isSpace&&event.key!=='ArrowLeft'&&event.key!=='ArrowRight')return;
    event.preventDefault();
    if(event.repeat)return;
    if(isSpace)toggleCardAnswer();
    else if(event.key==='ArrowLeft'&&!pe('#pod-prev').disabled)pe('#pod-prev').click();
    else if(event.key==='ArrowRight'&&!pe('#pod-next').disabled)pe('#pod-next').click();
},true);

let savedExpressions={};
try{const value=JSON.parse(localStorage.getItem('english-podcast-saved-v1')||'{}');if(value&&typeof value==='object'&&!Array.isArray(value)){for(const [id,items] of Object.entries(value)){if(Array.isArray(items))savedExpressions[id]=[...new Set(items.filter(i=>Number.isInteger(i)&&i>=0))]}}}catch{}
function persistSaved(){try{localStorage.setItem('english-podcast-saved-v1',JSON.stringify(savedExpressions));window.dispatchEvent(new Event('english-saved-change'));return true}catch{status('표현을 저장하지 못했습니다. 저장소를 확인하세요.',true);return false}}
function showSavedExpressions(){window.location.href='/library.html'}
pe('#pod-known').onclick=showSavedExpressions;

function saveDraft(){try{localStorage.setItem('english-podcast-draft-v1',JSON.stringify({title:pe('#pod-title').value,transcript:pe('#pod-transcript').value,url:currentSource,captionType,count:Number(pe('#pod-count').value)}))}catch{}}
async function restoreDraft(){
 try{
  let draft=JSON.parse(localStorage.getItem('english-podcast-draft-v1')||'null');
  if(!draft&&!localStorage.getItem('english-podcast-recovered-v1')){draft=await api('draft');localStorage.setItem('english-podcast-recovered-v1','1')}
  if(!draft?.transcript)return false;
  pe('#pod-title').value=draft.title||'';pe('#pod-transcript').value=draft.transcript;currentSource=draft.url||'';captionType=draft.captionType||'확인한 전사';pe('#pod-query').value=currentSource;pe('#pod-caption-type').textContent=captionType;pe('#pod-count').value=[10,20,30].includes(draft.count)?draft.count:10;pe('#pod-source').hidden=!currentSource;if(currentSource)pe('#pod-source').href=currentSource;activeSession=null;pe('#pod-deck').hidden=true;pe('#pod-empty').hidden=false;updateCharacters();saveDraft();return true;
 }catch{return false}
}

window.addEventListener('english-saved-change',()=>{try{savedExpressions=JSON.parse(localStorage.getItem('english-podcast-saved-v1')||'{}');if(activeSession&&podcastDialog.open)renderCard()}catch{}});
