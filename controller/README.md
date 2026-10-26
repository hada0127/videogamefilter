# Raspberry Pi controller bridge

switch-remote discovers a Raspberry Pi Zero W on the local network and automatically connects to a Pi prepared by this Mac. No Pi display, PIN entry, SSH login or IP address is needed during normal use. Game input uses authenticated UDP without acknowledgments; TLS manages enrollment and connection lifetime.

## Prepare a new SD card

1. Write **Raspberry Pi OS Lite (32-bit, Bookworm/Trixie or newer)** with Raspberry Pi Imager. Set the hostname, user and **2.4 GHz Wi-Fi** credentials in Imager. Zero W does not support 5 GHz Wi-Fi.
2. Before putting the card in the Pi, open **컨트롤러 → 컨트롤러 설정… → 새 파이 SD 준비…** in switch-remote and select its mounted `bootfs` partition.
3. The app generates a device certificate and temporary PIN, and remembers registration securely on this Mac. It preserves Imager's network setup and adds the first-boot installer; this action does not format the card.
4. Safely eject the card, insert it into the Pi, and power it on. First boot installs Bluetooth and discovery dependencies from the internet and may take several minutes, including a reboot. Subsequent boots start the service automatically.
5. Allow the Mac app's Local Network permission. On the same LAN, the app discovers the Pi and uses its saved PIN once. A persistent credential replaces the PIN in Keychain after enrollment. Later connections and reconnects are automatic.

Open **Controllers → Change Grip/Order** on the Switch for its first pairing with the Pi. The physical gamepad pairs with the Mac; the Pi pairs with the Switch. Both may advertise as “Pro Controller”, so do not pair the Pi with the Mac in Bluetooth settings.

## Operation

The app sends changed button state immediately, limits analog updates to approximately 125 Hz, and sends a full-state heartbeat every 20 ms. Only the active app forwards physical input. Selecting no gamepad or switching apps sends neutral state. A Pi releases inputs after 350 ms without a valid datagram; after 10 seconds without input it closes that session. Closing the control connection also requests neutral state.

Bluetooth pairing reports are limited to 15 Hz until initialization completes. Afterwards idle reports use 15 ms intervals; changed input can advance the next report (4 ms minimum). USB uses an 8 ms heartbeat and a 1 ms minimum for changed input. A blocked Bluetooth HID output lasting 100 ms ends the session. USB waits for the host to resume polling, while keeping the existing stale-input and disconnect timeouts. On session cleanup, USB retries a blocked neutral report after up to two 20 ms waits; a host that remains unresponsive may not receive that release.

Each connection creates an ephemeral UDP port and random HMAC key, delivered over pinned TLS. Datagrams contain an increasing sequence number, full input state, and SHA-256 HMAC. Out-of-order, duplicate, unauthenticated and oversized datagrams are discarded. UDP packets are authenticated but not encrypted. No input acknowledgment or retransmission is required. Allow the app's local network access, TCP 24872 and UDP traffic to the Pi, and mDNS discovery on the LAN.

The initial certificate fingerprint is transferred during SD preparation, not trusted from an unauthenticated network advertisement. PINs and persistent client credentials are stored in macOS Keychain. The Pi keeps its credentials in a root-only directory. Registration permits one Mac, rate-limits incorrect PIN attempts, and invalidates the PIN after the Mac has saved its permanent key. An interrupted enrollment can resume without losing access. The current version does not transfer registration to another Mac automatically; prepare a new card or retain/import the provisioning receipt using the development tools.

By default the app preserves GameController A/B/X/Y identifiers, as verified with a Switch Pro profile. Enable **A/B · X/Y 맞바꾸기** if needed. HOME, L+R and Capture buttons are available in settings. **Switch 2 wake from sleep is not supported** by the emulated first-generation Pro Controller. Turn on the console before reconnecting. Rumble, motion and NFC are not implemented.

## Development / current-Pi migration

