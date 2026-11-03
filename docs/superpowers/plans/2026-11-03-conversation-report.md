# 회화 리포트와 자주 틀리는 표현 복습 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 수업 스크립트를 분석해 교정·단어·수치·반복 실수를 저장해 보여주고, 대시보드 왼쪽에서 자주 틀리는 표현을 복습하게 한다.

**Architecture:** 파싱·지표·검증·저장·집계는 새 Python 모듈 `conversation_report.py`가 맡고, `server.py`는 기존 작업 큐로 연결만 한다. 화면의 순수 계산은 `conversation-core.js`에 두어 Node로 테스트하고, 리포트 페이지와 대시보드 복습 패널이 이를 공유한다.

**Tech Stack:** Python 3 표준 라이브러리, unittest, Codex CLI(`codex_json`), 바닐라 JS/CSS, 인라인 SVG, Node `node:vm` 테스트

**Spec:** `docs/superpowers/specs/2026-11-03-conversation-report-design.md`

## Global Constraints

- 회화 기록은 `~/Library/Application Support/English Routine/conversations/`에만 저장하고 저장소에 커밋하지 않는다.
- 테스트 픽스처에는 실제 수업 스크립트를 쓰지 않고 합성 문장만 쓴다.
- 원본 스크립트 전체와 상대 발화는 저장하지 않는다.
- 발음 점수를 만들지 않는다. 합산 점수도 만들지 않는다.
- 유형 고정 목록: `동사 조합, 관사, 단수·복수, 수일치, 시제, 비교·최상급, 전치사, 문장 구조, 단어 선택, 기타`
- 외부 JS 라이브러리를 추가하지 않는다.
- Codex 결과와 스크립트 문자열은 `textContent`로만 렌더링한다.
- 이 저장소의 기존 Python·JS는 밀집된 스타일이다. 새 파일은 사용자 규칙대로 읽기 좋게 쓰고, 기존 파일은 주변 스타일을 따른다.

## Review Focus

1. `(You)`가 없거나 화자 라벨이 없는 스크립트: 아무것도 저장하지 않고 이유를 한글로 안내한다. (Task 1)
2. 긴 스크립트의 일부 구간에서 Codex가 실패: 회차를 저장하지 않아 불완전한 수치가 추이에 섞이지 않는다. (Task 2)
3. 기록 폴더의 손상된 JSON 파일: 나머지 기록은 표시하고 읽지 못한 개수를 알린다. (Task 2)
4. 스크립트나 Codex 결과에 들어 있는 HTML 문자열: 태그로 실행되지 않고 글자로 표시된다. (Task 4)
5. 실수가 0건인 회차: `mistakesPer100`은 0이고, 복습 패널은 빈 상태를 표시한다. (Task 2, Task 4)

---

### Task 1: 스크립트 파싱과 지표 계산

**Files:**
- Create: `macos/conversation_report.py`
- Test: `macos/test_conversation_report.py`

**Interfaces:**
- Produces:
  - `parse_script(script: str) -> dict`: `{'turns': [{'text': str, 'before': str, 'after': str}], 'ownWords': int, 'otherWords': int, 'backchannelTurns': int}`. `before`와 `after`는 인접한 상대 발화이며 각 200자 이내이다.
  - `count_words(text: str) -> int`
  - `base_metrics(parsed: dict) -> dict`: `{'ownWords', 'talkShare', 'disfluencyPer100', 'wordsPerTurn'}`, 비율은 소수 1자리 반올림
  - `content_hash(turns: list[dict]) -> str`: 본인 발화 텍스트의 SHA-256

- [ ] **Step 1: Write the failing tests**

