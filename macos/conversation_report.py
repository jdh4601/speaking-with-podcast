"""Turn a speaker-labelled lesson transcript into a stored conversation report."""
from __future__ import annotations

import hashlib
import re

CONTEXT_LIMIT = 200
SPEAKER_LINE = re.compile(r'^([^:\n]{1,80}):\s*(.*)$')
WORD = re.compile(r"[A-Za-z0-9'’]+(?:-[A-Za-z0-9]+)*")
FILLER = re.compile(r'(?<![\w-])(?:um|uh|hmm|mm)(?![\w-])', re.IGNORECASE)
RESTART = re.compile(r'\b(\w+)[—–-]\s+(?=\1\b)', re.IGNORECASE)
BACKCHANNEL_WORDS = frozenset(
    {'mm', 'mm-hm', 'mhm', 'hmm', 'uh-huh', 'yeah', 'yes', 'okay', 'ok', 'right', 'no'}
)
MISSING_SELF_LABEL = (
    '(You) 표시가 있는 본인 발화를 찾지 못했습니다. '
    '화자 이름이 포함된 스크립트를 붙여 넣으세요.'
)


def count_words(text: str) -> int:
    return len(WORD.findall(text))


def _is_backchannel(text: str) -> bool:
    words = [word.lower() for word in WORD.findall(text)]
    return 0 < len(words) <= 3 and all(word in BACKCHANNEL_WORDS for word in words)


def _speaker_blocks(script: str) -> list[dict]:
    blocks: list[dict] = []
    for raw_line in script.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        match = SPEAKER_LINE.match(line)
        if match:
            blocks.append({'own': '(You)' in match[1], 'text': match[2].strip()})
        elif blocks:
            blocks[-1]['text'] = f"{blocks[-1]['text']} {line}".strip()
    return [block for block in blocks if block['text']]


def parse_script(script: str) -> dict:
    """Merge one speaker's lines into turns, keeping neighbours as short context.

    Raises:
        ValueError: If the transcript has no substantive line marked "(You)".
    """
    turns: list[dict] = []
    open_turn: dict | None = None
    previous_other = ''
    other_words = 0
    backchannel_turns = 0

    for block in _speaker_blocks(script):
        text = block['text']
        if not block['own']:
            other_words += count_words(text)
            # A listener's "Mm-hm" keeps the speaker's sentence going.
            if _is_backchannel(text):
                continue
            previous_other = text[:CONTEXT_LIMIT]
            if open_turn:
                open_turn['after'] = previous_other
            open_turn = None
        elif _is_backchannel(text):
            backchannel_turns += 1
        elif open_turn:
            open_turn['text'] = f"{open_turn['text']} {text}"
        else:
            open_turn = {'text': text, 'before': previous_other, 'after': ''}
            turns.append(open_turn)

    if not turns:
        raise ValueError(MISSING_SELF_LABEL)
    return {
        'turns': turns,
        'ownWords': sum(count_words(turn['text']) for turn in turns),
        'otherWords': other_words,
        'backchannelTurns': backchannel_turns,
    }


def _per_100(count: int, words: int) -> float:
    return round(count / words * 100, 1) if words else 0


def base_metrics(parsed: dict) -> dict:
    own_words = parsed['ownWords']
    total_words = own_words + parsed['otherWords']
    disfluencies = sum(
        len(FILLER.findall(turn['text'])) + len(RESTART.findall(turn['text']))
        for turn in parsed['turns']
    )
    return {
        'ownWords': own_words,
        'talkShare': round(own_words / total_words * 100, 1) if total_words else 0,
        'disfluencyPer100': _per_100(disfluencies, own_words),
        'wordsPerTurn': round(own_words / len(parsed['turns']), 1),
    }


def content_hash(turns: list[dict]) -> str:
    joined = '\n'.join(turn['text'] for turn in turns)
    return hashlib.sha256(joined.encode()).hexdigest()
