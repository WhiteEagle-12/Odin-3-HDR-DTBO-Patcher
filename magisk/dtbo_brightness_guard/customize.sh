#!/system/bin/sh

ui_print "*******************************"
ui_print " DTBO Peak Brightness Guard"
ui_print " v1.1.3 by KingAether"
ui_print "*******************************"

ui_print "- Default config installed in the module."

ui_print "- Copy the patched DTBO image to:"
ui_print "  /data/local/tmp/dtbo_patched.img"
ui_print "- Copy the original DTBO backup to:"
ui_print "  /data/local/tmp/dtbo_original.img"
ui_print "- While installed, the guard re-applies the"
ui_print "  patched DTBO if the active slot reverts."
ui_print "- Removing the module restores the original"
ui_print "  DTBO if dtbo_original.img is present."
ui_print "- Log: $MODPATH/guard.log"

chmod 755 "$MODPATH/service.sh" "$MODPATH/uninstall.sh"
