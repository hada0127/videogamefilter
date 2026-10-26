#!/bin/sh
# Configure only VGF's own gadget; never detach another USB gadget.
set -eu
umask 077
modprobe libcomposite
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
base=/sys/kernel/config/usb_gadget
gadget=$base/vgf-controller
attempt=0
while [ "$attempt" -lt 20 ]; do
    set -- /sys/class/udc/*
    [ -e "$1" ] && break
    sleep 0.5
    attempt=$((attempt + 1))
done
[ -e "$1" ] || { echo 'USB peripheral controller unavailable; reboot after enabling dwc2.' >&2; exit 0; }
udc=${1##*/}
for other in "$base"/*; do
    [ -d "$other" ] || continue
    [ "$other" = "$gadget" ] && continue
    if [ -s "$other/UDC" ] && [ -n "$(cat "$other/UDC")" ]; then
        echo 'Another gadget owns USB; leaving it unchanged.' >&2; exit 1
    fi
done
mkdir -p "$gadget"
if [ -n "$(cat "$gadget/UDC")" ]; then
    echo 'VGF USB gadget already active.'
else
    echo 0x0f0d > "$gadget/idVendor"
    echo 0x0092 > "$gadget/idProduct"
    echo 0x0200 > "$gadget/bcdUSB"
    echo 0x0100 > "$gadget/bcdDevice"
    mkdir -p "$gadget/strings/0x409" "$gadget/configs/c.1/strings/0x409" "$gadget/functions/hid.usb0"
    echo 'Video Game Filter' > "$gadget/strings/0x409/manufacturer"
    echo 'Switch Wired Controller' > "$gadget/strings/0x409/product"
    echo 'VGF Controller' > "$gadget/configs/c.1/strings/0x409/configuration"
    echo 500 > "$gadget/configs/c.1/MaxPower"
    echo 0x80 > "$gadget/configs/c.1/bmAttributes"
    echo 0 > "$gadget/functions/hid.usb0/subclass"
    echo 0 > "$gadget/functions/hid.usb0/protocol"
    echo 8 > "$gadget/functions/hid.usb0/report_length"
    if [ -f "$gadget/functions/hid.usb0/interval" ]; then echo 1 > "$gadget/functions/hid.usb0/interval"; fi
    /opt/videogamefilter-controller/native/vgf-controller --hid-descriptor > "$gadget/functions/hid.usb0/report_desc"
    [ -L "$gadget/configs/c.1/hid.usb0" ] || ln -s "$gadget/functions/hid.usb0" "$gadget/configs/c.1/hid.usb0"
    echo "$udc" > "$gadget/UDC"
fi
# Resolve our own HID function, even if another unbound function allocated hidg0.
dev=$(cat "$gadget/functions/hid.usb0/dev")
name=$(sed -n 's/^DEVNAME=//p' "/sys/dev/char/$dev/uevent")
case "$name" in hidg[0-9]*) ;; *) echo 'Invalid HID function device' >&2; exit 1;; esac
printf '/dev/%s\n' "$name" > /run/vgf-hid-device
chmod 600 /run/vgf-hid-device
