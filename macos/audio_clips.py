"""Find the original recording, align actual spoken words, and cache short MP3 clips."""
import difflib,hashlib,html,json,math,pathlib,re,socket,ipaddress,urllib.request,urllib.parse,uuid
from youtube_tools import command as youtube_command
FFMPEG='/opt/homebrew/bin/ffmpeg'
AUDIO_PYTHON=str(pathlib.Path.home()/'Library/Application Support/English Routine/audio-runtime/bin/python')

def public_url(url):
    p=urllib.parse.urlparse(url)
    if p.scheme!='https' or not p.hostname or p.username or p.password or p.port not in (None,443):raise ValueError('공개 HTTPS 오디오 주소가 필요합니다.')
    for info in socket.getaddrinfo(p.hostname,443,type=socket.SOCK_STREAM):
        if not ipaddress.ip_address(info[4][0]).is_global:raise ValueError('비공개 네트워크 주소는 사용할 수 없습니다.')
    return url

class PublicRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,req,fp,code,msg,headers,newurl):
        public_url(newurl);return super().redirect_request(req,fp,code,msg,headers,newurl)

def open_public(url):
    public_url(url)
    return urllib.request.build_opener(PublicRedirect()).open(urllib.request.Request(url,headers={'User-Agent':'EnglishRoutine/1.0'}),timeout=60)

def tokens(text):
    return re.findall(r"[a-z0-9]+(?:'[a-z]+)?",text.casefold().replace('’',"'"))

def timestamped_turns(transcript):
    matches=list(re.finditer(r'\[(\d{1,2}):(\d{2})(?::(\d{2}))?\]\s*:?\s*',transcript));turns=[]
    for i,m in enumerate(matches):
        a,b,c=m.groups();start=int(a)*3600+int(b)*60+int(c) if c is not None else int(a)*60+int(b)
        end=matches[i+1].start() if i+1<len(matches) else len(transcript)
        content=transcript[m.end():end]
        turns.append({'start':start,'end':None,'text':content})
    for i in range(len(turns)-1):turns[i]['end']=turns[i+1]['start']
    return turns

def locate_turn(card,transcript):
    needle=tokens(card['expression']);quote=tokens(card.get('quote',''));turns=timestamped_turns(transcript)
    flat=[];lengths=[]
    for t,turn in enumerate(turns):
        words=tokens(turn['text']);lengths.append(len(words))
        flat.extend((word,t,i) for i,word in enumerate(words))
    candidates=[]
    for i in range(max(0,len(flat)-len(needle)+1)):
        if [item[0] for item in flat[i:i+len(needle)]]!=needle:continue
        first=flat[i];last=flat[i+len(needle)-1];turn=turns[first[1]]
        nearby=' '.join(item[0] for item in flat[max(0,i-len(quote)):i+len(needle)+len(quote)])
        score=1 if quote and ' '.join(quote) in nearby else 0
        start=turn['start'];end=turns[last[1]]['end'] or turns[last[1]]['start']+45
        fraction=first[2]/max(1,lengths[first[1]])
        candidates.append((score,start,min(end,start+150),fraction))
    if not candidates:raise ValueError('이 표현의 시간표시를 전사에서 찾지 못했습니다. 시간표시가 있는 원본 전사가 필요합니다.')
    _,start,end,fraction=max(candidates,key=lambda c:c[0]);return start,end,fraction

