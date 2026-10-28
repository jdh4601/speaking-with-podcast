"""Portable, versioned study packs. No server tokens or full recordings leave the Mac."""
import base64
import json
import math
import re
import time
import urllib.parse
import uuid

MAX_BYTES = 64 * 1024 * 1024
MAX_AUDIO_BYTES = 8 * 1024 * 1024


class PackTooLarge(ValueError):
    def __init__(self):
        super().__init__('꾸러미가 64MB를 넘습니다. 음성 없이 내보내거나 표현 수를 줄여주세요.')


def _json(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode('utf-8')


def _number(value, minimum, maximum=None):
    return type(value) in (int, float) and math.isfinite(value) and value >= minimum and (maximum is None or value <= maximum)


def _source_url(value):
    if not isinstance(value, str):
        raise ValueError('원본 에피소드 주소가 올바르지 않습니다.')
    if not value:
        return value
    try:
        url = urllib.parse.urlsplit(value)
        if url.scheme != 'https' or not url.hostname or url.username or url.password:
            raise ValueError()
        url.port  # Invalid ports must not reach the iPhone's URL parser.
    except ValueError:
        raise ValueError('원본 에피소드의 HTTPS 주소를 확인하세요.')
    return value


def _norm(value):
    return ' '.join(re.sub(r'\[\d{1,2}:\d{2}(?::\d{2})?\]', ' ', value).casefold().split())


def export_pack(data, data_dir, prepare_audio, enrich, progress=lambda _: None):
    try:
        sid = str(uuid.UUID(data.get('sessionId', '')))
    except (ValueError, AttributeError, TypeError):
        raise ValueError('학습 기록 ID가 올바르지 않습니다.')
    include_audio = data.get('includeAudio', True)
    if type(include_audio) is not bool:
        raise ValueError('음성 포함 설정이 올바르지 않습니다.')
    path = data_dir / (sid + '.json')
    if not path.is_file():
        raise ValueError('학습 기록을 찾지 못했습니다.')
    session = json.loads(path.read_text())
    if not isinstance(session, dict) or not isinstance(session.get('id'), str) or session['id'].lower() != sid:
        raise ValueError('선택한 에피소드와 저장된 기록 ID가 일치하지 않습니다.')
    created_at = session.get('createdAt')
    if not _number(created_at, 0):
        raise ValueError('에피소드 생성 시간이 올바르지 않습니다.')
    source_url = _source_url(session.get('youtubeUrl') or session.get('url', ''))
    source_urls = {_source_url(session.get(key, '')) for key in ('url', 'youtubeUrl')}
    transcript = session.get('transcript', '')
    if not isinstance(transcript, str):
        raise ValueError('원문 전사를 확인하지 못했습니다.')
    expressions = session.get('expressions', [])
    if not isinstance(expressions, list) or not 1 <= len(expressions) <= 100:
        raise ValueError('표현이 1~100개인 에피소드를 선택하세요.')
    fields = ('expression', 'meaning', 'quote', 'sourceSentence', 'sourceSentenceTranslation', 'example', 'exampleTranslation', 'tip')
    if any(not isinstance(card, dict) or any(not isinstance(card.get(key, ''), str) for key in fields) for card in expressions):
        raise ValueError('표현과 해석의 형식이 올바르지 않습니다.')
    session = enrich(session)
    normalized_transcript = _norm(transcript)
    title = session.get('title') or '제목 없는 에피소드'
    if not isinstance(title, str) or not title.strip():
        raise ValueError('에피소드 제목이 올바르지 않습니다.')
    cards, warnings, seen = [], [], set()
    for original in expressions:
        if not isinstance(original, dict):
            raise ValueError('표현 형식이 올바르지 않습니다.')
        fields = ('expression', 'meaning', 'quote', 'sourceSentence', 'sourceSentenceTranslation', 'example', 'exampleTranslation', 'tip')
        if any(not isinstance(original.get(key, ''), str) for key in fields):
            raise ValueError('표현과 해석은 문자열이어야 합니다.')
        expression, meaning, quote = (original.get(key, '').strip() for key in ('expression', 'meaning', 'quote'))
        if not expression or not meaning or not quote:
            raise ValueError('표현·뜻·원문 인용이 빠진 기록입니다.')
        if _norm(quote) not in normalized_transcript or _norm(expression) not in _norm(quote):
            raise ValueError('원문 전사와 일치하지 않는 표현이나 인용이 있습니다.')
        # Identity follows content, not its position in an exported list.
        cid = str(uuid.uuid5(uuid.UUID(sid), expression + '\n' + quote))
        if cid in seen:
            raise ValueError('같은 표현과 인용이 중복되어 있습니다.')
        seen.add(cid)
        card = {key: original.get(key, '') for key in fields}
        card.update(id=cid, expression=expression, meaning=meaning, quote=quote,
                    audio=None, audioUnavailableReason=None if include_audio else 'Mac에서 음성 없이 내보낸 표현입니다.')
        cards.append(card)
    pack = {'format': 'podcast-study-pack', 'version': 1, 'exportedAt': time.time(),
            'episode': {'id': sid, 'title': title, 'sourceURL': source_url,
                        'createdAt': created_at, 'cards': cards}}
    # Reserve every text field first. Account for base64 expansion BEFORE reading
    # or encoding another clip, rather than building an unbounded in-memory pack.
    byte_count = len(_json(pack))
    if byte_count > MAX_BYTES:
        raise PackTooLarge()
    if include_audio:
        for index, card in enumerate(cards):
            progress(f'원문 음성 준비 중 · {index + 1}/{len(cards)}')
            try:
                clip = prepare_audio({'sessionId': sid, 'index': index})
                if not isinstance(clip, dict):
                    raise ValueError('원문 음성 정보 형식이 올바르지 않습니다.')
                match = re.fullmatch(r'/api/audio/' + re.escape(sid) + '/' + str(index) + r'-[0-9a-f]{16}\.mp3', clip.get('clipUrl', '') if isinstance(clip.get('clipUrl'), str) else '')
                if not match or clip.get('kind') != 'original-podcast-sentence':
                    raise ValueError('현재 표현의 원문 문장 음성이 아닙니다.')
                if not card['sourceSentence'] or clip.get('sentence') != card['sourceSentence'] or clip.get('expression') != card['expression']:
                    raise ValueError('현재 표현·원문과 음성의 문장이 일치하지 않습니다.')
                if clip.get('sourceUrl') not in source_urls or not clip.get('sourceUrl'):
                    raise ValueError('원문 음성의 출처가 현재 에피소드와 일치하지 않습니다.')
                start, end, duration = clip.get('start'), clip.get('end'), clip.get('duration')
                if not _number(start, 0) or not _number(end, 0) or not _number(duration, .001, 151) or end <= start or abs((end - start) - duration) > .02:
                    raise ValueError('원문 음성의 시작·끝·길이 정보가 일치하지 않습니다.')
                audio_path = data_dir / 'audio' / sid / clip['clipUrl'].rsplit('/', 1)[1]
                if audio_path.is_symlink() or not audio_path.is_file():
                    raise ValueError('원문 음성 파일을 확인하지 못했습니다.')
                size = audio_path.stat().st_size
                if not 0 < size <= MAX_AUDIO_BYTES:
                    raise ValueError('음성 크기가 허용 범위를 벗어났습니다.')
                audio = {'base64': '', 'duration': duration, 'start': start, 'kind': 'original-podcast-sentence'}
                encoded_size = 4 * ((size + 2) // 3)
                delta = len(_json(audio)) - len(b'null') + encoded_size
                if byte_count + delta > MAX_BYTES:
                    raise PackTooLarge()
                with audio_path.open('rb') as source:
                    raw = source.read(MAX_AUDIO_BYTES + 1)
                if len(raw) != size:
                    raise ValueError('음성 준비 중 파일 크기가 바뀌었습니다. 다시 시도하세요.')
                audio['base64'] = base64.b64encode(raw).decode('ascii')
                card['audio'] = audio
                byte_count += delta
            except PackTooLarge:
                raise
            except (ValueError, OSError, KeyError, TypeError) as error:
                reason = str(error)[:500]
                card['audioUnavailableReason'] = reason
                byte_count += len(_json(reason)) - len(b'null')
                warnings.append(f'{index + 1}번 표현: {reason}')
                if byte_count > MAX_BYTES:
                    raise PackTooLarge()
    folder = data_dir / 'exports'
    folder.mkdir(parents=True, exist_ok=True)
    export_id = str(uuid.uuid4())
    target = folder / (export_id + '.podstudy')
    temp = target.with_suffix('.tmp')
    written = 0
    try:
        # Stream JSON chunks so final serialization does not make another full
        # string + bytes copy of all inline audio.
        encoder = json.JSONEncoder(ensure_ascii=False, allow_nan=False, separators=(',', ':'))
        with temp.open('wb') as out:
            for chunk in encoder.iterencode(pack):
                raw = chunk.encode('utf-8')
                written += len(raw)
                if written > MAX_BYTES:
                    raise PackTooLarge()
                out.write(raw)
        temp.replace(target)
    finally:
        temp.unlink(missing_ok=True)
    return {'exportId': export_id, 'downloadUrl': '/api/exports/' + export_id + '.podstudy',
            'filename': 'podcast-' + sid[:8] + '.podstudy', 'episodeId': sid, 'episodeTitle': title,
            'cardCount': len(cards), 'audioCount': sum(c['audio'] is not None for c in cards),
            'warnings': warnings, 'bytes': written}