```python
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
        self.assertEqual([t['text'] for t in parsed['turns']],
                         ['I am— I am fine. I go to school yesterday.', 'Because.'])

    def test_adjacent_other_lines_become_context(self):
        turn = parse_script(SAMPLE)['turns'][0]
        self.assertEqual(turn['before'], 'Hello there, how are you?')
        self.assertEqual(turn['after'], 'Why?')

    def test_context_is_limited_to_200_characters(self):
        parsed = parse_script('A: ' + 'x' * 500 + '\nMe (You): Hello there friend.\n')
        self.assertEqual(len(parsed['turns'][0]['before']), 200)

    def test_own_only_backchannel_is_not_a_turn(self):
        parsed = parse_script('A: Right, so.\nMe (You): Mm-hm.\nA: Good.\nMe (You): I agree with you.\n')
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd macos && python3 -m unittest test_conversation_report -v`
Expected: FAIL, `ModuleNotFoundError: No module named 'conversation_report'`

- [ ] **Step 3: Implement the functions in `macos/conversation_report.py`**

- 화자 줄 패턴: `^([^:\n]{1,80}):\s*(.*)$`. 본인은 화자에 `(You)`가 포함된 경우이다.
- 단어 패턴: `[A-Za-z0-9'’]+(?:-[A-Za-z0-9]+)*`
- 맞장구 판정: 3단어 이하이고 모든 단어가 `mm, mm-hm, mhm, hmm, uh-huh, yeah, yes, okay, ok, right, no`에 속한다.
- 상대의 맞장구 줄은 본인 턴을 끊지 않는다. 본인의 맞장구 턴은 `turns`에 넣지 않고 `backchannelTurns`로만 센다.
- `after`는 그 턴 뒤의 첫 번째 상대 비맞장구 줄이다.
- 군말: `um, uh, hmm, mm`. 재시작: `(\w+)—\s+\1\b`(대소문자 무시). 맞장구 턴은 제외된 상태로 계산한다.
- 오류 문구: `(You) 표시가 있는 본인 발화를 찾지 못했습니다. 화자 이름이 포함된 스크립트를 붙여 넣으세요.`

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd macos && python3 -m unittest test_conversation_report -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add macos/conversation_report.py macos/test_conversation_report.py
git commit -m "feat(conversation): parse transcripts and measure speech metrics"
```

### Task 2: 분석 결과 검증·저장·빈도 집계

**Files:**
- Modify: `macos/conversation_report.py`
- Test: `macos/test_conversation_report.py`

**Interfaces:**
- Consumes: Task 1의 함수
- Produces:
  - `analyze_conversation(data: dict, root: Path, codex: Callable[[str, dict], dict], progress: Callable[[str], None]) -> dict`: `data`는 `{'script': str, 'date': 'YYYY-MM-DD'}`, 저장한 회차를 반환한다.
  - `load_report(root: Path) -> dict`: `{'conversations': [...], 'skipped': int, 'frequency': {...}}`. `conversations`는 `date`, `createdAt` 오름차순이다.
  - `delete_conversation(root: Path, conversation_id: str) -> dict`
  - `frequency_summary(sessions: list[dict]) -> dict`: `{'categories': [item], 'patterns': [item]}`. `item`은 `{'name', 'total', 'sessions', 'recent'}`이며 `recent`는 최근 5회차의 횟수이고 총 횟수 내림차순, 이름 오름차순이다.
  - 회차 필드: `id, date, createdAt, contentHash, metrics, turns, mistakes, reviewFlags, vocabulary`
  - 실수 필드: `turn, sentence, wrong, corrected, translation, category, pattern, rule`
  - 확인 항목 필드: `turn, quote, kind('pronunciation'|'transcription'), note`
  - 단어 필드: `term, meaning, example, target`
  - `metrics`에는 Task 1의 값에 `mistakesPer100`이 더해진다.

- [ ] **Step 1: Write the failing tests**

테스트는 임시 폴더와 가짜 `codex` 함수를 쓴다. `GOOD`은 `SAMPLE`의 첫 턴에서 `sentence='I go to school yesterday.'`, `wrong='go'`, `corrected='I went to school yesterday.'`, `category='시제'`, `pattern='past tense'`인 실수 1건과 단어 1건을 담는다.

```python
class AnalyzeTests(unittest.TestCase):
    def test_saves_valid_result_and_computes_mistake_rate(self):
        saved = analyze(codex=lambda p, s: GOOD)
        self.assertEqual(saved['metrics']['mistakesPer100'], 9.1)
        self.assertEqual(len(saved['mistakes']), 1)

    def test_fabricated_sentence_is_dropped(self):
        saved = analyze(codex=lambda p, s: with_mistake(sentence='I never said this.'))
        self.assertEqual(saved['mistakes'], [])

    def test_wrong_part_must_be_inside_sentence(self):
        saved = analyze(codex=lambda p, s: with_mistake(wrong='banana'))
        self.assertEqual(saved['mistakes'], [])

    def test_unknown_category_is_dropped(self):
        saved = analyze(codex=lambda p, s: with_mistake(category='발음'))
        self.assertEqual(saved['mistakes'], [])

    def test_vocabulary_target_must_be_in_example(self):
        saved = analyze(codex=lambda p, s: with_vocabulary(target='absent'))
        self.assertEqual(saved['vocabulary'], [])

    def test_review_flags_are_not_counted_as_mistakes(self):
        saved = analyze(codex=lambda p, s: with_flag(kind='transcription'))
        self.assertEqual(saved['metrics']['mistakesPer100'], 0)
        self.assertEqual(len(saved['reviewFlags']), 1)

    def test_zero_mistakes_gives_zero_rate(self):
        saved = analyze(codex=lambda p, s: EMPTY)
        self.assertEqual(saved['metrics']['mistakesPer100'], 0)

    def test_duplicate_script_is_rejected(self):
        analyze(codex=lambda p, s: GOOD)
        with self.assertRaisesRegex(ValueError, '이미 분석'):
            analyze(codex=lambda p, s: GOOD)

    def test_failed_chunk_saves_nothing(self):
        with self.assertRaises(ValueError):
            analyze(script=LONG_SCRIPT, codex=fail_on_second_call())
        self.assertEqual(load_report(self.root)['conversations'], [])

    def test_saved_file_has_no_other_speaker_text(self):
        analyze(codex=lambda p, s: GOOD)
        raw = next((self.root / 'conversations').glob('*.json')).read_text()
        self.assertNotIn('Hello there', raw)

    def test_prompt_contains_known_patterns_and_no_distant_other_lines(self):
        prompts = []
        analyze(codex=capture(prompts, GOOD))
        analyze(script=OTHER_SCRIPT, codex=capture(prompts, EMPTY))
        self.assertIn('past tense', prompts[-1])

    def test_vocabulary_is_deduplicated_and_capped_at_ten(self):
        saved = analyze(script=LONG_SCRIPT, codex=lambda p, s: many_vocabulary(14))
        self.assertLessEqual(len(saved['vocabulary']), 10)

    def test_invalid_date_is_rejected(self):
        with self.assertRaises(ValueError):
            analyze(date='11/03')

