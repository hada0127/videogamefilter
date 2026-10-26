#!/bin/bash
set -eu
umask 077
boot=/boot/firmware
[ -d "$boot/vgf-controller" ] || boot=/boot
rm -rf /opt/vgf-firstboot
mkdir -m 700 /opt/vgf-firstboot
cp -R "$boot/vgf-controller/." /opt/vgf-firstboot/
chmod -R go-rwx /opt/vgf-firstboot
cat > /etc/systemd/system/vgf-provision.service <<'UNIT'
[Unit]
Description=Install Video Game Filter controller
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0
[Service]
Type=oneshot
ExecStart=/bin/sh /opt/vgf-firstboot/install.sh
ExecStartPost=/bin/systemctl disable vgf-provision.service
Restart=on-failure
RestartSec=30
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable vgf-provision.service
python3 - "$boot/cmdline.txt" <<'PYBOOT'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
p.write_text(' '.join(x for x in p.read_text().split() if not x.startswith(('systemd.run=', 'systemd.run_success_action=', 'systemd.unit=')))+'\n')
PYBOOT
if [ -f "$boot/vgf-previous-run.txt" ]; then
    previous=$(cat "$boot/vgf-previous-run.txt")
    case "$previous" in /boot/*)
        [ -f "$previous" ] || previous="$boot/$(basename "$previous")"
        /bin/bash "$previous"
    ;; esac
fi
