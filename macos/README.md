# English Routine for macOS

설치 위치: `~/Applications/English Routine.app`

## 사용

- Dock의 말풍선·파형 아이콘으로 실행합니다.
- 대시보드의 **팟캐스트 학습**에서 제목을 검색하거나 YouTube 영상 링크 또는 Latent Space·Dwarkesh의 공개 전사 링크를 입력합니다.
- 검색 결과에서 실제 들은 영상을 선택하고 전사를 확인합니다. 영상 설명의 지원 발행사 링크가 있으면 공개 전사를 먼저 시도합니다. YouTube가 요청을 제한하면 전사 링크나 직접 붙여넣기를 사용합니다. 공개 영어 자막이 없는 경우 전사를 직접 붙여넣습니다.
- **표현 10개 추출**은 로그인된 Codex CLI를 실행합니다. 계정 사용량을 소비하며 인터넷 연결이 필요합니다.
- 뜻을 보고 영어로 말한 뒤 답을 확인하고 **다시 연습 / 기억남**으로 복습합니다.
- 원문 인용은 전사와 대조합니다. 새로 만든 연습 예문과 합성 음성은 원본 발화가 아닙니다.
- 자동 생성 자막은 잘못 인식될 수 있으므로 원음과 확인해야 합니다.

## 로컬 저장

- 에피소드·전사·추출 표현: `~/Library/Application Support/English Routine/*.json`
- 체크·메모·복습 상태: 앱의 WebKit 저장소
- 기존 웹사이트 브라우저 기록과 앱 기록은 별도입니다.
- 공개 웹페이지에는 로컬 Codex CLI 연결을 배포하지 않습니다.

## 실행 구조

AppKit + WKWebView 창에서 번들된 대시보드를 엽니다. 앱은 `127.0.0.1:47831`에 로컬 Python 서버를 실행하며 종료할 때 서버와 실행 중인 하위 프로세스를 정리합니다. 로컬 API는 실행별 토큰과 Host/Origin 검사로 제한합니다.

전사 안의 지시문은 데이터로 처리합니다. Codex는 임시 작업 폴더, read-only sandbox, ephemeral 모드로 실행하며 사용자 설정·앱·플러그인·셸·브라우저·다중 에이전트 도구를 비활성화합니다. 결과의 표현·원문·중복을 검증한 뒤 저장합니다.

필요 도구: 현재 Mac에 설치된 Python 3, yt-dlp, Codex CLI. 설치·로그인 경로가 바뀌면 `server.py`와 `App.m`의 경로를 조정합니다.

## 빌드 및 확인

```sh
python3 macos/build.py
python3 -m unittest discover -s macos -p test_server.py -v
node --check macos/web/podcast.js
open "$HOME/Applications/English Routine.app"
```

Xcode Command Line Tools의 SwiftBridging 모듈 중복 문제를 피하기 위해 네이티브 실행 파일과 아이콘 렌더러는 Objective-C / AppKit으로 빌드합니다. 서명은 이 Mac용 ad-hoc 서명입니다.
