param([string]$hunk = "")
# cycles from program start to the first VBL: initScroller (st: initDemoPart) + initMusic
$ErrorActionPreference = 'Stop'
$p = "$PSScriptRoot\prof"
if (-not $hunk) { $hunk = "$PSScriptRoot\build\d" }
$src = (Get-Content "$p\Emu.cs" -Raw) + "`n" + (Get-Content "$p\Seq.cs" -Raw) + "`n" + (Get-Content "$p\Den.cs" -Raw) + "`n" + (Get-Content "$p\Spr.cs" -Raw) + "`n" + (Get-Content "$p\Aud.cs" -Raw) -replace '(?m)^using [^\r\n]+;\r?\n', ''
$src = "using System;using System.Collections.Generic;using System.IO;using System.Text;using System.Linq;`n" + $src
Add-Type -TypeDefinition $src -Language CSharp
[Emu]::LoadHunk($hunk, 0x100000)
[Emu]::A[7] = 0x0c0000; [Emu]::A[6] = 0xdff000; [Emu]::cyc = 0
foreach ($n in "randomize","initScroller","initMusic") {
  if (-not [Emu]::symByName.ContainsKey($n)) { "$n : kein Symbol"; continue }
  if ($n -eq "randomize") { "randomize: OS-Aufrufe, im Harness nicht messbar"; continue }
  [Emu]::ResetStack(); [Emu]::A[6] = 0xdff000
  $c0 = [Emu]::cyc
  try { [Emu]::Call([Emu]::symByName[$n]) } catch { "$n FEHLER: " + $_.Exception.InnerException.Message }
  $d = [Emu]::cyc - $c0
  "{0}: {1:N0} Zyklen = {2:N1} Frames" -f $n, $d, ($d / 141875.0)
}
