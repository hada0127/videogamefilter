#!/bin/sh
set -eu
umask 077
cd "$(dirname "$0")"
if [ "$(id -u)" != 0 ]; then
    echo 'Run with sudo on the Raspberry Pi.' >&2
    exit 1
fi
apt-get update
apt-get install -y bluez avahi-daemon iw build-essential pkg-config libssl-dev libjson-c-dev libdbus-1-dev libbluetooth-dev
install -d -m 755 /opt/videogamefilter-controller
make -C native clean all check
install -d -m 755 /opt/videogamefilter-controller/native
install -m 755 native/vgf-controller native/usb-gadget.sh /opt/videogamefilter-controller/native/
install -m 644 native/switch-controller.xml /opt/videogamefilter-controller/native/
install -m 644 vendor/NXBT-LICENSE /opt/videogamefilter-controller/native/
chown -R root:root /opt/videogamefilter-controller
chmod -R go-w /opt/videogamefilter-controller
rfkill unblock bluetooth
if [ -d identity ]; then
    install -d -m 700 /var/lib/videogamefilter-controller
    systemctl stop vgf-controller.service 2>/dev/null || true
    python3 install_identity.py identity /var/lib/videogamefilter-controller
fi
if [ -f /var/lib/videogamefilter-controller/device.json ]; then
    python3 - <<'PY'
import json,pathlib
identity=json.loads(pathlib.Path('/var/lib/videogamefilter-controller/device.json').read_text())
device=identity['id']
# IDs are generated UUIDs, never arbitrary XML input.
import uuid
assert str(uuid.UUID(device)) == device
pathlib.Path('/etc/avahi/services/vgf-controller.service').write_text('''<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group><name>Video Game Filter Pi '''+device[:8]+'''</name>
<service><type>_vgf-controller._tcp</type><port>24872</port>
<txt-record>id='''+device+'''</txt-record><txt-record>version=1</txt-record>
</service></service-group>''')
PY
    # Native controller owns HID L2CAP directly, as the previous NXBT runtime did.
    systemctl stop vgf-controller.service 2>/dev/null || true
    install -d /etc/systemd/system/bluetooth.service.d
    cat > /etc/systemd/system/bluetooth.service.d/vgf-controller.conf <<'BLUEZ'
[Service]
ExecStart=
ExecStart=/usr/libexec/bluetooth/bluetoothd --compat --noplugin=*
BLUEZ
    # This is a dedicated Zero W image; leave unrelated board sections untouched.
    config=/boot/firmware/config.txt
    if [ -f "$config" ] && ! grep -q '^dtoverlay=dwc2,dr_mode=peripheral$' "$config"; then
        cp -n "$config" "$config.vgf-backup" || true
        printf '\n[all]\n# Video Game Filter USB controller\ndtoverlay=dwc2,dr_mode=peripheral\n' >> "$config"
    fi
    cat > /etc/systemd/system/vgf-usb-gadget.service <<'GADGET'
[Unit]
Description=Video Game Filter USB controller gadget
After=systemd-modules-load.service
Before=vgf-controller.service
[Service]
Type=oneshot
ExecStart=/opt/videogamefilter-controller/native/usb-gadget.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
GADGET
    cat > /etc/systemd/system/vgf-controller.service <<'UNIT'
[Unit]
Description=Video Game Filter controller service
Wants=network-online.target bluetooth.service avahi-daemon.service vgf-usb-gadget.service
After=network-online.target bluetooth.service avahi-daemon.service vgf-usb-gadget.service
[Service]
Type=simple
ExecStartPre=/usr/sbin/rfkill unblock bluetooth
ExecStartPre=-/usr/sbin/iw dev wlan0 set power_save off
ExecStart=/opt/videogamefilter-controller/native/vgf-controller
Nice=-5
Restart=on-failure
RestartSec=3
KillMode=control-group
TimeoutStopSec=25
UMask=0077
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl restart bluetooth.service
    systemctl enable --now vgf-usb-gadget.service
    systemctl enable --now avahi-daemon.service
    systemctl enable vgf-controller.service
    systemctl restart vgf-controller.service
    # Remove only this provisioner's generated secrets/artifacts after success.
    rm -f identity/device.json identity/server.key identity/server.crt
    rmdir identity 2>/dev/null || true
    for boot in /boot/firmware /boot; do
        if [ -f "$boot/vgf-controller/identity/device.json" ]; then
            rm -rf "$boot/vgf-controller"
            rm -f "$boot/vgf-firstboot.sh" "$boot/vgf-previous-run.txt" "$boot/vgf-cmdline-original.txt"
        fi
    done
fi
printf 'Controller service installed.\n'