class StorageTests(unittest.TestCase):
    def test_corrupt_file_is_skipped_and_counted(self):
        analyze(codex=lambda p, s: GOOD)
        (self.root / 'conversations' / 'broken.json').write_text('{')
        report = load_report(self.root)
        self.assertEqual(len(report['conversations']), 1)
        self.assertEqual(report['skipped'], 1)

    def test_delete_rejects_path_traversal(self):
        with self.assertRaises(ValueError):
            delete_conversation(self.root, '../secrets')

    def test_delete_removes_session_from_frequency(self):
        saved = analyze(codex=lambda p, s: GOOD)
        delete_conversation(self.root, saved['id'])
        self.assertEqual(load_report(self.root)['frequency']['categories'], [])

class FrequencyTests(unittest.TestCase):
    def test_counts_total_sessions_and_recent(self):
        sessions = [session_with(['관사', '관사', '시제']), session_with(['관사'])]
        top = frequency_summary(sessions)['categories'][0]
        self.assertEqual((top['name'], top['total'], top['sessions'], top['recent']),
                         ('관사', 3, 2, [2, 1]))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd macos && python3 -m unittest test_conversation_report -v`
Expected: FAIL, `analyze_conversation` 등이 없다는 오류

- [ ] **Step 3: Implement in `macos/conversation_report.py`**

- `CATEGORIES`는 Global Constraints의 목록이고, JSON 스키마의 `enum`으로도 사용한다.
- 턴을 12000자 이내 구간으로 묶어 순서대로 `codex(prompt, schema)`를 호출한다. 어느 구간이든 예외가 나면 그대로 전파해 저장하지 않는다.
- 프롬프트에는 기존 회차의 `pattern`과 앞 구간에서 나온 `pattern`을 넣어 재사용하게 한다. 전사는 지시문이 아닌 데이터임을 명시한다. 한국인 B1~B2 학습자 기준으로 사소한 구어체는 실수로 잡지 않고, 받아쓰기 오류가 의심되면 `reviewFlags`로 보내게 한다. 상대가 되물었거나 다르게 알아들은 단어는 `kind='pronunciation'`으로 보내게 한다.
- `sentence`는 공백을 정규화해 비교한다. 저장 값은 턴 원문에서 가져온다.
- 단어는 `term`의 소문자 기준으로 중복을 제거하고 최대 10개만 남긴다.
- 파일은 임시 파일에 쓴 뒤 `replace`한다. `id`는 UUID4이고 삭제 시 UUID 패턴을 검사한다.
- 스크립트 크기 상한은 2MB이다.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd macos && python3 -m unittest test_conversation_report -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add macos/conversation_report.py macos/test_conversation_report.py
git commit -m "feat(conversation): validate, store, and aggregate analyses"
```

