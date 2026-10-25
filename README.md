# Video Game Filter

<p align="center"><img src="build/icons/icon.png" width="200" height="200" alt="Video Game Filter icon"></p>

[English](#english) · [한국어](#한국어)

## English

### Introduction

Video Game Filter displays video and audio from a capture card and adds adjustable CRT and scanline effects for retro gaming.

### Native macOS 0.3.0

A lightweight SwiftUI/Metal viewer with CRT effects, independent horizontal/vertical scanline controls, bloom strength and radius, whole-video smoothing, resolution selection, audio playback, full screen and saved effect presets. Hada Sans is bundled.

New installations start with **CRT Default** (displayed as **CRT · 기본** in the app). Existing settings and user presets are preserved.

- Requires macOS 14 or later and Apple Silicon (arm64).
- Developer ID-signed and Apple-notarized.
- Capture resolution and frame rate depend on the device. HD60 X supports 4K30 capture, not 4K60 capture.
- Controller emulation, recording and streaming are not included.
- [Build instructions and effect details](macOS/README.md)

### Download and use

[Download the latest release](https://github.com/hada0127/videogamefilter/releases/latest).

1. Extract the ZIP and move `Video Game Filter.app` to Applications.
2. Launch the app and allow camera and microphone access when prompted.
3. Select your video device, audio device and capture resolution.
4. Choose a preset or adjust the effects. Click the video to show or hide settings.

### Legacy version

The original Electron version for macOS Apple Silicon and Windows x64/x86 is available in [v0.2](https://github.com/hada0127/videogamefilter/releases/tag/v0.2). The native macOS release does not include an Intel Mac binary.

### Contact and license

Use [GitHub Issues](https://github.com/hada0127/videogamefilter/issues) for bug reports and feature requests. The application is [MIT-licensed](LICENSE.md); bundled fonts and shader references include their own license notices.

## 한국어

### 소개

Video Game Filter는 캡처 카드의 영상과 오디오를 표시하고, 레트로 게임을 위한 CRT·스캔라인 효과를 조절할 수 있는 앱입니다.

### macOS 네이티브 0.3.0

SwiftUI와 Metal로 만든 가벼운 뷰어입니다. CRT 효과, 가로·세로 스캔라인 개별 조절, 빛 번짐 강도·반경, 영상 전체 부드러움, 해상도 선택, 오디오 재생, 전체 화면, 사용자 프리셋을 지원하며 Hada Sans를 내장했습니다.

새로 설치하면 **CRT · 기본** 프리셋으로 시작합니다. 기존 설정과 사용자 프리셋은 유지됩니다.

- macOS 14 이상, Apple Silicon(arm64)이 필요합니다.
- Developer ID 서명과 Apple 공증을 완료했습니다.
- 캡처 해상도와 프레임률은 장치에 따라 다릅니다. HD60 X는 4K30 캡처까지 지원하며 4K60 캡처는 지원하지 않습니다.
- 컨트롤러 에뮬레이션·녹화·스트리밍은 포함하지 않습니다.
- [빌드 방법과 효과 설명 — 영문](macOS/README.md)

### 다운로드 및 사용

[최신 릴리즈 다운로드](https://github.com/hada0127/videogamefilter/releases/latest)

1. ZIP을 풀어 `Video Game Filter.app`을 응용 프로그램 폴더로 옮깁니다.
2. 앱을 실행하고 요청 시 카메라·마이크 접근을 허용합니다.
3. 영상 장치, 오디오 장치, 캡처 해상도를 선택합니다.
4. 프리셋을 선택하거나 효과를 조절합니다. 영상을 클릭하면 설정을 표시하거나 숨길 수 있습니다.

### 이전 버전

macOS Apple Silicon과 Windows x64/x86용 기존 Electron 버전은 [v0.2](https://github.com/hada0127/videogamefilter/releases/tag/v0.2)에서 받을 수 있습니다. macOS 네이티브 릴리즈에는 Intel Mac용 바이너리가 없습니다.

### 문의 및 라이선스

버그 제보와 기능 요청은 [GitHub Issues](https://github.com/hada0127/videogamefilter/issues)를 이용해 주세요. 앱은 [MIT 라이선스](LICENSE.md)이며, 내장 폰트와 셰이더 참고 자료에는 각각의 라이선스 고지를 포함했습니다.
