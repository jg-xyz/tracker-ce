#!/usr/bin/env bash
# Apply/persist/revert the snd-usb-audio settings that fix Tracker+ playback garbling
# (host plays at ~33.2 kHz with default explicit feedback; implicit_fb=1 gives ~44.1 kHz).
# See docs/tracker-plus-usb-audio-garbling.md. Run as your normal user; uses sudo for
# the privileged steps (needs a terminal to prompt for the password).
#
#   tracker_usb_audio_settings.sh apply    reload snd_usb_audio now with implicit_fb=1 (until reboot)
#   tracker_usb_audio_settings.sh persist  write /etc/modprobe.d/tracker-plus-usb-audio.conf + apply
#   tracker_usb_audio_settings.sh revert   remove the conf file + reload with stock defaults
#   tracker_usb_audio_settings.sh status   show current params and measured Tracker+ sync mode
#   Add --dry-run (any mode) to print the commands instead of running them.
set -euo pipefail
exec 2>&1

CONF=/etc/modprobe.d/tracker-plus-usb-audio.conf
# implicit_fb is a bool array indexed by card slot; cover slots 0-7. lowlatency left at default.
OPTS="implicit_fb=1,1,1,1,1,1,1,1"
UNITS=(pipewire.socket pipewire-pulse.socket pipewire pipewire-pulse wireplumber)
mode=${1:-status}; dry=0
[ "${2:-}" = "--dry-run" ] || [ "${1:-}" = "--dry-run" ] && dry=1
[ "$mode" = "--dry-run" ] && mode=status

run() { if [ "$dry" = 1 ]; then echo "+ $*"; else "$@"; fi; }

status() {
  echo "implicit_fb=$(cat /sys/module/snd_usb_audio/parameters/implicit_fb 2>/dev/null | cut -c1-24)... lowlatency=$(cat /sys/module/snd_usb_audio/parameters/lowlatency 2>/dev/null)"
  card=$(awk '/Tracker Plus/{print $1; exit}' /proc/asound/cards || true)
  if [ -n "${card:-}" ]; then
    echo "Tracker+ is card $card:"
    grep -E "Sync Endpoint|Implicit Feedback Mode" "/proc/asound/card$card/stream0" | head -2
  else
    echo "Tracker+ not found in /proc/asound/cards"
  fi
  [ -f "$CONF" ] && { echo "persisted: $CONF"; cat "$CONF"; } || echo "not persisted"
}

reload() {
  local opts=$1
  run systemctl --user stop "${UNITS[@]}" || true
  run sudo modprobe -r snd_usb_audio
  run sudo modprobe snd_usb_audio $opts
  run systemctl --user start pipewire pipewire-pulse wireplumber
  [ "$dry" = 1 ] || { sleep 2; status; }
}

case "$mode" in
  apply)   reload "$OPTS" ;;
  persist)
    if [ "$dry" = 1 ]; then echo "+ write $CONF: options snd-usb-audio $OPTS"
    else printf '# Tracker+ playback runs at 33.2 kHz with explicit feedback; see docs/tracker-plus-usb-audio-garbling.md\noptions snd-usb-audio %s\n' "$OPTS" | sudo tee "$CONF" >/dev/null; fi
    reload "$OPTS" ;;
  revert)
    run sudo rm -f "$CONF"
    reload "" ;;
  status)  status ;;
  *) sed -n '2,12p' "$0"; exit 2 ;;
esac
