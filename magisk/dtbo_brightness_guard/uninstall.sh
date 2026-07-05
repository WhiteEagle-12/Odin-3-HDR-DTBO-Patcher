#!/system/bin/sh
# DTBO Peak Brightness Guard - uninstall hook

DIR=/data/adb/dtbo_guard
CONF=$DIR/config.conf
LOG=$DIR/guard.log

[ -f "$CONF" ] && . "$CONF"
[ -n "$ORIGINAL_IMG" ] || ORIGINAL_IMG=$DIR/dtbo_original.img

log() { echo "$(date '+%m-%d %H:%M:%S') [uninstall] $1" >> "$LOG"; }

dtbo_part_for_slot() {
  case "$1" in
    _a|_b) echo "/dev/block/by-name/dtbo$1" ;;
    *) echo "" ;;
  esac
}

restore_img() {
  img=$1
  part=$2

  if [ ! -f "$img" ]; then
    log "no original backup at $img - NOT restoring"
    return 1
  fi
  if [ ! -e "$part" ]; then
    log "partition $part not found - NOT restoring"
    return 1
  fi

  img_size=$(stat -c %s "$img" 2>/dev/null)
  part_size=$(blockdev --getsize64 "$part" 2>/dev/null)
  if [ -n "$img_size" ] && [ -n "$part_size" ] && [ "$img_size" -gt "$part_size" ]; then
    log "backup larger than partition - NOT restoring"
    return 1
  fi

  if dd if="$img" of="$part" bs=1048576 conv=fsync 2>>"$LOG"; then
    sync
    log "original DTBO restored to $part - takes effect on next reboot"
    return 0
  fi

  log "ERROR: restore dd failed for $part"
  return 1
}

SLOT=$(getprop ro.boot.slot_suffix)
ACTIVE=$(dtbo_part_for_slot "$SLOT")

if [ "$RESTORE_BOTH_SLOTS" = "1" ]; then
  restore_img "$ORIGINAL_IMG" "$(dtbo_part_for_slot _a)"
  restore_img "$ORIGINAL_IMG" "$(dtbo_part_for_slot _b)"
else
  restore_img "$ORIGINAL_IMG" "$ACTIVE"
fi

# Keep $DIR and the images so nothing is lost. The user can delete them manually.
