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

class StartupTests(unittest.TestCase):
    def test_busy_port_falls_back_and_serves_dashboard(self):
        import threading, urllib.request
        occupied=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
        http=server.create_server(occupied.server_port)
        thread=threading.Thread(target=http.serve_forever,daemon=True)
        thread.start()
        try:
            self.assertNotEqual(http.server_port,occupied.server_port)
            base=f'http://127.0.0.1:{http.server_port}'
            with urllib.request.urlopen(base+'/') as response:
                self.assertEqual(response.status,200)
                self.assertIn('runtime.js',response.read().decode())
            request=urllib.request.Request(base+'/api/health',headers={'X-English-Token':server.TOKEN})
            with urllib.request.urlopen(request) as response:
                self.assertTrue(__import__('json').load(response)['ok'])
            with self.assertRaises(urllib.error.HTTPError) as denied:
                urllib.request.urlopen(base+'/api/health')
            self.assertEqual(denied.exception.code,403)
            denied.exception.close()
        finally:
            http.shutdown();http.server_close();thread.join();occupied.server_close()

    def test_other_bind_errors_are_reported(self):
        import errno
        from unittest.mock import patch
        with patch.object(server,'ThreadingHTTPServer',side_effect=PermissionError(errno.EACCES,'denied')) as bind:
            with self.assertRaises(PermissionError):server.create_server()
            self.assertEqual(bind.call_count,1)

    def test_server_exits_when_parent_is_gone(self):
        import os, subprocess, sys
        process=subprocess.Popen([sys.executable,server.__file__],env={**os.environ,'ENGLISH_PARENT_PID':'-1','ENGLISH_PORT':'0'},stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            self.assertEqual(process.wait(timeout=4),0)
        finally:
            if process.poll() is None:process.kill()
            process.communicate()

class YouTubeDownloadTests(unittest.TestCase):
    def test_403_reextracts_without_resuming_partial_file(self):
        import audio_clips, tempfile, pathlib, json
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmp:
            folder=pathlib.Path(tmp)
            calls=[]
            def download(args,**kwargs):
                calls.append(args)
                if len(calls)==1:raise ValueError('HTTP Error 403: Forbidden')
                (folder/'source.mp3').write_bytes(b'a'*2000)
            with patch.object(audio_clips,'discover_audio',return_value={'youtube':'https://youtu.be/abcdefghijk','sourceUrl':'https://youtu.be/abcdefghijk'}):
                source,info=audio_clips.download_source({},folder,download,'yt-dlp')
            self.assertTrue(source.exists())
            self.assertEqual(len(calls),2)
            self.assertIn('--no-continue',calls[1])
            self.assertIn('--force-overwrites',calls[1])
            self.assertEqual(calls[1][-2:],['--','https://youtu.be/abcdefghijk'])
            self.assertEqual(json.loads((folder/'source.json').read_text()),info)

    def test_persistent_403_is_actionable_and_does_not_cache_success(self):
        import audio_clips, tempfile, pathlib
        from unittest.mock import patch, Mock
        with tempfile.TemporaryDirectory() as tmp:
            folder=pathlib.Path(tmp)
            download=Mock(side_effect=ValueError('HTTP Error 403: Forbidden'))
            with patch.object(audio_clips,'discover_audio',return_value={'youtube':'https://youtu.be/abcdefghijk'}):
                with self.assertRaisesRegex(ValueError,'YouTube.*403'):
                    audio_clips.download_source({},folder,download,'yt-dlp')
            self.assertEqual(download.call_count,2)
            self.assertFalse((folder/'source.json').exists())

    def test_unrelated_download_errors_are_not_retried(self):
        import audio_clips, tempfile, pathlib
        from unittest.mock import patch, Mock
        with tempfile.TemporaryDirectory() as tmp:
            download=Mock(side_effect=ValueError('private video'))
            with patch.object(audio_clips,'discover_audio',return_value={'youtube':'https://youtu.be/abcdefghijk'}):
                with self.assertRaisesRegex(ValueError,'private video'):
                    audio_clips.download_source({},pathlib.Path(tmp),download,'yt-dlp')
            self.assertEqual(download.call_count,1)

class DownloaderRuntimeTests(unittest.TestCase):
    def test_app_runtime_is_preferred_over_homebrew(self):
        import youtube_tools
        from unittest.mock import patch
        with patch.dict('os.environ',{},clear=True),patch.object(youtube_tools.pathlib.Path,'is_file',return_value=True):
            self.assertEqual(youtube_tools.downloader_path(),str(youtube_tools.RUNTIME/'bin/yt-dlp'))

    def test_explicit_downloader_override_is_respected(self):
        import youtube_tools
        from unittest.mock import patch
        with patch.dict('os.environ',{'ENGLISH_YTDLP':'/custom/yt-dlp'}):
            self.assertEqual(youtube_tools.downloader_path(),'/custom/yt-dlp')

class SentenceAudioTests(unittest.TestCase):
    def test_sentence_extends_beyond_quote_and_across_captions(self):
        import audio_clips
        transcript='[00:00:01] An earlier sentence. And the reason I say\n[00:00:03] this is because in hindsight\n[00:00:05] it all makes a lot of sense. Next sentence.'
        card={'expression':'it all makes a lot of sense','quote':'in hindsight it all makes a lot of sense.'}
        context=audio_clips.sentence_context(card,transcript)
        self.assertEqual(context['text'],'And the reason I say this is because in hindsight it all makes a lot of sense.')
        self.assertEqual(context['start'],1)
        self.assertNotIn('Next',context['tokens'])

    def test_repeated_expression_uses_quote_and_excludes_speaker_names(self):
        import audio_clips
        transcript='Alex [00:00:01]: I see your point.\nSam [00:00:10]: Well, I see your point about the product.\nAlex [00:00:20]: Another sentence.'
        context=audio_clips.sentence_context({'expression':'I see your point','quote':'I see your point about the product.'},transcript)
        self.assertEqual(context['text'],'Well, I see your point about the product.')
        self.assertEqual(context['start'],10)

    def test_missing_sentence_end_is_not_replaced_by_a_phrase(self):
        import audio_clips
        with self.assertRaisesRegex(ValueError,'문장의 끝'):
            audio_clips.sentence_context({'expression':'your point','quote':'your point'},'[00:00:01] I see your point')

    def test_alignment_covers_sentence_not_only_expression(self):
        import audio_clips
        sentence='And the reason is that it all makes a lot of sense'
        words=[{'word':word,'start':i*.3,'end':(i+1)*.3} for i,word in enumerate(sentence.split())]
        context={'tokens':audio_clips.tokens(sentence),'expressionStart':102}
        a,b=audio_clips.align_sentence(words,context,'it all makes a lot of sense',100)
        self.assertEqual(a,100)
        self.assertAlmostEqual(b,103.6)

    def test_partial_sentence_does_not_align(self):
        import audio_clips
        words=[{'word':word,'start':i,'end':i+1} for i,word in enumerate('it all makes a lot of sense'.split())]
        context={'tokens':audio_clips.tokens('And the reason is that it all makes a lot of sense'),'expressionStart':0}
        self.assertIsNone(audio_clips.align_sentence(words,context,'it all makes a lot of sense',0))

    def test_old_phrase_clip_is_not_reused(self):
        import audio_clips,tempfile,pathlib,json,uuid,hashlib
        from unittest.mock import patch
        sid=str(uuid.uuid4());card={'expression':'your point','quote':'I see your point.'}
        with tempfile.TemporaryDirectory() as tmp:
            root=pathlib.Path(tmp);folder=root/'audio'/sid;folder.mkdir(parents=True)
            session={'id':sid,'url':'https://youtu.be/abcdefghijk','transcript':'[00:00:01] I see your point.\n[00:00:04] Next sentence.','expressions':[card]}
            (root/(sid+'.json')).write_text(json.dumps(session))
            old=hashlib.sha256((card['expression']+'\n'+card['quote']).encode()).hexdigest()[:16]
            (folder/f'0-{old}.mp3').write_bytes(b'old clip')
            (folder/f'0-{old}.json').write_text(json.dumps({'kind':'old-phrase'}))
            def run(args,**kwargs):
                output=pathlib.Path(args[-1])
                if output.suffix=='.json':
                    output.write_text(json.dumps({'words':[{'word':word,'start':i*.4+1,'end':(i+1)*.4+1} for i,word in enumerate('I see your point'.split())]}))
                else:output.write_bytes(b'new sentence clip')
            with patch.object(audio_clips,'AUDIO_PYTHON',__file__),patch.object(audio_clips,'download_source',return_value=(folder/'source.mp3',{'sourceUrl':session['url']})):
                result=audio_clips.prepare({'sessionId':sid,'index':0},root,run,'yt-dlp')
            self.assertEqual(result['kind'],'original-podcast-sentence')
            self.assertEqual(result['sentence'],'I see your point.')
            self.assertNotIn(old,result['clipUrl'])

class SourceSentenceTranslationTests(unittest.TestCase):
    def test_source_sentence_is_full_original_not_practice_example(self):
        session={'transcript':'[00:00:01] For me personally, I love building products.\n[00:00:05] Another sentence.','expressions':[{'expression':'for me personally','quote':'For me personally','example':'For me personally, smaller classes are easier.'}]}
        server.attach_source_sentences(session)
        self.assertEqual(session['expressions'][0]['sourceSentence'],'For me personally, I love building products.')

    def test_changed_sentence_invalidates_translation(self):
        session={'transcript':'[00:00:01] I see your point.','expressions':[{'expression':'your point','quote':'I see your point.','sourceSentence':'An older sentence.','sourceSentenceTranslation':'잘못된 이전 해석'}]}
        server.attach_source_sentences(session)
        self.assertNotIn('sourceSentenceTranslation',session['expressions'][0])

    def test_translates_source_and_preserves_practice_example(self):
        import tempfile,pathlib,json,uuid
        from unittest.mock import patch
        sid=str(uuid.uuid4())
        session={'id':sid,'transcript':'[00:00:01] I see your point.','expressions':[{'expression':'your point','quote':'I see your point.','example':'I see your point about school.','exampleTranslation':'학교에 관한 의견은 이해해요.'}]}
        with tempfile.TemporaryDirectory() as tmp,patch.object(server,'DATA',pathlib.Path(tmp)):
            path=pathlib.Path(tmp)/(sid+'.json');path.write_text(json.dumps(session))
            def translate(prompt,schema):
                self.assertIn('I see your point.',prompt)
                self.assertNotIn('about school',prompt)
                return {'translations':[{'index':0,'translation':'무슨 말씀인지 이해해요.'}]}
            with patch.object(server,'codex_json',side_effect=translate) as model:
                result=server.translate_source_sentences({'sessionId':sid})
                again=server.translate_source_sentences({'sessionId':sid})
                self.assertEqual(model.call_count,1)
            card=result['expressions'][0]
            self.assertEqual(card['sourceSentenceTranslation'],'무슨 말씀인지 이해해요.')
            self.assertEqual(card['example'],session['expressions'][0]['example'])
            self.assertEqual(again,result)

    def test_incomplete_translation_is_not_saved(self):
        import tempfile,pathlib,json,uuid
        from unittest.mock import patch
        sid=str(uuid.uuid4());session={'id':sid,'transcript':'[00:00:01] I see your point.','expressions':[{'expression':'your point','quote':'I see your point.'}]}
        with tempfile.TemporaryDirectory() as tmp,patch.object(server,'DATA',pathlib.Path(tmp)),patch.object(server,'codex_json',return_value={'translations':[]}):
            path=pathlib.Path(tmp)/(sid+'.json');path.write_text(json.dumps(session))
            with self.assertRaises(ValueError):server.translate_source_sentences({'sessionId':sid})
            self.assertEqual(json.loads(path.read_text()),session)
