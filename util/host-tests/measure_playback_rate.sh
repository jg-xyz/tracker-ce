#!/usr/bin/env bash
# Measure the real ALSA playback rate to the Tracker+ (hw_ptr frames / wall time). No root.
# Expect ~44100; the broken snd-usb-audio path gives ~33230.
set -euo pipefail
exec 2>&1
secs=${1:-12}
card=$(awk '/Tracker Plus/{print $1; exit}' /proc/asound/cards)
[ -n "$card" ] || { echo "Tracker Plus card not found"; exit 1; }
tone=$(mktemp --suffix=.wav)
ffmpeg -loglevel error -y -f lavfi -i "sine=f=440:r=44100:d=$((secs+4))" -ac 2 -sample_fmt s16 "$tone"
echo "card=$card implicit_fb=$(cat /sys/module/snd_usb_audio/parameters/implicit_fb) lowlatency=$(cat /sys/module/snd_usb_audio/parameters/lowlatency)"
grep -E "Endpoint|Sync|Implicit" /proc/asound/card$card/stream0 | head -8
(aplay -q -D hw:$card,0 "$tone" &)
sleep 2
for _ in 1 2 3 4; do
  echo "$(date +%s.%N) $(awk '/hw_ptr/{print $3}' /proc/asound/card$card/pcm0p/sub0/status)"
  sleep 2
done | awk 'NR>1{printf "rate=%.0f Hz\n",($2-ph)/($1-pt)} {pt=$1;ph=$2}'
pkill aplay || true
