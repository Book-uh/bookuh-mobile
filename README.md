# 북어 iOS

SwiftUI · iOS 17 이상 기본 프로젝트.

`Bookuh.xcodeproj`를 열고 `Bookuh` 스킴과 iPhone 시뮬레이터를 선택해 실행한다. 개인 아이폰에서 실행할 때는 Signing & Capabilities에서 본인의 Team을 선택한다.

## CLI 빌드

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Bookuh.xcodeproj -scheme Bookuh \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/bookuh-empty-ios-build \
  CODE_SIGNING_ALLOWED=NO build
```
