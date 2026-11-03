import http.client
import json
import pathlib
import tempfile
import threading
import time
import unittest
from unittest import mock

import server
from conversation_report import (
    analyze_conversation,
    base_metrics,
    content_hash,
    delete_conversation,
    frequency_summary,
    load_report,
    parse_script,
)

SAMPLE = """A: Hello there, how are you?
Me (You): I am— I am fine.
A: Mm-hm.
Me (You): I go to school yesterday.
A: Why?
Me (You): Because.
"""


class ParseTests(unittest.TestCase):
    def test_backchannel_does_not_split_own_turn(self):
        parsed = parse_script(SAMPLE)
        self.assertEqual(
            [turn['text'] for turn in parsed['turns']],
            ['I am— I am fine. I go to school yesterday.', 'Because.'],
        )

    def test_adjacent_other_lines_become_context(self):
        turn = parse_script(SAMPLE)['turns'][0]
        self.assertEqual(turn['before'], 'Hello there, how are you?')
        self.assertEqual(turn['after'], 'Why?')

    def test_context_is_limited_to_200_characters(self):
        parsed = parse_script('A: ' + 'x' * 500 + '\nMe (You): Hello there friend.\n')
        self.assertEqual(len(parsed['turns'][0]['before']), 200)

    def test_own_only_backchannel_is_not_a_turn(self):
        parsed = parse_script(
            'A: Right, so.\nMe (You): Mm-hm.\nA: Good.\nMe (You): I agree with you.\n'
        )
        self.assertEqual(len(parsed['turns']), 1)
        self.assertEqual(parsed['backchannelTurns'], 1)

    def test_missing_you_label_is_rejected_with_korean_message(self):
        with self.assertRaisesRegex(ValueError, r'\(You\)'):
            parse_script('A: Hello\nB: Hi\n')

    def test_unlabelled_text_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_script('just some pasted words')

    def test_unlabelled_line_continues_previous_speaker(self):
        parsed = parse_script('Me (You): I like\nyour idea very much.\n')
        self.assertEqual(parsed['turns'][0]['text'], 'I like your idea very much.')


class MetricTests(unittest.TestCase):
    def test_base_metrics_values(self):
        metrics = base_metrics(parse_script(SAMPLE))
        self.assertEqual(metrics['ownWords'], 11)
        self.assertEqual(metrics['talkShare'], 61.1)
        self.assertEqual(metrics['wordsPerTurn'], 5.5)

    def test_disfluency_counts_fillers_and_restarts(self):
        metrics = base_metrics(parse_script('Me (You): I— I, um, think uh it is good.\n'))
        self.assertEqual(metrics['disfluencyPer100'], 37.5)

    def test_hash_ignores_other_speaker_lines(self):
        first = parse_script('A: One.\nMe (You): Same words here today.\n')
        second = parse_script('A: Two.\nMe (You): Same words here today.\n')
        self.assertEqual(content_hash(first['turns']), content_hash(second['turns']))


OTHER_SCRIPT = 'A: Tell me more.\nMe (You): I went there with my friends.\n'
LONG_SCRIPT = ''.join(
    f"A: Question {index}?\nMe (You): {'word ' * 100}number {index}.\n" for index in range(60)
)
MISTAKE = {
    'turn': 0,
    'sentence': 'I go to school yesterday.',
    'wrong': 'go',
    'corrected': 'I went to school yesterday.',
    'translation': '나는 어제 학교에 갔다.',
    'category': '시제',
    'pattern': 'past tense',
    'rule': '과거 시간 표현에는 과거 시제를 쓴다.',
}
WORD_ENTRY = {
    'term': 'yesterday',
    'meaning': '어제',
    'example': 'I saw it yesterday.',
    'target': 'yesterday',
}
EMPTY = {'mistakes': [], 'reviewFlags': [], 'vocabulary': []}
GOOD = {**EMPTY, 'mistakes': [MISTAKE], 'vocabulary': [WORD_ENTRY]}


def with_mistake(**changes: object) -> dict:
    return {**EMPTY, 'mistakes': [{**MISTAKE, **changes}]}


def with_vocabulary(**changes: object) -> dict:
    return {**EMPTY, 'vocabulary': [{**WORD_ENTRY, **changes}]}


def with_flag(kind: str) -> dict:
    flag = {'turn': 1, 'quote': 'Because.', 'kind': kind, 'note': '확인'}
    return {**EMPTY, 'reviewFlags': [flag]}