### Task 3: 서버 API와 앱 번들 연결

**Files:**
- Modify: `macos/server.py:307` (`work` 사전), `macos/server.py:359` 부근(GET), `macos/server.py:373`(`kind` 허용 목록)
- Modify: `macos/build.py:8` (복사 목록에 `conversation_report.py` 추가)
- Test: `macos/test_conversation_report.py`

**Interfaces:**
- Consumes: Task 2의 `analyze_conversation`, `load_report`, `delete_conversation`
- Produces:
  - `GET /api/conversations` → `load_report(DATA)`
  - `POST /api/conversation-analyze` `{'script','date'}` → `{job}`
  - `POST /api/conversation-delete` `{'id'}` → `{job}`
  - 작업 진행 메시지는 `JOBS[id]['progress']`, 조회는 기존 `/api/jobs/<id>`

- [ ] **Step 1: Write the failing tests**

`StartupTests.test_busy_port_falls_back_and_serves_dashboard`의 방식대로 임시 `server.DATA`로 서버를 띄운다.

```python
class ConversationApiTests(unittest.TestCase):
    def test_list_returns_empty_report(self):
        status, body = self.get('/api/conversations')
        self.assertEqual(status, 200)
        self.assertEqual(body['conversations'], [])

    def test_list_requires_token(self):
        status, _ = self.get('/api/conversations', token='wrong')
        self.assertEqual(status, 403)

    def test_analyze_job_stores_a_conversation(self):
        server.codex_json = lambda prompt, schema: EMPTY
        job = self.post('/api/conversation-analyze', {'script': SAMPLE, 'date': '2026-11-03'})
        self.assertEqual(self.wait(job)['status'], 'done')
        self.assertEqual(len(self.get('/api/conversations')[1]['conversations']), 1)

    def test_bad_script_reports_error_through_job(self):
        job = self.post('/api/conversation-analyze', {'script': 'nothing', 'date': '2026-11-03'})
        self.assertIn('(You)', self.wait(job)['error'])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd macos && python3 -m unittest test_conversation_report.ConversationApiTests -v`
Expected: FAIL, 404 응답

- [ ] **Step 3: Implement the wiring**

