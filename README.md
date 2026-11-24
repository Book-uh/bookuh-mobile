# 북어 iOS

북어는 책을 찾고 독서 진도를 남기며, 읽은 장면을 바탕으로 책 속 인물과 대화할 수 있는 iPhone 앱이다.

## 주요 기능

- **내 책장** — 제목·저자·ISBN으로 책을 검색하고 책장에 담거나 뺀다. 같은 판본을 다시 담으면 이전 독서 기록과 대화를 이어서 볼 수 있다.
- **독서 기록** — 읽은 장면과 독서 시간을 남기고, 주간·월간 통계에서 읽은 시간을 확인한다.
- **북어 비서** — 대화로 독서 진도와 시간을 기록하고, 책 검색이나 추천을 요청한다.
- **책 속 인물** — 읽은 장면을 저장하면 인물에게 편지를 보낼 수 있다. 인물별로 필요한 답장을 받으면 채팅이 열린다.

## 실행

1. Xcode에서 `Bookuh.xcodeproj`를 연다.
2. `Bookuh` 스킴과 iPhone 시뮬레이터를 선택한 뒤 실행한다. 프로젝트의 최소 배포 대상은 iOS 17이다.
3. 첫 화면에서 **시작하기**를 누르면 계정이 발급되고 책장이 열린다. 실기기에서 실행할 때는 **Signing & Capabilities**에서 본인의 Team을 선택한다.

앱은 배포된 북어 API에 HTTPS로 연결한다. 별도 서버를 사용하려면 [BookuhAPI.swift](Bookuh/BookuhAPI.swift)의 `APIConfiguration.baseURL`을 변경한다. 서버 실행 설정은 [북어 백엔드 저장소](https://github.com/Book-uh/bookuh-backend)를 참고한다.

## 구성

- [BookuhAPI.swift](Bookuh/BookuhAPI.swift)와 [BookSearchAPI.swift](Bookuh/BookSearchAPI.swift)에서 서버 요청을 처리한다.
- [AppSession.swift](Bookuh/AppSession.swift)에서 발급받은 사용자 토큰을 Keychain에 저장한다.
- [DesignSystem](Bookuh/DesignSystem)과 [Components](Bookuh/Components)에 공통 스타일과 재사용 화면 요소를 둔다.

## CLI 빌드

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Bookuh.xcodeproj -scheme Bookuh \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/bookuh-ios-build \
  CODE_SIGNING_ALLOWED=NO build
```
