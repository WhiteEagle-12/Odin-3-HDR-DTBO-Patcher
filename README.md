# Odin 3 HDR DTBO Peak Brightness Patcher

Companion tool for the Odin 3 HDR Fix Magisk module.

This patches the Odin 3 device tree overlay so Android reports the panel's real HDR peak brightness instead of the stock 420-nit limit.

## What This Fixes

Some Odin 3 units advertise HDR support, but the active panel device tree reports:

```text
qcom,mdss-dsi-panel-peak-brightness = 4200000
```

Qualcomm's display stack interprets that as `420.0` nits. The Odin 3 panel display config contains brightness data up to about `782.4283` nits, so Android ends up with conflicting information:

- display config brightness curve: about `782.4283` nits
- DTBO-reported HDR peak brightness: `420.0` nits

This patch changes only the active ICNA3520 panel peak-brightness entries:

```text
4200000 -> 7824283
```

After reboot, Android should report HDR max luminance around:

```text
782.4283
```

## Relationship To The Magisk Module

The complete Odin 3 HDR fix has two parts:

1. **DTBO peak-brightness patch** from this repo
   - changes the panel-reported HDR peak from `420.0` to `782.4283`
   - flashes the active `dtbo` partition
   - persists after removing Magisk modules

2. **Odin 3 HDR Fix Magisk module**
   - overlays the matching display config XML
   - applies HDR display properties
   - optionally keeps the SurfaceFlinger composition workaround active
   - is systemless and reversible

Use both for the full fix.

## Warning

This is not a normal Magisk module and it is not systemless.

The script flashes the active `dtbo` partition. It makes a backup first, but you should still treat this as an advanced operation. A bad DTBO flash can cause boot or display problems.

Only use this on the AYN Odin 3 with the ICNA3520 OLED panel.

## Requirements

- Windows
- ADB in PATH
- Odin 3 connected over USB
- USB debugging enabled
- Magisk root working through `su`
- Bootloader already unlocked

## Usage

Open PowerShell in this repo and run:

```powershell
.\patch_odin3_hdr_dtbo.ps1
```

The script will:

1. Detect the active slot.
2. Resolve the active `dtbo` block device.
3. Pull a backup of the current DTBO.
4. Patch the Odin 3 ICNA3520 panel peak-brightness properties.
5. Flash the patched image back to the active `dtbo` partition.
6. Pull a readback copy and verify the hash.
7. Reboot unless `-NoReboot` is used.

Backups are saved under:

```text
backups/<device-serial>-<timestamp>/
```

## Dry Run

To verify that the connected device has exactly the expected patch target without flashing:

```powershell
.\patch_odin3_hdr_dtbo.ps1 -DryRun
```

Dry run mode still pulls and backs up the active DTBO, then creates a patched test image locally. It does not push, flash, or reboot.

## No-Reboot Mode

To patch and verify without automatically rebooting:

```powershell
.\patch_odin3_hdr_dtbo.ps1 -NoReboot
```

You must still reboot before Android uses the patched DTBO.

## Verification

After reboot:

```sh
adb shell dumpsys display | grep -i HdrCapabilities
```

Expected result includes:

```text
mMaxLuminance=782.4283
mMaxAverageLuminance=782.4283
```

SurfaceFlinger should also show:

```text
desiredMaxLuminance=782.428284
```

## Restore

The script saves the original DTBO image before flashing. To restore manually, push the backup and write it to the active DTBO block.

Example:

```powershell
adb push .\backups\<folder>\dtbo_a.original.img /data/local/tmp/dtbo_a.original.img
adb shell su -c "dd if=/data/local/tmp/dtbo_a.original.img of=/dev/block/by-name/dtbo_a bs=4096 conv=fsync"
adb reboot
```

Use `dtbo_b` instead if your active slot is `_b`.

## OTA Notes

OTAs or slot switches may replace the patched DTBO. If HDR max luminance returns to `420.0`, rerun the patcher on the active slot.

## Credits

- kingaetheral
- WhiteEagle-12
- Zurce