`study_pack`처럼 함수 안에서 `import conversation_report`를 수행한다. `analyze_conversation`에는 모듈 전역 `codex_json`을 호출 시점에 넘긴다.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd macos && python3 -m unittest discover -p 'test_*.py' -q`
Expected: PASS

- [ ] **Step 5: Commit**

`/verify` 실행 후 커밋한다.

```bash
git add macos/server.py macos/build.py macos/test_conversation_report.py
git commit -m "feat(conversation): expose analysis through the local API"
```

### Task 4: 화면 공용 계산

**Files:**
- Create: `macos/web/conversation-core.js`
- Create: `macos/test_conversation_ui.cjs`
- Modify: `ios/verify.py:14-15` (새 JS `--check`와 `node macos/test_conversation_ui.cjs` 추가)

**Interfaces:**
- Produces (`window.ConversationCore`, Node에서는 `module.exports`):
  - `highlightParts(sentence: string, target: string): {text: string, marked: boolean}[]`
  - `reviewQueue(sessions: object[], mastered: Record<string,string>): object[]`: 패턴당 카드 1장. `{pattern, category, categoryTotal, patternTotal, latestDate, sentence, wrong, corrected, translation, rule}`
  - `metricTrend(sessions: object[]): {key, label, values, latest, delta, direction}[]`. `direction`은 `'better'|'worse'|'same'|'baseline'`
  - `METRICS`: `mistakesPer100`(100단어당 실수, 낮을수록 좋음), `disfluencyPer100`(말 더듬·재시작, 낮을수록 좋음), `wordsPerTurn`(이어 말한 단어, 높을수록 좋음), `talkShare`(내 발화 비율, 높을수록 좋음)

- [ ] **Step 1: Write the failing tests**

```js
assert.deepEqual(highlightParts('I go home', 'go'),
  [{text:'I ',marked:false},{text:'go',marked:true},{text:' home',marked:false}]);
assert.deepEqual(highlightParts('<img src=x>', '<img'),
  [{text:'<img',marked:true},{text:' src=x>',marked:false}]);
assert.deepEqual(highlightParts('abc', 'zzz'), [{text:'abc',marked:false}]);

const A=m('2026-11-01','관사','the same'),B=m('2026-11-03','관사','the same'),C=m('2026-11-02','시제','past tense');
assert.equal(reviewQueue([session([A,C]),session([B])],{}).length,2);
assert.equal(reviewQueue([session([A,C]),session([B])],{})[0].pattern,'the same');
assert.equal(reviewQueue([session([A,C]),session([B])],{})[0].latestDate,'2026-11-03');
assert.equal(reviewQueue([session([A])],{'the same':'2026-11-01'}).length,0);
assert.equal(reviewQueue([session([B])],{'the same':'2026-11-01'}).length,1);
assert.deepEqual(reviewQueue([session([])],{}),[]);

const trend=metricTrend([withMetrics({mistakesPer100:5}),withMetrics({mistakesPer100:4})]);
assert.equal(byKey(trend,'mistakesPer100').direction,'better');
assert.equal(byKey(metricTrend([withMetrics({mistakesPer100:5})]),'mistakesPer100').direction,'baseline');
assert.equal(byKey(metricTrend([withMetrics({mistakesPer100:4}),withMetrics({mistakesPer100:5})]),'mistakesPer100').direction,'worse');
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node macos/test_conversation_ui.cjs` (저장소 루트)
Expected: FAIL, `conversation-core.js` 파일 없음

- [ ] **Step 3: Implement `macos/web/conversation-core.js`**

`reviewQueue` 정렬은 `categoryTotal` 내림차순, 같으면 `latestDate` 내림차순이다. 카드 내용은 그 패턴의 가장 최근 실수에서 가져온다. `mastered[pattern]`의 날짜보다 최근 실수가 없으면 제외하므로, 외운 표현을 다시 틀리면 카드가 돌아온다.

- [ ] **Step 4: Run tests to verify they pass**

Run: `node macos/test_conversation_ui.cjs`
Expected: 오류 없이 종료

- [ ] **Step 5: Commit**

`/verify` 실행 후 커밋한다.

```bash
git add macos/web/conversation-core.js macos/test_conversation_ui.cjs ios/verify.py
git commit -m "feat(conversation): add shared review queue and trend logic"
```

### Task 5: 회화 리포트 페이지

**Files:**
- Create: `macos/web/conversation.html`, `macos/web/conversation.js`, `macos/web/conversation.css`
- Modify: `ios/verify.py` (`node --check macos/web/conversation.js`)

**Interfaces:**
- Consumes: Task 3 API, Task 4의 `ConversationCore`
- Produces: `conversation.html` 페이지. Task 6의 링크 대상이다.

- [ ] **Step 1: Build the page**

`library.html`의 헤더 구조와 `library.js`의 fetch 방식을 따른다. 구역 순서는 입력 → 추이 → 반복 실수 → 회차 리포트이다.

- 입력: `<textarea id="script-input">`, `<input type="date" id="session-date">`(기본값 Asia/Seoul 기준 오늘), `<button id="analyze">분석하기</button>`, `role="status"` 진행 표시. 작업은 `/api/jobs/<id>`를 1.5초마다 조회한다.
- 추이: `metricTrend`의 지표마다 인라인 SVG 꺾은선과 최신값, 직전 대비 변화, "개선/악화/동일"을 표시한다. `baseline`이면 "첫 기록: 기준선"을 표시한다.
- 반복 실수: 유형별·표현별 순위에 총 횟수, 등장 회차 수, 최근 회차 횟수를 표시한다.
- 회차 리포트: `<select>`로 회차를 고른다. 실수마다 `highlightParts` 결과를 `<mark class="mistake">`로 만들고, 개선 문장·한글 해석·유형·규칙을 그 아래에 둔다.
- 단어 정리: `단어 | 뜻 | 예문` 표. 예문은 `highlightParts(example, target)`으로 만들고 `<em class="vocab-target">`을 쓴다.
- 확인 필요 구역: `reviewFlags`를 "발음 확인 필요"와 "받아쓰기 확인 필요"로 나눈다.
- 삭제: `<dialog>`로 확인한 뒤 호출한다. 브라우저 `confirm()`은 쓰지 않는다.
- `skipped`가 1 이상이면 "읽지 못한 기록 n개"를 표시한다.
- `.mistake`는 연한 빨강 배경(`#FFD9D9`)이고 글자색은 유지한다.
- 동적 문자열은 모두 `textContent`로 넣는다.

