# Odin 3 HDR DTBO Peak Brightness Patcher

Companion tool for the Odin 3 HDR Fix Magisk module.

This patches the Odin 3 device tree overlay so Android reports the panel's real HDR peak brightness instead of the stock 420-nit limit.

## Quickstart

Download the latest release ZIP:

```text
Odin-3-HDR-DTBO-Patcher-v1.1.1.zip
```

Unzip it on Windows, connect the Odin 3 over USB, then run:

```powershell
.\patch_odin3_hdr_dtbo.ps1
```

The patcher is the required part. It backs up the active DTBO, patches the active slot, verifies the readback hash, and reboots. On tested Odin 3 firmware, good output is one of these:

```text
Patched 40 ICNA3520 peak-brightness entries
```

or, if some entries were already patched by a previous run:

```text
Patched 29 ICNA3520 peak-brightness entries
Already patched entries left unchanged: 11
```

or, if the device is already fully patched:

```text
Already patched: 40 ICNA3520 peak-brightness entries
```

If the output does not match one of those patterns, download the latest release and run the patcher again.

After reboot, verify:

```sh
adb shell dumpsys display | grep -i HdrCapabilities
```

Expected result includes:

```text
mMaxLuminance=782.4283
mMaxAverageLuminance=782.4283
```

### Optional Guard Module

The guard is optional. It is installed as a Magisk module ZIP:

```text
DTBO-Brightness-Guard-v1.1.3.zip
```

The guard does not create the patch. Install it only after running the patcher. Its job is to watch for OTA or slot-change regressions and re-flash the saved patched DTBO if the device boots back to stock.

After installing the guard module in Magisk, keep these two files on the device:

```sh
adb push .\backups\<folder>\dtbo_a.hdr782.img /data/local/tmp/dtbo_patched.img
adb push .\backups\<folder>\dtbo_a.original.img /data/local/tmp/dtbo_original.img
```

Use `dtbo_b` filenames instead if your active slot is `_b`.

Guard boot behavior:

1. If the live DTBO is already patched, it logs OK and does nothing.
2. If the live DTBO is stock, it flashes `/data/local/tmp/dtbo_patched.img` back to the active slot.
3. If the guard had to flash, reboot once more so Android boots from the patched DTBO.
4. If the module is removed in Magisk, it tries to restore `/data/local/tmp/dtbo_original.img` to the active slot.

## What This Fixes

Some Odin 3 units advertise HDR support, but the active panel device tree reports:

```text
qcom,mdss-dsi-panel-peak-brightness = 4200000
```

Qualcomm's display stack interprets that as `420.0` nits. The Odin 3 panel display config contains brightness data up to about `782.4283` nits, so Android ends up with conflicting information:

- display config brightness curve: about `782.4283` nits
- DTBO-reported HDR peak brightness: `420.0` nits

This patch changes only the active ICNA3520 panel peak-brightness entries across all matching DTBO overlays:

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

Magisk module repo:

https://github.com/kingaetheral/Odin-3-HDR-Fix-Persistence

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

On tested Odin 3 firmware this patches 40 ICNA3520 peak-brightness entries. The parser handles embedded FDT blobs even when their DTBO offsets are not 4-byte aligned.

If a previous run already partially patched 11 entries, this version can be run directly over it. It will leave the already-patched entries unchanged and patch the remaining stock entries.

Backups are saved under:

```text
backups/<device-serial>-<timestamp>/
```

## Dry Run

To verify that the connected device has exactly the expected patch target without flashing:

```powershell
.\patch_odin3_hdr_dtbo.ps1 -DryRun
```

Dry run mode still pulls and backs up the active DTBO. If the DTBO is unpatched, it creates a patched test image locally. If the DTBO is already patched, it reports the patched entries and exits without creating a new image. It does not push, flash, or reboot.

## No-Reboot Mode

To patch and verify without automatically rebooting:

```powershell
.\patch_odin3_hdr_dtbo.ps1 -NoReboot
```

You must still reboot before Android uses the patched DTBO.

## Optional Magisk Guard

This repo also includes an optional Magisk module source tree under:

```text
magisk/dtbo_brightness_guard/
```

The guard does not replace the PowerShell patcher. It is a persistence and reversibility helper for people who already ran the patcher and want Magisk to watch for OTA or slot-change regressions.

The current guard module version is `v1.1.3`.

Guard lifecycle:

1. Run this patcher first so you have both images:
   - `dtbo_<slot>.original.img`
   - `dtbo_<slot>.hdr782.img` or `dtbo_<slot>.readback.img`
2. Install the guard module in Magisk.
3. Copy the images on-device and keep them there while the guard is installed:

```sh
adb push .\backups\<folder>\dtbo_a.hdr782.img /data/local/tmp/dtbo_patched.img
adb push .\backups\<folder>\dtbo_a.original.img /data/local/tmp/dtbo_original.img
```

Use `dtbo_b` filenames instead if your active slot is `_b`.

While installed, the guard checks the live ICNA3520 peak-brightness device-tree value after boot. If it sees stock or unknown values and `AUTO_FLASH=1`, it writes `dtbo_patched.img` back to the active `dtbo` partition. The patch takes effect after the next reboot.

When removed in Magisk, `uninstall.sh` restores `dtbo_original.img` to the active `dtbo` partition if that backup exists and fits the partition. If the backup is missing or invalid, it logs the problem and leaves the DTBO untouched.

Caveats:

- Reversibility depends on keeping the correct `dtbo_original.img`.
- The guard expects `dtbo_patched.img` and `dtbo_original.img` to remain at `/data/local/tmp/` unless you edit `PATCHED_IMG` and `ORIGINAL_IMG` in `/data/adb/modules/dtbo_brightness_guard/config.conf`.
- By default, uninstall restores only the active slot. Set `RESTORE_BOTH_SLOTS=1` in `/data/adb/modules/dtbo_brightness_guard/config.conf` if you intentionally want both slots restored.
- By default, the guard patches only the active slot. Set `PATCH_BOTH_SLOTS=1` only if you intentionally want the inactive slot kept byte-identical to the same patched image.

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

OTAs or slot switches may replace the patched DTBO. If you are not using the optional Magisk guard and HDR max luminance returns to `420.0`, rerun the patcher on the active slot.

If the optional guard is installed with `AUTO_FLASH=1`, it should detect the stock value after boot and re-flash `dtbo_patched.img` to the active slot. Reboot once more after the guard logs a flash so Android boots from the patched DTBO.

## Credits

- WhiteEagle-12
