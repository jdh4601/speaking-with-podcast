import unittest

from conversation_report import base_metrics, content_hash, parse_script

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


if __name__ == '__main__':
    unittest.main()