- [ ] **Step 2: Check syntax**

Run: `node --check macos/web/conversation.js && node macos/test_conversation_ui.cjs`
Expected: 오류 없음

- [ ] **Step 3: Commit**

`/verify` 실행 후 커밋한다.

```bash
git add macos/web/conversation.html macos/web/conversation.js macos/web/conversation.css ios/verify.py
git commit -m "feat(conversation): add report page with highlights and vocabulary"
```

### Task 6: 대시보드 개편과 자주 틀리는 표현 복습

**Files:**
- Create: `macos/web/mistake-review.js`, `macos/web/mistake-review.css`
- Modify: `macos/web/index.html`, `macos/web/app.js`, `macos/web/style.css`
- Modify: `ios/verify.py` (`node --check macos/web/mistake-review.js`, `node --check macos/web/app.js`)
- Test: `macos/test_conversation_ui.cjs`

**Interfaces:**
- Consumes: `GET /api/conversations`, `ConversationCore.reviewQueue`
- Produces: `localStorage['english-mistake-mastered-v1']`: `{pattern: 'YYYY-MM-DD'}`

- [ ] **Step 1: Write the failing test**

`index.html`을 문자열로 읽어 구조를 고정한다.

```js
const html=fs.readFileSync('macos/web/index.html','utf8');
for(const removed of ['class="stats"','class="calendar"','class="roadmap"','id="week"','id="topic"','id="daily-note"'])
  assert.equal(html.includes(removed),false,removed);
for(const required of ['id="mistake-review"','id="today-strip"','href="conversation.html"','id="settings-open"','id="today-review"','conversation-core.js','mistake-review.js'])
  assert.equal(html.includes(required),true,required);
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node macos/test_conversation_ui.cjs`
Expected: FAIL, `class="stats"`

- [ ] **Step 3: Change `index.html`**

스펙의 제거 목록을 적용한다. `#topic-dialog`도 함께 지운다. 왼쪽 패널은 `class="panel today-panel"`을 유지해 좁은 화면 탭 CSS가 동작하게 하고, `id`는 `mistake-review`로 바꾼다. `.roadmap` 자리에 `<section id="today-strip" aria-label="오늘 할 일">`을 둔다. 좁은 화면 탭 문구는 "자주 틀리는 표현"으로 바꾼다.

