param([string]$hunk = "")
# where the time before the first VBL goes: initScroller and initMusic by routine
$ErrorActionPreference = 'Stop'
$p = "$PSScriptRoot\prof"
if (-not $hunk) { $hunk = "$PSScriptRoot\build\d" }
$src = (Get-Content "$p\Emu.cs" -Raw) + "`n" + (Get-Content "$p\Seq.cs" -Raw) + "`n" + (Get-Content "$p\Den.cs" -Raw) + "`n" + (Get-Content "$p\Spr.cs" -Raw) + "`n" + (Get-Content "$p\Aud.cs" -Raw) -replace '(?m)^using [^\r\n]+;\r?\n', ''
$src = "using System;using System.Collections.Generic;using System.IO;using System.Text;using System.Linq;`n" + $src
Add-Type -TypeDefinition $src -Language CSharp
[Emu]::LoadHunk($hunk, 0x100000)
[Emu]::A[7] = 0x0c0000; [Emu]::A[6] = 0xdff000; [Emu]::cyc = 0
foreach ($n in "initScroller","initMusic") {
  [Emu]::ResetStack(); [Emu]::A[6] = 0xdff000
  $c0 = [Emu]::cyc
  [Emu]::frameInc.Clear(); [Emu]::frameCnt.Clear(); [Emu]::profile = $true
  [Emu]::Call([Emu]::symByName[$n])
  [Emu]::profile = $false
  $d = [Emu]::cyc - $c0
  "{0}: {1:N0} Zyklen = {2:N1} Frames" -f $n, $d, ($d / 141875.0)
  foreach ($kv in ([Emu]::frameInc.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 12)) {
    "   {0} = {1:N0} x{2}" -f [Emu]::Name($kv.Key), $kv.Value, [Emu]::frameCnt[$kv.Key]
  }
}
