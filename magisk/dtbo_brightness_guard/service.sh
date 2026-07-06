#!/system/bin/sh
# DTBO Peak Brightness Guard - boot service

MODDIR=${0%/*}
CONF=$MODDIR/config.conf
LOG=$MODDIR/guard.log

log() { echo "$(date '+%m-%d %H:%M:%S') $1" >> "$LOG"; }

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 5

[ -f "$CONF" ] || exit 0
. "$CONF"

: > "$LOG"
log "guard started"

slot_suffix() {
  getprop ro.boot.slot_suffix
}

dtbo_part_for_slot() {
  case "$1" in
    _a|_b) echo "/dev/block/by-name/dtbo$1" ;;
    *) echo "" ;;
  esac
}

hex4() {
  od -A n -t x1 -N4 "$1" 2>/dev/null | tr -d ' \n'
}

partition_matches_image() {
  [ -f "$1" ] || return 1
  [ -e "$2" ] || return 1
  cmp -s "$1" "$2"
}

flash_img() {
  img=$1
  part=$2

  if [ ! -f "$img" ]; then
    log "cannot flash: image missing: $img"
    return 1
  fi
  if [ ! -e "$part" ]; then
    log "cannot flash: partition missing: $part"
    return 1
  fi

  img_size=$(stat -c %s "$img" 2>/dev/null)
  part_size=$(blockdev --getsize64 "$part" 2>/dev/null)
  if [ -n "$img_size" ] && [ -n "$part_size" ] && [ "$img_size" -gt "$part_size" ]; then
    log "ABORT: image ($img_size) larger than partition ($part_size)"
    return 1
  fi

  if dd if="$img" of="$part" bs=1048576 conv=fsync 2>>"$LOG"; then
    sync
    log "flashed $img -> $part"
    return 0
  fi

  log "ERROR: dd failed for $part"
  return 1
}

SLOT=$(slot_suffix)
ACTIVE=$(dtbo_part_for_slot "$SLOT")
log "active slot: ${SLOT:-none} ($ACTIVE)"

if [ -z "$ACTIVE" ] || [ ! -e "$ACTIVE" ]; then
  log "ERROR: active DTBO partition not found"
  exit 0
fi

MATCHED=0
PATCHED=0
STOCK=0
UNKNOWN=0

for node in $(find "$DT_ROOT" -path "*$PANEL_MARKER*" -name "$PEAK_PROP" 2>/dev/null); do
  MATCHED=$((MATCHED + 1))
  cur=$(hex4 "$node")
  log "live value: $cur at $node"
  case "$cur" in
    "$EXPECTED_HEX") PATCHED=$((PATCHED + 1)) ;;
    "$STOCK_HEX") STOCK=$((STOCK + 1)) ;;
    *) UNKNOWN=$((UNKNOWN + 1)) ;;
  esac
done

log "matched nodes: $MATCHED patched: $PATCHED stock: $STOCK unknown: $UNKNOWN"

if [ "$MATCHED" -eq 0 ]; then
  log "ERROR: no matching live device-tree nodes found"
  exit 0
fi

if [ "$PATCHED" -gt 0 ] && [ "$STOCK" -eq 0 ] && [ "$UNKNOWN" -eq 0 ]; then
  log "OK: patched DTBO is active"
else
  log "MISMATCH: stock/unknown ICNA3520 DTBO value detected"
  if [ "$AUTO_FLASH" = "1" ]; then
    flash_img "$PATCHED_IMG" "$ACTIVE" && log "NOTE: reboot required for the patch to take effect"
  else
    log "AUTO_FLASH=0, leaving DTBO unchanged"
  fi
fi

if [ "$PATCH_BOTH_SLOTS" = "1" ]; then
  case "$SLOT" in
    _a) OTHER=$(dtbo_part_for_slot _b) ;;
    _b) OTHER=$(dtbo_part_for_slot _a) ;;
    *) OTHER= ;;
  esac

  if [ -n "$OTHER" ] && [ -e "$OTHER" ]; then
    if partition_matches_image "$PATCHED_IMG" "$OTHER"; then
      log "inactive slot already matches patched image"
    else
      log "inactive slot differs from patched image, flashing $OTHER"
      flash_img "$PATCHED_IMG" "$OTHER"
    fi
  else
    log "inactive DTBO partition not found"
  fi
fi

log "guard done"
