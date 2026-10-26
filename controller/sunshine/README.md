# Local Sunshine input backend

Development integration, pinned to upstream Sunshine v2025.628.4510. This source
baseline has macOS video/audio capture but no gamepad backend; our MIT header provides
local forwarding, with per-client liveness handling added by `patch.py`. It is not a
replacement for the upstream macOS virtual HID driver and does not require a license
for that driver. Sunshine itself remains GPL-3.0. If distributing a modified Sunshine
binary, provide its corresponding source, patches, license and dependency notices.
The current helper is a local development build, not a published release.

Prerequisites: Xcode, Homebrew CMake/Ninja/pkgconf/miniupnpc/opus/openssl@3, Node/npm.
Boost 1.87 is fetched by Sunshine's pinned CMake configuration. Do not add the generic
Homebrew include directory to C++ flags: newer Boost headers can conflict with 1.87.

```sh
brew install cmake ninja pkgconf miniupnpc opus openssl@3
# Choose a new checkout directory.
git clone --depth 1 --branch v2025.628.4510 https://github.com/LizardByte/Sunshine.git /path/to/Sunshine
git -C /path/to/Sunshine submodule update --init --recursive --depth 1 third-party/build-deps third-party/moonlight-common-c third-party/libdisplaydevice third-party/Simple-Web-Server third-party/TPCircularBuffer third-party/tray third-party/nanors third-party/nv-codec-headers
python3 controller/sunshine/patch.py /path/to/Sunshine
bash controller/sunshine/build.sh /path/to/Sunshine "$HOME/Applications/VGF Sunshine.app"
```

Stop a running helper before rebuilding using the shutdown sequence below. Set `CODE_SIGN_IDENTITY` to your Developer ID
identity if it differs from the main app build script. This builds and signs locally;
it does not publish, change login items, or alter your existing Sunshine installation.

Build with `BUILD_DOCS=OFF`, `BUILD_TESTS=OFF`, `SUNSHINE_ENABLE_TRAY=OFF`,
`CMAKE_POLICY_VERSION_MINIMUM=3.5`, and `CMAKE_BUILD_TYPE=Release`. Point
`OPENSSL_INCLUDE_DIR`, `OPENSSL_SSL_LIBRARY`, and `OPENSSL_CRYPTO_LIBRARY` explicitly at
Homebrew's openssl@3. Add only that include directory and the opus include directory
to `CMAKE_CXX_FLAGS`. Set `CMAKE_INSTALL_PREFIX` to the helper app's
`Contents/Resources`; Sunshine reads its `assets` there. Use
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for configure/build.
Bundle the built executable, generated `build/assets`, and its non-system dylibs;
rewrite dylib references to `@executable_path/../Frameworks`, then sign libraries and
bundle with the same identity and the audio-input entitlement in `Entitlements.plist`. Screen-recording and microphone permission are needed.
For Switch audio, select the capture card's audio input (e.g. `Game Capture HD60 X`).

Recommended Sunshine configuration:

```ini
sunshine_name = switch-remote
origin_web_ui_allowed = pc
upnp = disabled
encoder = videotoolbox
vt_realtime = enabled
hevc_mode = 1
audio_sink = Game Capture HD60 X
lan_encryption_mode = 2
wan_encryption_mode = 2
```

For this pinned helper, start with H.264, 60 FPS, and Moonlight's lowest-latency
frame pacing. Its bundled FFmpeg enables VideoToolbox's low-latency rate-control
mode for H.264 only, so the configuration above does not advertise HEVC. This is
a starting point for latency testing, not an end-to-end latency guarantee.

Store the config, pairing certificate/key and state under a private user directory.
Use a strong local Web UI password. Launch the signed app through LaunchServices so
macOS attributes screen-recording permission to the app:

```sh
open -W -a "$HOME/Applications/VGF Sunshine.app" --args /absolute/path/to/sunshine.conf
```

For a per-user LaunchAgent, use the same `/usr/bin/open -W -a ... --args ...`
argument list. Running the inner `Contents/MacOS/sunshine` executable directly from
launchd can report missing capture permission even when the app is allowed in Settings.
Before rebuilding or changing configuration, unload the LaunchAgent first, then quit
the app separately: LaunchServices owns the app process, so stopping the agent alone
does not stop Sunshine. Likewise, `kickstart -k` only restarts `open` and does not reload
the running app's configuration.

```sh
launchctl bootout "gui/$(id -u)/net.tarucy.videogamefilter.sunshine"
osascript -e 'quit app id "net.tarucy.videogamefilter.sunshine"'
# Confirm Sunshine has exited before rebuilding or replacing the bundle.
# After the rebuild or configuration edit:
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/net.tarucy.videogamefilter.sunshine.plist"
```

If no LaunchAgent is installed, only quit the app. Start with the config-bearing
command above rather than double-clicking the bundle, which starts with default
configuration. Use Sunshine's configured `log_path` for server diagnostics; the
LaunchAgent's standard-output files now contain only `open` diagnostics.
Pair the client through the local Web UI, then use Tailscale rather than public port
forwarding. The app input source **Moonlight · Sunshine** must be selected, and the Pi
must be connected. Only the lowest numbered active remote pad is used.
