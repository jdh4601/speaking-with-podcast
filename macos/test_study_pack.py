import base64
import json
import pathlib
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
import uuid
from unittest.mock import patch

import server
from study_pack import export_pack


class StudyPackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.sid = str(uuid.uuid4())
        self.session = {'id': self.sid, 'title': 'Test episode', 'createdAt': time.time(),
                        'url': 'https://youtu.be/abcdefghijk',
                        'transcript': '[00:00:01] I see your point.\n[00:00:04] Another sentence.',
                        'expressions': [{'expression': 'your point', 'meaning': '네 의견',
                                         'quote': 'I see your point.', 'example': 'A new practice example.',
                                         'sourceSentence': 'I see your point.'}]}
        self.save()

    def save(self):
        (self.root / (self.sid + '.json')).write_text(json.dumps(self.session))

    def export(self, **kwargs):
        return export_pack({'sessionId': self.sid, **kwargs}, self.root, self.audio, server.attach_source_sentences)

    def audio(self, data):
        folder = self.root / 'audio' / self.sid
        folder.mkdir(parents=True, exist_ok=True)
        name = '0-' + 'a' * 16 + '.mp3'
        (folder / name).write_bytes(b'ID3 test original audio')
        return {'clipUrl': f'/api/audio/{self.sid}/{name}', 'kind': 'original-podcast-sentence',
                'sentence': 'I see your point.', 'expression': 'your point',
                'sourceUrl': self.session['url'], 'duration': 2.5, 'start': 1.2, 'end': 3.7}

    def read(self, result):
        return json.loads((self.root / 'exports' / (result['exportId'] + '.podstudy')).read_bytes())

    def test_original_audio_roundtrip_and_no_secrets_or_transcript(self):
        result = self.export()
        pack = self.read(result)
        self.assertEqual(pack['version'], 1)
        card = pack['episode']['cards'][0]
        self.assertEqual(base64.b64decode(card['audio']['base64']), b'ID3 test original audio')
        self.assertEqual(card['sourceSentence'], 'I see your point.')
        self.assertEqual(result['audioCount'], 1)
        self.assertNotIn('transcript', pack['episode'])
        self.assertNotIn(server.TOKEN, json.dumps(pack))

    def test_partial_audio_failure_keeps_cards_and_reason(self):
        with patch.object(self, 'audio', side_effect=ValueError('원문을 확인하지 못했습니다.')):
            result = self.export()
        card = self.read(result)['episode']['cards'][0]
        self.assertIsNone(card['audio'])
        self.assertIn('원문', card['audioUnavailableReason'])
        self.assertEqual(len(result['warnings']), 1)

    def test_text_only_never_calls_audio(self):
        with patch.object(self, 'audio', side_effect=AssertionError('must not prepare audio')):
            self.assertEqual(self.export(includeAudio=False)['audioCount'], 0)

    def test_reorder_keeps_card_identity(self):
        before = self.read(self.export(includeAudio=False))['episode']['cards'][0]['id']
        self.session['expressions'].insert(0, {'expression': 'Another sentence', 'meaning': '다른 문장', 'quote': 'Another sentence.'})
        self.save()
        after = self.read(self.export(includeAudio=False))['episode']['cards'][1]['id']
        self.assertEqual(before, after)

    def test_rejects_duplicate_cards_and_invalid_inputs(self):
        for data in ({'sessionId': '../../secret'}, {'sessionId': self.sid, 'includeAudio': 'yes'}):
            with self.assertRaises(ValueError): export_pack(data, self.root, self.audio, server.attach_source_sentences)
        self.session['expressions'] *= 2
        self.save()
        with self.assertRaises(ValueError): self.export(includeAudio=False)

    def test_rejects_mismatched_sentence_audio(self):
        original = self.audio
        def bad(data):
            clip = original(data)
            clip['sentence'] = 'A different sentence.'
            return clip
        with patch.object(self, 'audio', side_effect=bad): result = self.export()
        self.assertEqual(result['audioCount'], 0)
        self.assertIn('일치하지', result['warnings'][0])

    def test_size_failure_leaves_no_export(self):
        with patch('study_pack.MAX_BYTES', 10):
            with self.assertRaises(ValueError): self.export(includeAudio=False)
        self.assertFalse((self.root / 'exports').exists())

    def test_export_http_job_and_authenticated_download(self):
        http = server.create_server(0)
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(http.server_close)
        self.addCleanup(http.shutdown)
        origin = f'http://127.0.0.1:{http.server_port}'
        with patch.object(server, 'DATA', self.root):
            body = json.dumps({'sessionId': self.sid, 'includeAudio': False}).encode()
            req = urllib.request.Request(origin + '/api/export', data=body, headers={'X-English-Token': server.TOKEN})
            with urllib.request.urlopen(req) as response: job = json.load(response)['job']
            for _ in range(200):
                if server.JOBS[job]['status'] != 'running': break
                time.sleep(.01)
            self.assertEqual(server.JOBS[job]['status'], 'done')
            path = server.JOBS[job]['result']['downloadUrl']
            with self.assertRaises(urllib.error.HTTPError) as denied: urllib.request.urlopen(origin + path)
            self.assertEqual(denied.exception.code, 403)
            denied.exception.close()
            req = urllib.request.Request(origin + path, headers={'X-English-Token': server.TOKEN})
            with urllib.request.urlopen(req) as response:
                self.assertEqual(json.load(response)['episode']['id'], self.sid)

    def test_session_identity_source_and_quote_are_verified_before_audio(self):
        cases = [
            ('id', str(uuid.uuid4())), ('id', 123),
            ('createdAt', float('nan')), ('createdAt', True), ('createdAt', '1000'),
            ('url', 'file:///private/recording.mp3'), ('url', 'https://user:password@example.com/podcast'),
            ('url', 'https://example.com:bad/podcast'),
        ]
        for key, value in cases:
            with self.subTest(key=key, value=value):
                original = self.session[key]
                self.session[key] = value
                self.save()
                with patch.object(self, 'audio', side_effect=AssertionError('audio must not run')):
                    with self.assertRaises(ValueError): self.export()
                self.session[key] = original
        self.session['expressions'][0]['quote'] = 'This quote never occurred.'
        self.save()
        with self.assertRaisesRegex(ValueError, '원문 전사'): self.export()

    def test_invalid_audio_metadata_stays_partial_with_explicit_reasons(self):
        original = self.audio
        cases = [
            {'start': -1}, {'start': float('nan')}, {'start': True}, {'duration': True},
            {'duration': float('inf')}, {'duration': 0}, {'duration': 152},
            {'end': None}, {'end': 1}, {'end': 9}, {'expression': 'another expression'},
            {'sourceUrl': 'https://example.com/another-episode'},
            {'clipUrl': f'/api/audio/{self.sid}/1-' + 'a' * 16 + '.mp3'},
            {'clipUrl': f'/api/audio/{self.sid}/../../source.mp3'},
        ]
        for changes in cases:
            with self.subTest(changes=changes):
                def invalid(data):
                    clip = original(data)
                    clip.update(changes)
                    return clip
                with patch.object(self, 'audio', side_effect=invalid), patch('study_pack.base64.b64encode') as encode:
                    result = self.export()
                    encode.assert_not_called()
                card = self.read(result)['episode']['cards'][0]
                self.assertIsNone(card['audio'])
                self.assertTrue(card['audioUnavailableReason'])
                self.assertEqual(result['audioCount'], 0)
                self.assertEqual(len(result['warnings']), 1)

    def test_audio_file_symlink_is_not_embedded(self):
        original = self.audio
        secret = self.root / 'private.bin'
        secret.write_bytes(b'secret recording')
        def linked(data):
            clip = original(data)
            path = self.root / 'audio' / self.sid / clip['clipUrl'].rsplit('/', 1)[1]
            path.unlink()
            path.symlink_to(secret)
            return clip
        with patch.object(self, 'audio', side_effect=linked): result = self.export()
        self.assertEqual(result['audioCount'], 0)
        self.assertNotIn(base64.b64encode(secret.read_bytes()).decode(), json.dumps(self.read(result)))

    def test_audio_size_budget_rejected_before_base64_encoding(self):
        baseline = self.read(self.export(includeAudio=False))
        baseline['episode']['cards'][0]['audioUnavailableReason'] = None
        baseline['exportedAt'] = 1000
        size = len(json.dumps(baseline, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode())
        existing = set((self.root / 'exports').iterdir())
        with patch('study_pack.time.time', return_value=1000), patch('study_pack.MAX_BYTES', size + 1), patch('study_pack.base64.b64encode') as encode:
            with self.assertRaisesRegex(ValueError, '64MB'): self.export()
            encode.assert_not_called()
        self.assertEqual(set((self.root / 'exports').iterdir()), existing)

    def test_invalid_string_fields_rejected_as_validation_errors(self):
        self.session['expressions'] = [{'expression': 42, 'quote': 'I see your point.', 'meaning': '뜻'}]
        self.save()
        with self.assertRaises(ValueError): self.export()

    def test_export_http_partial_audio_and_oversize_download(self):
        http = server.create_server(0)
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(http.server_close)
        self.addCleanup(http.shutdown)
        origin = f'http://127.0.0.1:{http.server_port}'
        with patch.object(server, 'DATA', self.root), patch.object(server, 'prepare_audio', side_effect=ValueError('원음 미제공')):
            body = json.dumps({'sessionId': self.sid, 'includeAudio': True}).encode()
            req = urllib.request.Request(origin + '/api/export', data=body, headers={'X-English-Token': server.TOKEN})
            with urllib.request.urlopen(req) as response: job = json.load(response)['job']
            for _ in range(200):
                if server.JOBS[job]['status'] != 'running': break
                time.sleep(.01)
            self.assertEqual(server.JOBS[job]['status'], 'done')
            result = server.JOBS[job]['result']
            req = urllib.request.Request(origin + result['downloadUrl'], headers={'X-English-Token': server.TOKEN})
            with urllib.request.urlopen(req) as response:
                pack = json.load(response)
                self.assertEqual(response.headers['Content-Type'], 'application/vnd.podcast-study+json')
                self.assertEqual(pack['episode']['cards'][0]['audioUnavailableReason'], '원음 미제공')
            path = self.root / 'exports' / (result['exportId'] + '.podstudy')
            with path.open('wb') as out: out.truncate(64 * 1024 * 1024 + 1)
            with self.assertRaises(urllib.error.HTTPError) as oversized: urllib.request.urlopen(req)
            self.assertEqual(oversized.exception.code, 413)
            oversized.exception.close()
