#!/usr/bin/env python3
"""Run portable core checks, including a Python → Swift study-pack round trip."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT.parent / 'macos'))
from study_pack import export_pack
from toolchain import mac_swift_flags

with tempfile.TemporaryDirectory(prefix='podcast-study-check-') as temp:
    work = Path(temp)
    flags = mac_swift_flags(work)
    fixture = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if fixture is None:
        sid = 'f95fbe21-3f7d-4bb8-88d4-6db2834229f5'
        session = {'id': sid, 'title': 'Portable test episode', 'createdAt': 1000,
                   'url': 'https://example.com/podcast', 'transcript': '[00:00:01] I see your point.\n[00:00:04] Another sentence.', 'expressions': [
                       {'expression': 'your point', 'meaning': '네 의견', 'quote': 'I see your point.',
                        'sourceSentence': 'I see your point.', 'sourceSentenceTranslation': '네 의견을 이해해요.'}]}
        (work / (sid + '.json')).write_text(json.dumps(session))
        def audio(data):
            folder = work / 'audio' / sid
            folder.mkdir(parents=True)
            name = '0-' + 'a' * 16 + '.mp3'
            (folder / name).write_bytes(b'ID3fixture')
            return {'kind': 'original-podcast-sentence', 'clipUrl': f'/api/audio/{sid}/{name}', 'sentence': 'I see your point.', 'duration': 2, 'start': 1, 'end': 3, 'expression': 'your point', 'sourceUrl': session['url']}
        result = export_pack({'sessionId': sid}, work, audio, lambda value: value)
        fixture = work / 'exports' / (result['exportId'] + '.podstudy')
    binary = work / 'checks'
    core = sorted((ROOT / 'PodcastStudy/Core').glob('*.swift'))
    subprocess.run(['swiftc', *flags, *map(str, core), str(ROOT / 'Checks/CoreChecks.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary), str(fixture)], check=True)
    subprocess.run(['swiftc', '-frontend', '-parse', *flags, *map(str, (ROOT / 'PodcastStudy/App').glob('*.swift'))], check=True)
    print('PASS Swift source syntax (iOS build still requires full Xcode)')
