#!/usr/bin/env bash
# Capture + decode the Tracker+ UAC2 feedback endpoint (EP3 IN) while playing a tone.
# Needs root (usbmon). Usage: sudo util/host-tests/capture_usb_feedback.sh [seconds]
set -euo pipefail
exec 2>&1
secs=${1:-3}
# per-run private dir (mode 700) instead of fixed /tmp paths; handed to the invoking user to read
outdir=$(mktemp -d /tmp/tracker-fb.XXXXXX)
tone=$outdir/tone.wav
trap 'pkill aplay 2>/dev/null || true' EXIT
fb=$outdir/feedback.txt
fbout=$outdir/out-raw.txt
modprobe usbmon
mount -t debugfs none /sys/kernel/debug 2>/dev/null || true
read -r bus dev < <(lsusb -d 16d0:1119 | sed -E 's/Bus 0*([0-9]+) Device 0*([0-9]+).*/\1 \2/')
ffmpeg -loglevel error -y -f lavfi -i "sine=f=440:r=44100:d=$((secs+2))" -ac 2 -sample_fmt s16 "$tone"
card=$(awk '/Tracker Plus/{print $1; exit}' /proc/asound/cards)
(aplay -q -D "hw:${card},0" "$tone" &) ; sleep 1
echo "bus=$bus dev=$dev; feedback EP = 3 IN"
timeout "$secs" cat "/sys/kernel/debug/usb/usbmon/${bus}u" \
  | grep -E "Zi:${bus}:0*${dev}:3 " | grep -v ' -18 ' | head -400 > "$fb" || true
pkill aplay || true
sleep 1
# raw OUT (host->device) iso submissions/completions on EP3, for packet-size analysis
echo "bus=$bus dev=$dev" > "$fbout"
(aplay -q -D "hw:${card},0" "$tone" &) ; sleep 1
timeout 1 cat "/sys/kernel/debug/usb/usbmon/${bus}u" | grep -E "Zo:${bus}:0*${dev}:3 " | head -60 >> "$fbout" || true
pkill aplay || true
echo "raw OUT packets saved to $fbout"
python3 - "$fb" <<'PY'
import re, sys, collections
c = collections.Counter()
for l in open(sys.argv[1]):
    m = re.search(r'=\s*((?:[0-9a-f]{2,8}\s*)+)', l)
    if not m: continue
    b = bytes.fromhex(''.join(m.group(1).split()))[:4]
    if len(b) == 4: c[int.from_bytes(b, 'little')] += 1
for v, n in c.most_common(8):
    print(f"raw=0x{v:08x} n={n} -> {v/65536:.4f} samples/uframe = {v/65536*8000:.0f} Hz")
print("nominal 44100 Hz = 5.5125 samples/uframe = 0x00058349")
PY
if [ -n "${SUDO_UID:-}" ]; then chown -R "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$outdir"; fi
echo "files in $outdir"