def many_vocabulary(count: int) -> dict:
    entries = [
        {'term': f'word{i}', 'meaning': '뜻', 'example': f'A word{i} here.', 'target': f'word{i}'}
        for i in range(count)
    ]
    return {**EMPTY, 'vocabulary': entries}


def session_with(categories: list[str]) -> dict:
    return {'mistakes': [{'category': name, 'pattern': name} for name in categories]}


def capture(prompts: list[str], result: dict):
    def codex(prompt: str, schema: dict) -> dict:
        prompts.append(prompt)
        return result
    return codex


def fail_on_second_call():
    calls = []

    def codex(prompt: str, schema: dict) -> dict:
        calls.append(prompt)
        if len(calls) == 2:
            raise ValueError('Codex 실패')
        return EMPTY
    return codex


class StoredReportTestCase(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = pathlib.Path(directory.name)

    def analyze(self, script: str = SAMPLE, date: str = '2026-11-03', codex=None) -> dict:
        data = {'script': script, 'date': date}
        return analyze_conversation(data, self.root, codex or (lambda p, s: EMPTY), lambda m: None)


class AnalyzeTests(StoredReportTestCase):
    def test_saves_valid_result_and_computes_mistake_rate(self):
        saved = self.analyze(codex=lambda p, s: GOOD)
        self.assertEqual(saved['metrics']['mistakesPer100'], 9.1)
        self.assertEqual(len(saved['mistakes']), 1)
        self.assertEqual(len(saved['vocabulary']), 1)

    def test_fabricated_sentence_is_dropped(self):
        saved = self.analyze(codex=lambda p, s: with_mistake(sentence='I never said this.'))
        self.assertEqual(saved['mistakes'], [])
        self.assertEqual(saved['droppedItems'], 1)

    def test_wrong_part_must_be_inside_sentence(self):
        saved = self.analyze(codex=lambda p, s: with_mistake(wrong='banana'))
        self.assertEqual(saved['mistakes'], [])

    def test_unknown_category_is_dropped(self):
        saved = self.analyze(codex=lambda p, s: with_mistake(category='발음'))
        self.assertEqual(saved['mistakes'], [])

    def test_out_of_range_turn_is_dropped(self):
        saved = self.analyze(codex=lambda p, s: with_mistake(turn=99))
        self.assertEqual(saved['mistakes'], [])

    def test_vocabulary_target_must_be_in_example(self):
        saved = self.analyze(codex=lambda p, s: with_vocabulary(target='absent'))
        self.assertEqual(saved['vocabulary'], [])

    def test_review_flags_are_not_counted_as_mistakes(self):
        saved = self.analyze(codex=lambda p, s: with_flag('transcription'))
        self.assertEqual(saved['metrics']['mistakesPer100'], 0)
        self.assertEqual(len(saved['reviewFlags']), 1)

    def test_zero_mistakes_gives_zero_rate(self):
        self.assertEqual(self.analyze()['metrics']['mistakesPer100'], 0)

    def test_duplicate_script_is_rejected(self):
        self.analyze()
        with self.assertRaisesRegex(ValueError, '이미 분석'):
            self.analyze()

    def test_failed_chunk_saves_nothing(self):
        with self.assertRaises(ValueError):
            self.analyze(script=LONG_SCRIPT, codex=fail_on_second_call())
        self.assertEqual(load_report(self.root)['conversations'], [])

    def test_saved_file_has_no_other_speaker_text(self):
        self.analyze(codex=lambda p, s: GOOD)
        raw = next((self.root / 'conversations').glob('*.json')).read_text()
        self.assertNotIn('Hello there', raw)

    def test_prompt_reuses_known_patterns(self):
        prompts: list[str] = []
        self.analyze(codex=capture(prompts, GOOD))
        self.analyze(script=OTHER_SCRIPT, codex=capture(prompts, EMPTY))
        self.assertIn('past tense', prompts[-1])

    def test_prompt_excludes_distant_other_lines(self):
        prompts: list[str] = []
        script = 'A: Private story.\nA: Close line.\nMe (You): I think so too.\n'
        self.analyze(script=script, codex=capture(prompts, EMPTY))
        self.assertIn('Close line.', prompts[0])
        self.assertNotIn('Private story', prompts[0])

    def test_vocabulary_is_deduplicated_and_capped_at_ten(self):
        saved = self.analyze(script=LONG_SCRIPT, codex=lambda p, s: many_vocabulary(14))
        self.assertEqual(len(saved['vocabulary']), 10)

    def test_invalid_date_is_rejected(self):
        with self.assertRaises(ValueError):
            self.analyze(date='11/03')


class StorageTests(StoredReportTestCase):
    def test_corrupt_file_is_skipped_and_counted(self):
        self.analyze(codex=lambda p, s: GOOD)
        (self.root / 'conversations' / 'broken.json').write_text('{')
        report = load_report(self.root)
        self.assertEqual(len(report['conversations']), 1)
        self.assertEqual(report['skipped'], 1)

    def test_conversations_are_sorted_by_date(self):
        self.analyze(script=OTHER_SCRIPT, date='2026-11-05')
        self.analyze(date='2026-11-03')
        dates = [item['date'] for item in load_report(self.root)['conversations']]
        self.assertEqual(dates, ['2026-11-03', '2026-11-05'])

    def test_delete_rejects_path_traversal(self):
        with self.assertRaises(ValueError):
            delete_conversation(self.root, '../secrets')

    def test_delete_removes_session_from_frequency(self):
        saved = self.analyze(codex=lambda p, s: GOOD)
        delete_conversation(self.root, saved['id'])
        self.assertEqual(load_report(self.root)['frequency']['categories'], [])


class FrequencyTests(unittest.TestCase):
    def test_counts_total_sessions_and_recent(self):
        sessions = [session_with(['관사', '관사', '시제']), session_with(['관사'])]
        top = frequency_summary(sessions)['categories'][0]
        self.assertEqual(
            (top['name'], top['total'], top['sessions'], top['recent']),
            ('관사', 3, 2, [2, 1]),
        )

    def test_recent_shows_zero_for_sessions_without_the_mistake(self):
        sessions = [session_with(['시제']), session_with(['관사'])]
        patterns = {item['name']: item for item in frequency_summary(sessions)['patterns']}
        self.assertEqual(patterns['시제']['recent'], [1, 0])


class ConversationApiTests(StoredReportTestCase):
    def setUp(self):
        super().setUp()
        patcher = mock.patch.object(server, 'DATA', self.root)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.server = server.create_server(0)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def request(self, method: str, path: str, body: dict | None = None, token: str | None = None):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        self.addCleanup(connection.close)
        headers = {'X-English-Token': token or server.TOKEN}
        connection.request(method, path, json.dumps(body) if body else None, headers)
        response = connection.getresponse()
        return response.status, json.loads(response.read())

    def wait(self, job: str) -> dict:
        for _ in range(100):
            _, state = self.request('GET', f'/api/jobs/{job}')
            if state['status'] != 'running':
                return state
            time.sleep(0.02)
        self.fail('job did not finish')

    def start_job(self, path: str, body: dict) -> dict:
        status, created = self.request('POST', path, body)
        self.assertEqual(status, 202)
        return self.wait(created['job'])

    def test_list_returns_empty_report(self):
        status, body = self.request('GET', '/api/conversations')
        self.assertEqual(status, 200)
        self.assertEqual(body['conversations'], [])

    def test_list_requires_token(self):
        status, _ = self.request('GET', '/api/conversations', token='wrong')
        self.assertEqual(status, 403)

    def test_analyze_job_stores_a_conversation(self):
        with mock.patch.object(server, 'codex_json', lambda prompt, schema: EMPTY):
            state = self.start_job(
                '/api/conversation-analyze', {'script': SAMPLE, 'date': '2026-11-03'}
            )
        self.assertEqual(state['status'], 'done')
        _, body = self.request('GET', '/api/conversations')
        self.assertEqual(len(body['conversations']), 1)

    def test_bad_script_reports_error_through_job(self):
        state = self.start_job(
            '/api/conversation-analyze', {'script': 'nothing', 'date': '2026-11-03'}
        )
        self.assertIn('(You)', state['error'])

    def test_delete_job_removes_conversation(self):
        saved = self.analyze()
        self.assertEqual(
            self.start_job('/api/conversation-delete', {'id': saved['id']})['status'], 'done'
        )
        _, body = self.request('GET', '/api/conversations')
        self.assertEqual(body['conversations'], [])


if __name__ == '__main__':
    unittest.main()
