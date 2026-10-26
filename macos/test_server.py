import unittest
import server
class TranscriptTests(unittest.TestCase):
    def test_rolling_captions(self):
        raw='WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nWhat makes you say that?\n\n00:00:02.000 --> 00:00:03.000\nWhat makes you say that?\nI see your point.\n\n00:00:03.000 --> 00:00:04.000\nI see your point.\n'
        self.assertEqual(server.parse_vtt(raw),'What makes you say that?\nI see your point.')
    def test_blocks_other_hosts_and_bad_ids(self):
        for url in ['https://youtube.com.evil.test/watch?v=abcdefghijk','http://localhost:8000','https://youtube.com/watch?v=bad','file:///etc/passwd']:
            with self.assertRaises(ValueError):server.video_url(url)
        self.assertEqual(server.video_url('https://youtu.be/abcdefghijk'),'https://www.youtube.com/watch?v=abcdefghijk')
    def test_rejects_fabricated_quote(self):
        cards=[{'expression':f'phrase {i}','meaning':'뜻','quote':f'phrase {i}','example':'new example','tip':'팁'} for i in range(10)]
        source=' '.join(c['quote'] for c in cards)
        self.assertEqual(len(server.validate({'expressions':cards},source)),10)
        cards[3]['quote']='fabricated sentence'
        with self.assertRaises(ValueError):server.validate({'expressions':cards},source)
if __name__=='__main__':unittest.main()
