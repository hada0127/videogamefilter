# Native macOS viewer

SwiftUI + AVFoundation viewer for external capture cards. macOS 14+, Xcode required. No external Swift packages. The original Electron app remains unchanged.

```sh
bash macOS/build.sh
open 'macOS/build/Video Game Filter.app'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test -c release --package-path macOS
```

The build defaults to the owner's existing `Developer ID Application: eunkyu lee (WBL49792F2)` identity. Other developers can set `CODE_SIGN_IDENTITY` to their own signing identity. There is no automatic ad-hoc fallback: stable bundle ID, team and certificate class preserve macOS's designated requirement across updates. Switching from an earlier ad-hoc build can require one more permission grant. The key is used in Keychain, never exported. Builds use hardened runtime and a secure timestamp. `bash macOS/release.sh` submits an archive through the configured Xcode developer account and exports a stapled, notarized release. It requires access to the matching Developer ID account.

## Controls

The original app's black video canvas and floating white panel are retained. Click the video or press Command-comma to hide/show settings. Select Video, Audio and Resolution directly; a running capture restarts with the new selection. Start/stop: Command-Return. Mute: Shift-Command-M. Full screen: Control-Command-F or the window's green button. Closing the window quits the app and releases capture/audio. Volume and start/stop also remain in the Capture menu. The viewer starts automatically when an input is available at launch.

Hada Sans Regular/SemiBold are bundled and loaded directly from their font files; no font installation is needed. Their OFL license and copyright notices are included.

## Effects and presets

Horizontal and vertical scanlines have independent 0–50% strength, including the original 5% values and finer adjustments. Horizontal and vertical lines each have independent thickness and gap controls (1–16 display pixels each, default 2). Gap means clear space between dark lines. On scaled Retina displays, native-mode dimensions map the drawable to final display pixels; pixel-area integration handles fractional coverage. If native dimensions are unavailable, the renderer falls back to drawable pixels. Both sizes remain fixed regardless of input resolution, window size, or full screen; only the number of visible lines changes. Older presets default missing thickness/gap fields to 2 pixels. Scanlines are composed in the same Metal pass as the video. The RGB mask uses smooth sinusoidal color modulation integrated over each output pixel. Each RGB triad spans three final panel pixels (enlarged in low-resolution display modes to stay below the drawable sampling limit), independently of line thickness/gap. Mask chroma is combined separately from varying scanline coverage to avoid multiplying the two grids and creating beat frequencies. This removes hard mask edges and their high-frequency harmonics; it reduces aliasing but cannot guarantee zero moire on all scaled displays or source content. Scanlines stay straight in output space even when the CRT image curves. This reduces aliasing; display scaling and the content itself can still affect the result.

CRT offers curvature, glow, vignette and RGB mask. Bloom extracts highlights in linear light before 2×2 downsampling, uses a half-resolution MPS Gaussian blur, then screen-blends the halo in linear light. Strength (0–50%) and radius (2–48 output display pixels, approximately 3 sigma at the image center) are independent. The radius defaults to 18 for older presets. Very small radii can look similar when the half-resolution blur is enlarged substantially. Zero strength or CRT off skips extraction and blur. Curvature can change the apparent radius toward image edges.

Video antialiasing (0–100%, default off for existing settings) blends the captured image with a Gaussian-filtered copy (sigma rises from 0.5 to 4 captured pixels with strength). Per the user’s preference this softens the entire video, including fine textures, rather than selecting only edges. The blur is applied before bloom, scanlines and RGB mask composition; it does not filter the generated CRT patterns. Zero strength skips this pass. AA can also be used with CRT off. Both AA strength and bloom radius are saved in user presets. The sharp enlargement filter adapts the CC0 Sharp-Shimmerless area-overlap coordinate calculation; it applies when enlarging captured frames without CRT curvature. Downscaling and curved CRT use linear interpolation. Switch HDMI capture is already scaled video, so this does not reconstruct the emulator's original pixel grid.

Built-in presets: Original, Horizontal 25%, Grid 27%, CRT Default, CRT Sharp. New installations use CRT Default (horizontal20%, vertical2%, all line widths/gaps4px, curvature0, bloom25%/10px, vignette46%, mask38%, AA41%, sharp on). Existing saved settings and presets are preserved. Save creates a new named user preset; Overwrite changes only the selected user preset; Delete confirms removal. Effect settings and user presets persist locally via UserDefaults. Older preset fields default safely on update. Presets store effects, not capture devices or resolution.

References: https://github.com/Woohyun-Kang/Sharp-Shimmerless-Shader (CC0, zadpos); https://gall.dcinside.com/mgallery/board/view/?id=retrogame&no=238959&page=3 . Read-only inspection of the owner's iPhone RetroArch saved presets found crtglow_gauss, lcd3x, lcd-grid-v2-gba-color-motionblur and sharp-bilinear-simple. CRT here is an original lightweight implementation inspired by those effects, not a full RetroArch multi-pass shader runtime. Imported .slangp/.glslp files are not supported.

## Capture behavior

Resolution/fps describe frames delivered by the capture device, not the HDMI signal. HD60 X supports 4K30 capture, not 4K60. A no-signal image generated by the card still counts as arriving frames. The preview preserves aspect ratio. Audio plays through the Mac's default output.

AVCaptureVideoPreviewLayer is used with effects off. Effects use Core Image's GPU color conversion and a final Metal pass (plus a source-resolution Gaussian pass while AA is enabled, and highlight extraction/Gaussian blur while bloom is enabled), with one in-flight frame and a latest-frame mailbox. GPU errors fall back to normal preview with an error message; changing effects or restarting capture retries rendering. Device removal stops capture; reconnect and use Start to resume. No recording, streaming or controller emulation is included yet.
