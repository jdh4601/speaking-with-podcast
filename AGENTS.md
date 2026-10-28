# 프로젝트 작업 지침

- 근거가 없다면 모른다고 답한다. 확인하지 않은 빌드·실기기 동작을 검증했다고 표현하지 않는다.
- 개발 중 의미 있는 기능 단위로 나눠 커밋하고, 해당 변경의 검증 후 `origin`에 푸시한다.
- 원격 저장소: https://github.com/jdh4601/speaking-with-podcast.git
- 개인 학습 꾸러미·음성·복습 기록·계정 자격증명·빌드 산출물은 커밋하지 않는다.
- 통합 검사: `python3 ios/verify.py`. 전체 Xcode가 있으면 `python3 ios/verify.py --require-ios`로 iOS 빌드도 확인한다.
