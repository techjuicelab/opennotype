# 자연스러운 번역 받아쓰기 UI 검증 · 0.2.1 (29)

설정 › 입력·단축키에 **받아쓰기 출력 언어**를 추가했다. 평소 받아쓰기 단축키를 유지하면서 말한 언어 유지, 영어, 일본어, 한국어 중 하나를 사용할 수 있다. 기존 별도 번역 단축키와 그 출력 언어는 따로 유지한다.

**언어 선택·예시 보기…**는 고정 합성 한국어 발화와 각 언어의 입력 예시를 보여 준다. 선택 언어는 시트의 로컬 상태에만 저장되며 **적용**을 눌러야 설정이 바뀐다. 닫기, 취소, Escape는 적용하지 않는다. 예시가 실제 모델 평가 결과가 아님을 표시하고, 예시를 여는 동안 AI 호출·녹음·전송을 하지 않는다.

번역 중에는 받아쓰기 표현 설정을 비활성화하고, 말한 언어 유지로 돌아오면 기존 설정을 다시 사용하는 점을 안내한다. 홈의 출력 언어와 표현·Jev 요약, 기록과 복구의 번역 표시도 실제 처리 방식에 맞춘다. 번역 받아쓰기 기록의 Jev 검토 동의문은 원문·번역문·당시 목표 언어를 설명한다.

## 빌드와 실제 UI 확인

- `CONFIGURATION=debug ./scripts/build-app.sh`로 당시 코드의 전체 앱 빌드와 strict 코드 서명 검증을 통과했다. 선택된 SDK는 `MacOSX26.5.sdk`, 빌드 완료 시간은 8.28초였다. 로그: `build/native-translation/ui-app-build.log`.
- 별도 Debug 미리보기 bundle `app.opennotype.usage-preview`로 실행했다. `AppLaunch`의 합성 runtime은 API 네트워크, 녹음, 자동 입력, 암호화 저장소 접근을 차단하며 `startServices: false`로 설정 저장도 하지 않는다. 설치된 production 앱과 설정은 바꾸지 않았다.
- 한국어 UI에서 일본어 예시를 고른 뒤 Escape를 눌렀다. 시트가 닫혔고 현재 출력 언어는 **말한 언어 유지**였다. 증거: `build/native-translation/ui-escape-state.txt`.
- 시트를 다시 열어 일본어를 **적용**했다. 출력 언어가 **일본어**로 바뀌고 적용 완료 안내가 표시됐으며, 받아쓰기 표현 선택과 예시 버튼은 비활성화됐다. 별도 번역 단축키의 언어는 **영어 · 미국식**을 유지했다. 증거: `build/native-translation/ui-japanese-applied-state.txt`.
- **말한 언어 유지**를 다시 적용했다. 표현 선택과 예시 버튼이 다시 활성화되고 기존 **현재 받아쓰기 · 강도 0** 설정을 유지했다. 증거: `build/native-translation/ui-restored-state.txt`.
- 인터페이스를 English로 바꿔도 출력 언어는 **Keep spoken language**를 유지했다. 시트의 제목·선택지·버튼은 영어로 표시하고, 비교 원문은 같은 한국어 발화를 유지했다. 영어 예시를 고른 뒤 **Cancel**을 눌렀을 때 출력 언어는 그대로였다. 증거: `build/native-translation/ui-cancel-state.txt`.
- 한국어·영어 시트에서 선택 언어, 현재 설정 표시, 원문/결과 제목, Apply/Cancel/Close가 접근성 트리에 노출됐다. 본문은 스크롤 영역에 두고 언어 선택과 적용 버튼은 고정해 두어 긴 예시에서도 조작할 수 있다. 스크린샷에서 예문과 하단 버튼의 잘림을 발견하지 않았다.
- 검증 후 미리보기 앱을 종료했다. 앱 inventory에서 `app.opennotype.usage-preview`는 실행 중이 아니었고 설치본 `app.opennotype.mac`은 기존대로 실행 중이었다.

## 스크린샷

스크린샷은 로컬 검증 산출물로 `build/native-translation/`에 보관한다.

![한국어 UI의 일본어 미리보기](/Users/techjuice/Documents/Dev/AI/opennotype/build/native-translation/ui-ko-japanese-preview.png)

![일본어 적용 안내와 표현 설정 일시 중지](/Users/techjuice/Documents/Dev/AI/opennotype/build/native-translation/ui-ko-applied-settings.png)

![영어 UI의 한국어 원문과 영어 결과 비교](/Users/techjuice/Documents/Dev/AI/opennotype/build/native-translation/ui-en-english-preview.png)

이 문서는 설정과 고정 예시의 UI 동작을 검증한다. 실제 음성 인식 및 모델 번역 품질은 별도 파이프라인·실제 API 검증 결과로 판단해야 한다.
