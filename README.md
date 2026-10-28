# Podcast Study

내가 듣는 팟캐스트에서 영어 표현과 실제 발화를 골라, 아이폰에서 듣고 말하며 복습하는 개인용 앱입니다.

**Mac에서 준비 → `.podstudy` 파일로 전달 → iPhone에서 오프라인 학습**을 기본으로 합니다.

- Mac: 자막·전사 확인, 회화 표현 추출, 원문 문장 음성 정렬, 학습 꾸러미 내보내기
- iPhone: 좌우 카드 학습, 발견·듣기·말하기, 원음 반복·배속, 북마크와 복습 일정, 복습 기록 파일 백업
- 복습 기록은 표현 저장 여부와 별도로 관리합니다. 카드를 넘기는 것만으로 외웠다고 기록하지 않습니다.

## 시작

[아이폰 앱 설치·사용·파일 형식](ios/README.md) · [Mac 앱 실행·원본 자료 처리](macos/README.md)

```sh
# Mac 앱 빌드: ~/Applications/English Routine.app
python3 macos/build.py

# 로컬 테스트·프로젝트 검사·Swift 핵심 로직·공유 화면 타입 검사
python3 ios/verify.py

# 전체 Xcode/iOS Simulator SDK가 있을 때 iOS 빌드를 필수로 검사
python3 ios/verify.py --require-ios
```

아이폰 프로젝트는 `ios/PodcastStudy.xcodeproj`입니다. 기기 설치에는 전체 Xcode와 본인 계정의 서명이 필요합니다. 현재 환경에 iOS SDK가 없을 때는 검사 결과에 이를 명시하며, 소스 검사를 iOS 실행 검증으로 표시하지 않습니다.

`dist/`는 이전 웹 대시보드입니다. 현재 팟캐스트 학습 기능은 `macos/`와 `ios/`에서 개발합니다.
