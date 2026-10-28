# Podcast Study

내가 듣는 팟캐스트에서 영어 표현과 실제 발화를 골라, 아이폰에서 듣고 말하며 복습하는 개인용 앱입니다.

**Mac에서 준비 → `.podstudy` 파일로 전달 → iPhone에서 오프라인 학습**을 기본으로 합니다.

- Mac: 자막·전사 확인, 회화 표현 추출, 원문 문장 음성 정렬, 학습 꾸러미 내보내기
- iPhone: 원음 자동 재생, 오른쪽 스와이프로 저장·왼쪽으로 넘기는 카드 복습, 복습 일정과 기록 파일 백업
- 확정된 스와이프는 한 번의 복습으로 기록하며, 저장하거나 넘겼다고 암기 성공으로 기록하지 않습니다.

## 시작

[아이폰 앱 설치·사용·파일 형식](ios/README.md) · [Mac 앱 실행·원본 자료 처리](macos/README.md) · [디자인 가이드](DESIGN.md)

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
