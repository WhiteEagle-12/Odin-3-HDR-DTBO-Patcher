param(
  [switch]$DryRun,
  [switch]$NoReboot
)

$ErrorActionPreference = "Stop"

function Run-Adb {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "adb"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.Arguments = ($Args | ForEach-Object {
    if ($_ -match '^[A-Za-z0-9_./:=@%+-]+$') {
      $_
    } else {
      '"' + ($_.Replace('\', '\\').Replace('"', '\"')) + '"'
    }
  }) -join " "

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $psi
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  $output = (($stdout, $stderr) | Where-Object { $_ }) -join "`n"
  if ($process.ExitCode -ne 0) {
    throw "adb $($Args -join ' ') failed:`n$output"
  }
  return $output
}

function Run-Root {
  param([string]$Command)
  return Run-Adb shell su -c $Command
}

function Read-U32BE {
  param([byte[]]$Bytes, [int]$Offset)
  return [uint32]((([uint32]$Bytes[$Offset]) -shl 24) -bor (([uint32]$Bytes[$Offset + 1]) -shl 16) -bor (([uint32]$Bytes[$Offset + 2]) -shl 8) -bor ([uint32]$Bytes[$Offset + 3]))
}

function Write-U32BE {
  param([byte[]]$Bytes, [int]$Offset, [uint32]$Value)
  $Bytes[$Offset] = [byte](($Value -shr 24) -band 0xff)
  $Bytes[$Offset + 1] = [byte](($Value -shr 16) -band 0xff)
  $Bytes[$Offset + 2] = [byte](($Value -shr 8) -band 0xff)
  $Bytes[$Offset + 3] = [byte]($Value -band 0xff)
}

function Align4 {
  param([int]$Value)
  return (($Value + 3) -band (-bnot 3))
}

function Get-CString {
  param([byte[]]$Bytes, [int]$Offset)
  $end = $Offset
  while ($end -lt $Bytes.Length -and $Bytes[$end] -ne 0) {
    $end++
  }
  return [Text.Encoding]::ASCII.GetString($Bytes, $Offset, $end - $Offset)
}

function Patch-Fdt {
  param(
    [byte[]]$Image,
    [int]$FdtOffset,
    [string]$ImageLabel
  )

  if ((Read-U32BE $Image $FdtOffset) -ne [uint32]3490578157) {
    throw "$ImageLabel does not contain an FDT at offset $FdtOffset"
  }

  $totalsize = Read-U32BE $Image ($FdtOffset + 4)
  $offStruct = $FdtOffset + (Read-U32BE $Image ($FdtOffset + 8))
  $offStrings = $FdtOffset + (Read-U32BE $Image ($FdtOffset + 12))
  $sizeStruct = Read-U32BE $Image ($FdtOffset + 36)

  $pos = $offStruct
  $end = $offStruct + $sizeStruct
  $path = New-Object System.Collections.Generic.List[string]
  $targets = @()

  while ($pos -lt $end) {
    $token = Read-U32BE $Image $pos
    $pos += 4

    if ($token -eq 0 -or $token -eq 9) {
      return $targets
    }

    switch ($token) {
      1 {
        $name = Get-CString $Image $pos
        $pos = Align4 ($pos + $name.Length + 1)
        if ($name.Length -gt 0) {
          $path.Add($name)
        }
      }
      2 {
        if ($path.Count -gt 0) {
          $path.RemoveAt($path.Count - 1)
        }
      }
      3 {
        $len = Read-U32BE $Image $pos
        $nameoff = Read-U32BE $Image ($pos + 4)
        $pos += 8
        $valueOffset = $pos
        $propName = Get-CString $Image ($offStrings + $nameoff)
        $currentPath = "/" + ($path -join "/")

        if (
          $propName -eq "qcom,mdss-dsi-panel-peak-brightness" -and
          $len -eq 4 -and
          $currentPath -match "icna3520"
        ) {
          $value = Read-U32BE $Image $valueOffset
          if ($value -eq 4200000 -or $value -eq 7824283) {
            $targets += [pscustomobject]@{
              Label = $ImageLabel
              Path = $currentPath
              Offset = $valueOffset
              Value = $value
            }
            if ($value -eq 4200000) {
              Write-U32BE $Image $valueOffset 7824283
            }
          }
        }

        $pos = Align4 ($pos + $len)
      }
      4 { }
      default {
        throw "$ImageLabel has unexpected FDT token $token at offset $($pos - 4)"
      }
    }
  }
  return $targets
}

function Patch-Dtbo {
  param([string]$InputPath, [string]$OutputPath)

  $image = [IO.File]::ReadAllBytes($InputPath)
  if ((Read-U32BE $image 0) -ne [uint32]3619138334) {
    throw "Input does not look like an Android DTBO image."
  }

  $headerSize = Read-U32BE $image 8
  $entrySize = Read-U32BE $image 12
  $entryCount = Read-U32BE $image 16
  $entriesOffset = Read-U32BE $image 20
  $allTargets = @()

  for ($i = 0; $i -lt $entryCount; $i++) {
    $entry = $entriesOffset + ($i * $entrySize)
    $dtSize = Read-U32BE $image $entry
    $dtOffset = Read-U32BE $image ($entry + 4)
    if ($dtOffset -lt $headerSize -or ($dtOffset + $dtSize) -gt $image.Length) {
      throw "DTBO entry $i has invalid bounds."
    }
    $allTargets += Patch-Fdt -Image $image -FdtOffset $dtOffset -ImageLabel "dtbo entry $i"
  }

  $patchable = @($allTargets | Where-Object { $_.Value -eq 4200000 })
  $alreadyPatched = @($allTargets | Where-Object { $_.Value -eq 7824283 })

  if ($patchable.Count -gt 0 -and $alreadyPatched.Count -eq 0) {
    [IO.File]::WriteAllBytes($OutputPath, $image)
    return [pscustomobject]@{
      Status = "Patched"
      Targets = $patchable
    }
  }

  if ($patchable.Count -eq 0 -and $alreadyPatched.Count -gt 0) {
    return [pscustomobject]@{
      Status = "AlreadyPatched"
      Targets = $alreadyPatched
    }
  }

  $details = $allTargets | ForEach-Object { "$($_.Label): $($_.Path) = $($_.Value)" }
  throw "Found a mixed or invalid Odin 3 ICNA3520 peak-brightness state: patchable=$($patchable.Count), alreadyPatched=$($alreadyPatched.Count).`n$($details -join "`n")"
}

Write-Host "Odin 3 HDR DTBO Peak Brightness Patcher"
Write-Host "This patches the active DTBO partition from 420.0 nits to 782.4283 nits."
Write-Host "It will back up the original DTBO before flashing."
if ($DryRun) {
  Write-Host "Dry-run mode: no flashing and no reboot."
}
Write-Host ""

Run-Adb devices | Out-Host
$serial = (Run-Adb get-serialno).Trim()
if (-not $serial -or $serial -eq "unknown") {
  throw "No ADB device found."
}

$rootCheck = (Run-Root "id").Trim()
if ($rootCheck -notmatch "uid=0") {
  throw "Root shell is not available through Magisk su."
}

$device = (Run-Adb shell getprop ro.product.device).Trim()
$model = (Run-Adb shell getprop ro.product.model).Trim()
$slot = (Run-Adb shell getprop ro.boot.slot_suffix).Trim()
if ($slot -notmatch "^_[ab]$") {
  throw "Could not determine active slot. ro.boot.slot_suffix='$slot'"
}

$dtboBlock = (Run-Root "readlink -f /dev/block/by-name/dtbo$slot").Trim()
if (-not $dtboBlock) {
  throw "Could not resolve dtbo$slot block device."
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$workDir = Join-Path $PSScriptRoot "backups\$serial-$timestamp"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

$original = Join-Path $workDir "dtbo$slot.original.img"
$patched = Join-Path $workDir "dtbo$slot.hdr782.img"
$readback = Join-Path $workDir "dtbo$slot.readback.img"

Write-Host "Device: $model ($device)"
Write-Host "Serial: $serial"
Write-Host "Active slot: $slot"
Write-Host "DTBO block: $dtboBlock"
Write-Host "Backup folder: $workDir"

Run-Root "dd if=$dtboBlock of=/data/local/tmp/dtbo$slot.original.img bs=4096" | Out-Host
Run-Adb pull "/data/local/tmp/dtbo$slot.original.img" $original | Out-Host
Run-Root "rm -f /data/local/tmp/dtbo$slot.original.img" | Out-Null

$result = Patch-Dtbo -InputPath $original -OutputPath $patched
if ($result.Status -eq "AlreadyPatched") {
  $originalHash = (Get-FileHash $original -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-Host "Already patched: $($result.Targets.Count) ICNA3520 peak-brightness entries"
  foreach ($target in $result.Targets) {
    Write-Host "  $($target.Label): $($target.Path)"
  }
  Write-Host "Current value: 7824283"
  Write-Host "No flashing needed."
  Write-Host "Original backup SHA256: $originalHash"
  Write-Host "Original backup saved at: $original"
  exit 0
}

Write-Host "Patched $($result.Targets.Count) ICNA3520 peak-brightness entries:"
foreach ($target in $result.Targets) {
  Write-Host "  $($target.Label): $($target.Path)"
}
Write-Host "Old value: 4200000"
Write-Host "New value: 7824283"

$originalHash = (Get-FileHash $original -Algorithm SHA256).Hash.ToLowerInvariant()
$patchedHash = (Get-FileHash $patched -Algorithm SHA256).Hash.ToLowerInvariant()
if ($originalHash -eq $patchedHash) {
  throw "Patched image hash matches original; refusing to flash."
}

if ($DryRun) {
  Write-Host ""
  Write-Host "Dry-run complete."
  Write-Host "Original backup SHA256: $originalHash"
  Write-Host "Patched test image SHA256: $patchedHash"
  Write-Host "Original backup saved at: $original"
  Write-Host "Patched test image saved at: $patched"
  exit 0
}

Run-Adb push $patched "/data/local/tmp/dtbo$slot.hdr782.img" | Out-Host
Run-Root "dd if=/data/local/tmp/dtbo$slot.hdr782.img of=$dtboBlock bs=4096 conv=fsync" | Out-Host
Run-Root "dd if=$dtboBlock of=/data/local/tmp/dtbo$slot.readback.img bs=4096" | Out-Host
Run-Adb pull "/data/local/tmp/dtbo$slot.readback.img" $readback | Out-Host
Run-Root "rm -f /data/local/tmp/dtbo$slot.hdr782.img /data/local/tmp/dtbo$slot.readback.img" | Out-Null

$readbackHash = (Get-FileHash $readback -Algorithm SHA256).Hash.ToLowerInvariant()
if ($readbackHash -ne $patchedHash) {
  throw "Readback hash does not match patched image. Backup is saved at $original"
}

Write-Host ""
Write-Host "Patch complete."
Write-Host "Original backup SHA256: $originalHash"
Write-Host "Patched/readback SHA256: $patchedHash"
Write-Host "Original backup saved at: $original"

if (-not $NoReboot) {
  Write-Host "Rebooting..."
  Run-Adb reboot | Out-Null
} else {
  Write-Host "NoReboot was set. Reboot manually to activate the patched DTBO."
}