def sentence_context(card,transcript):
    # Speaker labels belong to the following timestamp, not the previous sentence.
    transcript=re.sub(r'(?m)^[^\n\[]+(?=\[\d{1,2}:\d{2}(?::\d{2})?\])','',transcript)
    turns=timestamped_turns(transcript)
    text='';flat=[]
    for turn in turns:
        content=re.sub(r'\[[^\]]*\]',' ',turn['text']).replace('’',"'").strip()
        offset=len(text);text+=content+' '
        for match in re.finditer(r"[a-z0-9]+(?:'[a-z]+)?",content,re.I):
            flat.append((match[0].lower(),offset+match.start(),offset+match.end(),turn))
    needle=tokens(card['expression']);quote=tokens(card.get('quote',''))
    words=[item[0] for item in flat];candidates=[]
    for i in range(len(words)-len(needle)+1):
        if words[i:i+len(needle)]!=needle:continue
        nearby=words[max(0,i-len(quote)):i+len(needle)+len(quote)]
        score=any(nearby[j:j+len(quote)]==quote for j in range(len(nearby)-len(quote)+1)) if quote else False
        candidates.append((score,i))
    if not candidates:raise ValueError('전사에서 표현이 포함된 원문 문장을 찾지 못했습니다.')
    _,position=max(candidates,key=lambda item:item[0])
    def boundary(i):
        if i==0:return True
        punctuation=text[flat[i-1][2]:flat[i][1]] if i<len(flat) else text[flat[-1][2]:]
        if not re.search(r'[.!?]',punctuation):return False
        if punctuation.strip()=='.' and flat[i-1][0] in {'mr','mrs','ms','dr','prof','jr','sr','vs'}:return False
        # A decimal point or initials inside a word are not sentence endings.
        if i<len(flat) and not re.search(r'\s',punctuation):return False
        return True
    left=position;right=position+len(needle)
    while left>0 and not boundary(left):left-=1
    while right<len(flat) and not boundary(right):right+=1
    if not boundary(right):raise ValueError('전사에서 원문 문장의 끝을 확인하지 못했습니다. 문장부호가 포함된 전사가 필요합니다.')
    first,last=flat[left],flat[right-1]
    end_text=flat[right][1] if right<len(flat) else len(text)
    sentence=text[first[1]:end_text].strip()
    turn=first[3];start=turn['start'];end=last[3]['end'] or last[3]['start']+45
    if end-start>150:raise ValueError('원문 문장이 너무 길어 음성 구간을 확인하지 못했습니다.')
    return {'text':sentence,'tokens':words[left:right],'start':start,'end':end,
            'expressionStart':flat[position][3]['start']}

def align_sentence(words,context,expression,window_start):
    flat=[]
    for word in words:
        for token in tokens(word['word']):flat.append((token,word['start'],word['end']))
    observed=[item[0] for item in flat];wanted=context['tokens'];phrase=tokens(expression)
    anchor=min(3,len(wanted))
    starts=[i for i in range(len(flat)-anchor+1) if observed[i:i+anchor]==wanted[:anchor]]
    ends=[i+anchor for i in range(len(flat)-anchor+1) if observed[i:i+anchor]==wanted[-anchor:]]
    phrases=[i for i in range(len(flat)-len(phrase)+1) if observed[i:i+len(phrase)]==phrase]
    candidates=[]
    for first in starts:
        for last in ends:
            if last<=first:continue
            matches=[i for i in phrases if first<=i and i+len(phrase)<=last]
            if not matches:continue
            a=flat[first][1]+window_start;b=flat[last-1][2]+window_start
            if not .08<b-a<150:continue
            similarity=difflib.SequenceMatcher(None,wanted,observed[first:last],autojunk=False).ratio()
            if similarity<.8:continue
            distance=min(abs(flat[i][1]+window_start-context['expressionStart']) for i in matches)
            candidates.append((distance,-similarity,a,b))
    if not candidates:return None
    _,_,a,b=min(candidates)
    return a,b

def validate_word_timings(value,duration):
    """Validate optional clip-relative measurements; never estimate missing times."""
    if value is None:return None
    if not isinstance(value,list) or not 1<=len(value)<=2000:raise ValueError('단어별 음성 시간 정보가 올바르지 않습니다.')
    result=[];previous_start=previous_end=-1
    for item in value:
        if not isinstance(item,dict):raise ValueError('단어별 음성 시간 정보가 올바르지 않습니다.')
        word=item.get('word');start=item.get('start');end=item.get('end')
        if (not isinstance(word,str) or not 1<=len(word.strip())<=200 or not tokens(word)
            or type(start) not in (int,float) or type(end) not in (int,float)
            or not math.isfinite(start) or not math.isfinite(end) or not 0<=start<end<=duration
            or start<previous_start or end<previous_end):
            raise ValueError('단어별 음성 시간 정보가 올바르지 않습니다.')
        result.append({'word':word.strip(),'start':start,'end':end})
        previous_start,previous_end=start,end
    return result

