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

class AudioTimingTests(unittest.TestCase):
    def test_timestamp_lookup_prefers_exact_quote(self):
        import audio_clips
        transcript='Speaker [00:01:00]: I see your point.\nOther [00:01:08]: Next thought.\nSpeaker [00:02:00]: Well, I see your point about the product.\nOther [00:02:12]: Yes.'
        card={'expression':'I see your point','quote':'I see your point about the product.'}
        start,end,_=audio_clips.locate_turn(card,transcript)
        self.assertEqual((start,end),(120,132))
    def test_untimed_text_is_not_guessed(self):
        import audio_clips
        with self.assertRaises(ValueError):audio_clips.locate_turn({'expression':'I see your point','quote':'I see your point'},'I see your point.')
    def test_downloaded_subtitles_keep_time_information(self):
        raw='WEBVTT\n\n00:00:12.340 --> 00:00:15.670\nI see your point.\n'
        self.assertEqual(server.parse_vtt(raw,include_timestamps=True),'[00:00:12] I see your point.')


class YouTubeSourceTests(unittest.TestCase):
    def test_source_input_requires_youtube_url(self):
        self.assertEqual(server.search('https://youtu.be/abcdefghijk?t=20')['url'],'https://www.youtube.com/watch?v=abcdefghijk')
        with self.assertRaises(ValueError):server.search('some podcast title')
    def test_jump_links_come_from_caption_times(self):
        session={'url':'https://www.youtube.com/watch?v=abcdefghijk','transcript':'[00:05:19] I see your point.\n[00:05:23] Another thought.','expressions':[{'expression':'I see your point','quote':'I see your point.'}]}
        server.attach_youtube_positions(session)
        self.assertEqual(session['expressions'][0]['youtubeStart'],319)
        self.assertTrue(session['expressions'][0]['youtubeUrl'].endswith('&t=319s'))
    def test_no_timestamp_has_no_invented_jump_link(self):
        session={'url':'https://www.youtube.com/watch?v=abcdefghijk','transcript':'I see your point.','expressions':[{'expression':'I see your point','quote':'I see your point.'}]}
        server.attach_youtube_positions(session)
        self.assertNotIn('youtubeUrl',session['expressions'][0])


class CaptionBoundaryTests(unittest.TestCase):
    def test_phrase_spanning_caption_lines_has_real_start(self):
        import audio_clips
        text='[00:00:12] I see your\n[00:00:14] point about the product.\n[00:00:17] Another thought.'
        start,end,_=audio_clips.locate_turn({'expression':'I see your point','quote':'I see your point about the product.'},text)
        self.assertEqual((start,end),(12,17))
        self.assertIn(server.norm('I see your point'),server.norm(text))

class LongTranscriptTests(unittest.TestCase):
    def test_all_text_covered_without_total_length_cap(self):
        text=''.join(f'line {i:06d} ABCDEFGHIJKLMNOPQRSTUVWXYZ\n' for i in range(14000))+'END_VERIFIED'
        chunks=server.transcript_chunks(text)
        self.assertGreater(len(text),500000)
        self.assertTrue(chunks[-1].endswith('END_VERIFIED'))
        cursor=0
        for chunk in chunks:
            position=text.find(chunk,max(0,cursor-2000))
            self.assertGreaterEqual(position,0)
            self.assertLessEqual(position,cursor)
            cursor=max(cursor,position+len(chunk))
        self.assertEqual(cursor,len(text))
    def test_counts_and_long_extraction(self):
        from unittest.mock import patch
        import tempfile,pathlib,re
        source=''.join(f'Can you explain item {i:06d}? This is a useful conversation practice sentence.\n' for i in range(4200))+'END_VERIFIED'
        for count in (10,20,30):
            calls=[]
            def fake_extract(chunk,title,quota,exclude):
                calls.append(chunk)
                phrases=[f'Can you explain item {n}' for n in re.findall(r'Can you explain item (\d{6})',chunk)]
                phrases=[p for p in phrases if p not in exclude][:quota]
                return [{'expression':p,'quote':p+'?','meaning':'뜻','example':p+'?','exampleTranslation':'예시 해석','tip':'설명'} for p in phrases]
            with tempfile.TemporaryDirectory() as tmp,patch.object(server,'DATA',pathlib.Path(tmp)),patch.object(server,'extract_chunk',side_effect=fake_extract),patch.object(server,'select_cards',side_effect=lambda cards,n:cards[:n]):
                result=server.extract({'transcript':source,'count':count})
                self.assertEqual(len(result['expressions']),count)
                self.assertEqual(result['transcript'],source)
                self.assertIn('END_VERIFIED',calls[-1])
    def test_invalid_count_rejected(self):
        for count in (0,9,15,40,True,'20'):
            with self.assertRaises(ValueError):server.extract({'count':count,'transcript':'x'*1000})

class LargeRequestTests(unittest.TestCase):
    def test_request_over_old_body_limit_is_accepted(self):
        from unittest.mock import patch
        import urllib.request,threading,json,time
        body=json.dumps({'transcript':'x'*650000,'count':30}).encode()
        http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
        thread=threading.Thread(target=http.serve_forever,daemon=True);thread.start()
        try:
            with patch.object(server,'extract',side_effect=lambda data,*_: {'receivedLength':len(data['transcript']),'count':data['count']}):
                request=urllib.request.Request(f'http://127.0.0.1:{http.server_port}/api/extract',data=body,headers={'X-English-Token':server.TOKEN,'Content-Type':'application/json'})
                with urllib.request.urlopen(request) as response:
                    self.assertEqual(response.status,202);job=json.load(response)['job']
                for _ in range(100):
                    if server.JOBS[job]['status']!='running':break
                    time.sleep(.01)
                self.assertEqual(server.JOBS[job]['result'],{'receivedLength':650000,'count':30})
        finally:http.shutdown();http.server_close();thread.join()