`prepare_sd.py DESTINATION --stage --receipt PRIVATE_RECEIPT.json` creates a migration payload and saves a private enrollment receipt before committing files. Install the staged payload with `sudo sh install.sh` on an existing Pi, and import the receipt on the Mac. This migration can use SSH once; the running app does not use SSH. Keep the receipt private. The app also consumes a pending receipt at `~/Library/Application Support/VideoGameFilter/pending-pi-enrollment.json`, stores its secrets in Keychain, and removes that temporary file after saving registration.

The service is `vgf-controller.service`, discovery is `_vgf-controller._tcp`, and runtime files live in `/opt/videogamefilter-controller` and `/var/lib/videogamefilter-controller`. `journalctl -u vgf-controller.service` diagnoses installation/service errors. The first-boot installer retries after network/package-manager failures. Reinstalling the same identity preserves its paired credential; explicitly preparing a new identity replaces the previous registration and restarts the service. Provisioning secrets are removed from the boot partition and installation staging directory after successful installation. The legacy SSH transport is retained for development tests, not the default UI.

On the Pi, run `make -C controller/native check` for native protocol/enrollment tests. For provisioning and compatibility tests, run `python3 -m unittest discover -s controller -p 'test_*.py'` and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path macOS`. NXBT attribution and lifecycle/performance changes are in `vendor/UPSTREAM.txt`.

## 한국어

파이에 HDMI를 연결하거나 앱에서 PIN·SSH 주소를 입력할 필요가 없습니다. Raspberry Pi Imager에서 **Bookworm/Trixie 이상 32비트 Lite OS와 2.4GHz Wi-Fi**를 설정해 SD를 구운 뒤, 앱의 **새 파이 SD 준비…**에서 `bootfs`를 선택하세요. 앱이 임시 PIN과 인증 정보를 만들고 맥에 기억합니다. SD를 파이에 넣고 켜면 최초 설치 후 네트워크에서 자동으로 찾아 등록하며, 이후에는 키체인에 저장된 연결 키로 자동 재연결합니다.

최초 설치에는 인터넷이 필요하고 몇 분 걸릴 수 있습니다. 맥에서 로컬 네트워크 접근 권한을 허용해주세요. 스위치와 처음 페어링할 때만 **컨트롤러 → 잡는 방법/순서 변경** 화면을 열면 됩니다. 버튼 입력은 UDP로 즉시 전달하며, 입력이 끊기면 자동으로 버튼을 놓습니다. 스위치 2 슬립 깨우기·진동·자이로는 지원하지 않습니다.

## Moonlight on iPhone (development)

The Mac app accepts Moonlight input through a small, locally built Sunshine backend.
This bypasses the need for an OS virtual gamepad: it forwards authenticated Sunshine
controller events to this user's private Unix socket. It does not expose another LAN
input port. It supports buttons and both sticks; rumble/motion are not forwarded.

Build the pinned upstream Sunshine `v2025.628.4510` (`65f14e1003f831e776c170621bd06d8292f65155`),
then apply `python3 controller/sunshine/patch.py /path/to/Sunshine` before compiling.
Use the helper build instructions in [sunshine/README.md](sunshine/README.md).
Run Sunshine as the **same logged-in user** as switch-remote, never as root/a
LaunchDaemon. The backend sends changes immediately and refreshes held input every
100 ms. Each client's authenticated 100 ms periodic ping renews only its own pads;
a missing ping for 350 ms clears held buttons/sticks on the next 100 ms tick. A
stopped Sunshine process is also covered by the app's 350 ms stale-input timeout.

In switch-remote → Controller Settings, select **Moonlight · Sunshine**. This
explicit selection enables background input; local physical pads still require the
app to be active. The lowest numbered active remote pad controls the Switch. The swap option
uses the same A/B and X/Y mapping as local GameController input. Stop remote input by
selecting **No input** or a local controller.

Pair the iPhone's Moonlight with this Sunshine host using its displayed PIN. For
outside access, connect both devices to the same Tailscale network and add the Mac's
Tailscale address manually in Moonlight. Leave router port forwarding and Sunshine
UPnP off. Keep the Mac/app/Pi running and the Switch awake: Switch 2 wake is unsupported.
A working Tailscale address on home Wi-Fi alone does not prove cellular performance;
verify streaming and controls on cellular separately.

### 문라이트 원격 조작

선샤인 `v2025.628.4510` 소스에 `controller/sunshine/patch.py`를 적용해 빌드합니다.
앱과 **같은 로그인 사용자**로 실행해야 합니다. 별도 가상 패드 드라이버 없이
선샤인의 입력을 이 맥 사용자 전용 소켓으로 앱에 전달합니다.
앱 컨트롤러 설정의 입력 장치에서 **문라이트 · 선샤인**을 선택하면 백그라운드에서도
입력을 전달합니다. 중단하려면 **입력 사용 안 함** 또는 맥의 다른 패드를 선택하세요.
연결이 끊기면 눌린 버튼과 스틱을 자동 해제합니다. 통신이 복구된 뒤에는
버튼을 다시 누르거나 스틱을 다시 움직여야 합니다.

아이폰 문라이트에서 PIN으로 선샤인을 등록합니다. 외부에서는 맥과 아이폰의
Tailscale을 연결하고 문라이트에 맥의 Tailscale 주소를 직접 추가하세요.
공유기 포트 개방과 UPnP는 필요 없습니다. 맥·앱·파이를 켜 두고 스위치 2도 미리
켜 두어야 합니다. 홈 Wi-Fi 테스트와 셀룰러 외부 접속 테스트는 별도로 확인합니다.

### Native controller / 네이티브 컨트롤러

The Pi runtime is C: authenticated binary UDP input, button-state buffering and USB or
Bluetooth output run in one session process. Python is used only by provisioning tools
and retained compatibility tests, not the native controller runtime. Protocol v2 packets
are 56 bytes: sequence (8, big endian), `VGF2`, button bits (4, little endian), four signed
16-bit axes (little endian), and HMAC-SHA256 (32). TLS enrollment and saved identities
remain compatible with the earlier service.

Use the **Basic / 기본**, **Retro effects / 레트로 효과**, and **Controller / 컨트롤러** tabs.
HOME, Capture, L+R, and Close stay visible above every tab. A physical controller's Home/Guide signal received from Moonlight is
forwarded as Switch HOME. There is no START+SELECT remapping; PLUS and MINUS stay independent.

For USB, connect the Zero W's **USB data port** (not PWR IN) to a Switch dock USB port
using a data cable. If the console does not accept wired input, check **Settings →
Controllers and Sensors → Pro Controller Wired Communication** and turn it on.
This is a HORI-compatible HID device, so the exact setting requirement needs console verification.
The dock can power the Pi through that same cable. The installer
adds the `dwc2` peripheral overlay during SD preparation so it is active on first boot.
For an existing Pi upgraded in place, reboot once after installation. A configured VGF HID gadget is preferred when a session connects; otherwise
the native daemon uses Bluetooth. Moving the cable may reboot the Pi. Auto-connect
restores the session when the Pi comes back. If USB is connected to a Mac, the HID host
is that Mac, not the Switch: connect it to the dock for console control.

USB uses a HORI-compatible eight-byte gamepad report, with both sticks, simultaneous
buttons, HOME and Capture. This avoids sharing the Zero W's radio between Wi-Fi and
Bluetooth. Rumble, motion, NFC and console wake are not implemented. A USB descriptor
and report test passing does not by itself prove compatibility with a specific Switch;
verify the actual dock connection in the console's controller test screen.

파이 실행부를 C로 교체했습니다. 기존 등록 정보는 유지하며, 설정 패널은 **기본 / 레트로 효과 /
컨트롤러** 탭으로 나뉘며 HOME·캡처·L+R과 닫기는 모든 탭 위에 고정됩니다. 문라이트의 실제 패드 홈 버튼도
그대로 전달하고 START+SELECT 조합은 바꾸지 않습니다. USB 유선 연결은 파이의
**USB 데이터 포트 → 스위치 독 USB**를 사용하세요. 새 SD에는 USB 설정이 미리 적용됩니다. 기존 파이 업그레이드 시 한 번 재부팅하세요.
USB가 활성화되지 않으면 블루투스로 연결합니다. USB 보고서 테스트와 실제 스위치
독 연결 검증은 별개입니다.
