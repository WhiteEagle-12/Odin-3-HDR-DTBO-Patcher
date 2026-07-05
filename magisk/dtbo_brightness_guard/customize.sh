#!/system/bin/sh

CONF_DIR=/data/adb/dtbo_guard

ui_print "*******************************"
ui_print " DTBO Peak Brightness Guard"
ui_print " v1.1.0 by KingAether"
ui_print "*******************************"

mkdir -p "$CONF_DIR"
if [ -f "$CONF_DIR/config.conf" ]; then
  ui_print "- Kept existing config."
else
  cp -f "$MODPATH/config.conf" "$CONF_DIR/config.conf"
  ui_print "- Default config installed."
fi

ui_print "- Copy the patched DTBO image to:"
ui_print "  $CONF_DIR/dtbo_patched.img"
ui_print "- Copy the original DTBO backup to:"
ui_print "  $CONF_DIR/dtbo_original.img"
ui_print "- While installed, the guard re-applies the"
ui_print "  patched DTBO if the active slot reverts."
ui_print "- Removing the module restores the original"
ui_print "  DTBO if dtbo_original.img is present."
ui_print "- Log: $CONF_DIR/guard.log"

chmod 755 "$MODPATH/service.sh" "$MODPATH/uninstall.sh"
