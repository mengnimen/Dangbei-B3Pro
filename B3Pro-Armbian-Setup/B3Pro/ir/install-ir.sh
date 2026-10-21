#!/usr/bin/env bash
# Run inside Armbian, not on the host computer.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }
MODEL="$(tr -d '\0' < /proc/device-tree/model)"
case "$MODEL" in *Dangbei*|*dangbei*) ;; *) echo "Unexpected board: $MODEL"; exit 1;; esac
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install -d /etc/rc_keymaps
if [ -f /etc/rc_keymaps/dangbei-b3-pro.toml ]; then
 cp -p /etc/rc_keymaps/dangbei-b3-pro.toml "/etc/rc_keymaps/dangbei-b3-pro.toml.bak-$(date +%Y%m%d-%H%M%S)"
fi
install -m 644 "$HERE/dangbei-b3-pro.toml" /etc/rc_keymaps/dangbei-b3-pro.toml
if [ ! -f /etc/rc_maps.cfg ]; then
 echo "IR keymap saved. Install ir-keytable later, then rerun this script to register it."
 exit 0
fi
cp -p /etc/rc_maps.cfg "/etc/rc_maps.cfg.bak-$(date +%Y%m%d-%H%M%S)"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
RULE='meson-ir * /etc/rc_keymaps/dangbei-b3-pro.toml'
printf '%s\n' "$RULE" > "$TMP"
awk -v rule="$RULE" '$0 != rule { print }' /etc/rc_maps.cfg >> "$TMP"
cat "$TMP" > /etc/rc_maps.cfg
FOUND=0
if ! command -v ir-keytable >/dev/null; then
 echo "IR keymap saved. Install ir-keytable later to load it immediately."
 exit 0
fi
for r in /sys/class/rc/rc*; do
 [ -f "$r/uevent" ] || continue
 if grep -q '^DRV_NAME=meson-ir$' "$r/uevent"; then
  ir-keytable -s "${r##*/}" -a /etc/rc_maps.cfg
  FOUND=1
 fi
done
[ "$FOUND" -eq 1 ] || { echo "meson-ir not found; keymap saved for next boot."; exit 1; }
echo "IR installed. Reboot and test with ir-keytable -s <IR-device> -t."
