# OpenNoType 아이콘

2026-09-09에 선택한 **02번 보이스 키**를 사용합니다. 산호색 바탕, 아이보리 키캡, 주황색 음성 심볼로 구성됩니다.

## 원본과 적용 경로

- `AppIcon-master.png`는 승인된 1254 × 1254 PNG를 알파 채널과 함께 그대로 복사한 원본입니다.
- `scripts/generate-app-icon.sh`는 16~1024px의 표준 macOS 아이콘 이미지 10개를 생성해 `Sources/OpenNoType/Resources/AppIcon.icns`에 묶습니다.
- `scripts/build-app.sh`는 서명 전에 ICNS를 앱의 `Contents/Resources`로 복사합니다. `CFBundleIconFile`을 통해 Finder·Dock·기본 앱 정보 창 등 앱 식별 화면에서 사용합니다.
- SwiftPM에도 같은 ICNS를 포함합니다. `AppBrand.icon`은 앱 번들의 리소스를 우선 사용하므로 배포 환경에서 소스 폴더에 의존하지 않습니다.
- 사이드바는 같은 ICNS를 사용합니다. `AppBrand`는 키캡 안쪽의 음성 심볼을 메뉴바용 단색 벡터 템플릿으로 그리며, 녹음 중에는 점과 접근성 이름으로 상태를 구별합니다.
- 기존 ZIP·DMG 배포 과정도 아이콘이 포함된 앱을 포장합니다. 디스크 이미지의 볼륨 아이콘은 별도입니다.
- 최초 6종 시안은 `design/icon-concepts/2026-09-09/`에 보존합니다. 빌드는 이 폴더를 참조하지 않습니다.

승인된 원본을 바꾼 뒤 저장소 루트에서 다시 생성합니다.

```sh
./scripts/generate-app-icon.sh
./scripts/build-app.sh
```

## 적용 검증 — 2026-09-09

- 기준 커밋: `f0f84d2`.
- 승인 시안과 마스터의 SHA-256 일치: `c728236fb609d75615f24d2e5476bda3100bd6171286207637d751c9a4bccc8f`.
- ICNS를 다시 풀어 10개 이미지의 크기와 알파 채널을 확인했습니다.
- 기존 `TechJuice Local Code Signing` 서명으로 앱 빌드 및 `codesign --verify --deep --strict` 검증을 통과했습니다.
- `swift test --arch arm64`: 140개 실행, 1개 건너뜀, 실패 0개.
- 앱을 재실행하고 사이드바 및 기본 앱 정보 창에서 02번 아이콘을 시각 확인했습니다.
- 별도 검증 번들에서 SwiftPM fallback을 호출하면 실패하도록 만든 뒤 실제 `AppBrand.icon` 로딩이 성공하는지 확인했습니다.
- 메뉴바 대기·녹음 이미지를 실제 구현에서 렌더링해 22 × 18pt 크기, template 속성, 접근성 이름을 확인했습니다. 녹음 상태 검증은 실제 녹음이나 API 호출 없이 수행했습니다.
