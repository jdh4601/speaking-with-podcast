"""Find the original recording, align actual spoken words, and cache short MP3 clips."""
import hashlib,html,json,pathlib,re,socket,ipaddress,urllib.request,urllib.parse,uuid
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
        run([ytdlp,'--ignore-config','--no-playlist','-f','bestaudio','--extract-audio','--audio-format','mp3','--audio-quality','4','--ffmpeg-location',FFMPEG,'-o',str(folder/'source.%(ext)s'),'--',info['youtube']],timeout=600)
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
    start,end,fraction=locate_turn(card,session.get('transcript',''))
    folder=data_dir/'audio'/sid;folder.mkdir(parents=True,exist_ok=True)
    digest=hashlib.sha256((card['expression']+'\n'+card['quote']).encode()).hexdigest()[:16];name=f'{index}-{digest}'
    clip=folder/(name+'.mp3');meta=folder/(name+'.json')
    if clip.exists() and meta.exists():return json.loads(meta.read_text())
    if not pathlib.Path(AUDIO_PYTHON).exists():raise ValueError('원본 음성 구간 분석 도구가 없습니다. 앱 설치 상태를 확인하세요.')
    source,info=download_source(session,folder,run,ytdlp)
    expected=start+(end-start)*fraction
    bounds=None
    for padding in (7,75):
        window_start=max(0,start-padding);window_end=end+padding;window=folder/f'window-{int(window_start)}-{int(window_end)}.wav';wordsfile=window.with_suffix('.words.json')
        if not wordsfile.exists():
            run([FFMPEG,'-hide_banner','-loglevel','error','-y','-ss',str(window_start),'-i',str(source),'-t',str(window_end-window_start),'-vn','-ac','1','-ar','16000',str(window)],timeout=120)
            run([AUDIO_PYTHON,str(pathlib.Path(__file__).with_name('align_words.py')),str(window),str(wordsfile)],timeout=300)
        words=json.loads(wordsfile.read_text())['words'];wanted=tokens(card['expression']);flat=[]
        for w in words:
            for token in tokens(w['word']):flat.append((token,w['start'],w['end']))
        candidates=[]
        for n in range(len(flat)-len(wanted)+1):
            if [w[0] for w in flat[n:n+len(wanted)]]==wanted:
                a=flat[n][1]+window_start;b=flat[n+len(wanted)-1][2]+window_start
                if .08<b-a<20:candidates.append((a,b))
        if candidates:
            bounds=min(candidates,key=lambda x:abs(x[0]-expected));break
    if bounds is None:raise ValueError('실제 음성에서 이 표현의 정확한 단어 구간을 확인하지 못했습니다. 다른 표현을 선택해 주세요.')
    a=max(0,bounds[0]-.10);b=bounds[1]+.16
    run([FFMPEG,'-hide_banner','-loglevel','error','-y','-ss',f'{a:.3f}','-i',str(source),'-t',f'{b-a:.3f}','-vn','-acodec','libmp3lame','-q:a','2',str(clip)],timeout=120)
    result={'clipUrl':f'/api/audio/{sid}/{name}.mp3','start':round(a,3),'end':round(b,3),'duration':round(b-a,3),'expression':card['expression'],'sourceUrl':info['sourceUrl'],'kind':'original-podcast'}
    meta.write_text(json.dumps(result,ensure_ascii=False));return result