def relative_word_timings(words,window_start,clip_start,duration):
    """Select measured words wholly inside this clip and convert to local time."""
    selected=[];clip_end=clip_start+duration
    try:
        for item in words:
            start=window_start+item['start'];end=window_start+item['end']
            if not math.isfinite(start) or not math.isfinite(end):return None
            if end<=clip_start or start>=clip_end or end<=start:continue
            # Do not label partial neighbouring words in the clip padding as complete.
            # The caller matches the displayed excerpt against the remaining whole words.
            if start<clip_start-.03 or end>clip_end+.03:continue
            if not tokens(item['word']):continue
            selected.append({'word':item['word'].strip(),'start':round(max(0,start-clip_start),3),
                             'end':round(min(duration,end-clip_start),3)})
        return validate_word_timings(selected,duration)
    except (ValueError,TypeError,KeyError,AttributeError):return None

def cached_word_timings(folder,metadata):
    """Upgrade old clip metadata from existing ASR caches, without any I/O service."""
    try:
        start=metadata['start'];end=metadata['end'];duration=metadata['duration']
        sentence=metadata['sentence'];expression=metadata['expression']
        if (type(start) not in (int,float) or type(end) not in (int,float)
            or type(duration) not in (int,float) or not all(map(math.isfinite,(start,end,duration)))
            or not 0<=start<end or abs(end-start-duration)>.02):return None
        context={'tokens':tokens(sentence),'expressionStart':start}
        if not context['tokens'] or not tokens(expression):return None
        for path in sorted(folder.glob('window-*.words.json')):
            match=re.fullmatch(r'window-(\d+)-(\d+)\.words\.json',path.name)
            if not match:continue
            window_start,window_end=map(int,match.groups())
            if window_start>start or window_end<end:continue
            try:
                words=json.loads(path.read_text())['words']
                bounds=align_sentence(words,context,expression,window_start)
                if bounds is None or abs(max(0,bounds[0]-.10)-start)>.02 or abs(bounds[1]+.16-end)>.02:continue
                result=relative_word_timings(words,window_start,start,duration)
                if result:return result
            except (ValueError,TypeError,KeyError,AttributeError,OSError):continue
    except (ValueError,TypeError,KeyError,AttributeError):pass
    return None

def discover_audio(session,run,ytdlp):
    url=session.get('url','');host=urllib.parse.urlparse(url).hostname or ''
    if host in ('youtube.com','www.youtube.com','youtu.be','m.youtube.com'):
        return {'youtube':url,'sourceUrl':url}
    if host not in ('latent.space','www.latent.space','dwarkesh.com','www.dwarkesh.com'):raise ValueError('원본 오디오를 연결할 수 없는 기록입니다. 원본 에피소드 링크로 전사를 다시 가져와 주세요.')
    with open_public(url) as r:raw=r.read(6000000).decode('utf-8','replace')
    raw=html.unescape(raw).replace('\\/','/')
    urls=re.findall(r'https://[^\s"<>\\]+?\.mp3(?:\?[^\s"<>\\]*)?',raw)
    if not urls:raise ValueError('발행사 페이지에서 공개 MP3를 찾지 못했습니다. 원본 MP3가 공개된 에피소드가 필요합니다.')
    audio=urls[0];public_url(audio)
    return {'audioUrl':audio,'sourceUrl':url}

def download_source(session,folder,run,ytdlp):
    source=folder/'source.mp3';infofile=folder/'source.json'
    if source.exists() and source.stat().st_size>1000:return source,json.loads(infofile.read_text()) if infofile.exists() else {'sourceUrl':session.get('url','')}
    info=discover_audio(session,run,ytdlp)
    if info.get('youtube'):
        args=youtube_command(ytdlp)+['-f','bestaudio','--extract-audio','--audio-format','mp3','--audio-quality','4','--ffmpeg-location',FFMPEG,'-o',str(folder/'source.%(ext)s'),'--',info['youtube']]
        try:
            run(args,timeout=600)
        except ValueError as error:
            if '403' not in str(error):raise
            # Re-extract fresh media URLs and discard a failed partial download.
            try:run(args[:-2]+['--force-overwrites','--no-continue']+args[-2:],timeout=600)
            except ValueError as retry_error:
                if '403' not in str(retry_error):raise
                raise ValueError('YouTube가 원본 음성 다운로드를 거부했습니다(403). 잠시 후 다시 시도해 주세요. 계속되면 앱의 다운로드 도구 업데이트가 필요합니다.') from retry_error
        if not source.is_file() or source.stat().st_size<=1000:
            raise ValueError('원본 MP3 다운로드가 완료되지 않았습니다. 다시 시도해 주세요.')
    else:
        partial=folder/'source.download'
        try:
            with open_public(info['audioUrl']) as response,partial.open('wb') as out:
                total=0
                while True:
                    chunk=response.read(1024*1024)
                    if not chunk:break
                    total+=len(chunk)
                    if total>450*1024*1024:raise ValueError('원본 음성이 450MB를 넘어 처리하지 않았습니다.')
                    out.write(chunk)
            if partial.stat().st_size<1000:raise ValueError('오디오 파일을 가져오지 못했습니다.')
            partial.replace(source)
        finally:
            if partial.exists():partial.unlink()
    infofile.write_text(json.dumps(info));return source,info