- [ ] **Step 4: Change `app.js`**

- 지운다: `weekSelect` 초기화와 핸들러, `.days` 렌더링, `updateMetrics`, `[data-phase]`, `#edit-topic`, `#topic-save`, `#topic-input`, `#daily-note` 처리.
- `selected`는 항상 실제 오늘 요일이다: `(new Date(nowISO+'T00:00:00Z').getUTCDay()+6)%7`. 주차 계산은 기존처럼 1~8로 고정한다.
- `render()`는 날짜 표시와 `#today-strip`만 그린다. 각 항목은 체크박스·제목·시간이며, 체크 키는 `${state.week}-${selected}-${j}`를 유지한다.
- `state.notes`, `state.topics`는 읽기와 저장 형식을 그대로 두어 기존 값을 보존한다.
- 계획 설정 저장 후 `selectCurrent()`와 `render()`를 호출하는 흐름을 유지한다.

- [ ] **Step 5: Implement `macos/web/mistake-review.js` and CSS**

- 위쪽에 `frequency.categories`의 상위 3개 유형과 횟수를 표시한다.
- 카드 앞면은 `translation`과 "영어로 말해보세요" 안내, **답 확인** 버튼이다.
- 답 확인 후 `sentence`(빨간 형광펜), `corrected`, `rule`, 유형과 `patternTotal`회를 표시한다.
- 버튼은 **외웠어요**와 **다음 →** 이다. 외웠어요는 `mastered[pattern]=latestDate`를 저장한다.
- 기록이 없으면 "아직 분석한 회화가 없습니다"와 회화 리포트 링크를, 카드를 모두 외웠으면 완료 문구를 표시한다.
- 불러오기 실패 시 오류 문구와 다시 시도 버튼을 표시한다.
- 키보드 단축키는 오른쪽 복습과 충돌하지 않도록 패널에 포커스가 있을 때만 Space·오른쪽 화살표를 처리한다.

- [ ] **Step 6: Fix layout in `style.css`**

`body`가 `overflow:hidden`이므로 `.stats`, `.calendar`, `.roadmap` 기준의 그리드 행을 새 구조에 맞게 고친다. 하단 띠는 한 줄 높이로 두고, 왼쪽 패널과 오른쪽 패널이 남은 높이를 채운다.

- [ ] **Step 7: Run tests to verify they pass**

Run: `python3 ios/verify.py`
Expected: 모든 항목 통과. iOS SDK가 없으면 그 사실이 표시된다.

- [ ] **Step 8: Commit**

`/verify` 실행 후 커밋한다.

```bash
git add macos/web/index.html macos/web/app.js macos/web/style.css macos/web/mistake-review.js macos/web/mistake-review.css macos/test_conversation_ui.cjs ios/verify.py
git commit -m "feat(dashboard): put frequent mistake review first and simplify layout"
```

### Task 7: 문서 갱신과 실제 앱 확인

**Files:**
- Modify: `macos/README.md`, `README.md`

- [ ] **Step 1: Update docs**

`macos/README.md`의 사용·로컬 저장 구역에 회화 리포트, 저장 경로, Codex로 보내는 범위, 달라진 대시보드를 적는다. `README.md`의 Mac 소개 줄에 회화 리포트를 추가한다.

- [ ] **Step 2: Build the app**

Run: `python3 macos/build.py`
Expected: 앱 경로 출력

- [ ] **Step 3: Check the real app with today's script**

앱을 열고 오늘 스크립트를 2026-11-03 회차로 분석한다. 대시보드 왼쪽 복습, 하단 오늘 할 일, 리포트의 형광펜·단어 표·추이·반복 실수를 화면으로 확인한다. 스크립트 파일은 세션 임시 폴더에만 두고 저장소에 넣지 않는다.

- [ ] **Step 4: Run all checks**

Run: `python3 ios/verify.py && git status --short`
Expected: 검사 통과, 회화 기록이나 스크립트 파일이 변경 목록에 없음

- [ ] **Step 5: Commit and push**

```bash
git add macos/README.md README.md
git commit -m "docs(conversation): describe report and new dashboard"
git push origin main
```