def prepare(data,data_dir,run,ytdlp):
    try:sid=str(uuid.UUID(data.get('sessionId','')))
    except (ValueError,AttributeError):raise ValueError('학습 기록 ID가 올바르지 않습니다.')
    index=data.get('index')
    if type(index)!=int or index<0:raise ValueError('표현 번호가 올바르지 않습니다.')
    path=data_dir/(sid+'.json')
    if not path.exists():raise ValueError('학습 기록을 찾지 못했습니다.')
    session=json.loads(path.read_text())
    if index>=len(session['expressions']):raise ValueError('표현 번호가 올바르지 않습니다.')
    card=session['expressions'][index]
    context=sentence_context(card,session.get('transcript',''))
    start,end=context['start'],context['end']
    folder=data_dir/'audio'/sid;folder.mkdir(parents=True,exist_ok=True)
    digest=hashlib.sha256(('sentence-v1\n'+card['expression']+'\n'+card['quote']+'\n'+context['text']).encode()).hexdigest()[:16];name=f'{index}-{digest}'
    clip=folder/(name+'.mp3');meta=folder/(name+'.json')
    if clip.exists() and meta.exists():
        result=json.loads(meta.read_text())
        try:measured=validate_word_timings(result.get('words'),result.get('duration',0))
        except (ValueError,TypeError):measured=None
        if measured is None:
            measured=cached_word_timings(folder,result)
            if measured:
                result['words']=measured
                meta.write_text(json.dumps(result,ensure_ascii=False))
        return result
    if not pathlib.Path(AUDIO_PYTHON).exists():raise ValueError('원본 음성 구간 분석 도구가 없습니다. 앱 설치 상태를 확인하세요.')
    source,info=download_source(session,folder,run,ytdlp)
    bounds=None
    for padding in (7,75):
        window_start=max(0,start-padding);window_end=end+padding;window=folder/f'window-{int(window_start)}-{int(window_end)}.wav';wordsfile=window.with_suffix('.words.json')
        if not wordsfile.exists():
            run([FFMPEG,'-hide_banner','-loglevel','error','-y','-ss',str(window_start),'-i',str(source),'-t',str(window_end-window_start),'-vn','-ac','1','-ar','16000',str(window)],timeout=120)
            run([AUDIO_PYTHON,str(pathlib.Path(__file__).with_name('align_words.py')),str(window),str(wordsfile)],timeout=300)
        words=json.loads(wordsfile.read_text())['words']
        bounds=align_sentence(words,context,card['expression'],window_start)
        if bounds is not None:break
    if bounds is None:raise ValueError('실제 음성에서 이 표현이 포함된 문장 전체의 시작과 끝을 확인하지 못했습니다. 다른 표현을 선택해 주세요.')
    a=max(0,bounds[0]-.10);b=bounds[1]+.16
    run([FFMPEG,'-hide_banner','-loglevel','error','-y','-ss',f'{a:.3f}','-i',str(source),'-t',f'{b-a:.3f}','-vn','-acodec','libmp3lame','-q:a','2',str(clip)],timeout=120)
    result={'clipUrl':f'/api/audio/{sid}/{name}.mp3','start':round(a,3),'end':round(b,3),'duration':round(b-a,3),'expression':card['expression'],'sentence':context['text'],'sourceUrl':info['sourceUrl'],'kind':'original-podcast-sentence'}
    measured=relative_word_timings(words,window_start,a,result['duration'])
    if measured:result['words']=measured
    meta.write_text(json.dumps(result,ensure_ascii=False));return result
