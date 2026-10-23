param($n)
$src = (Get-Content "$n\prof\Emu.cs" -Raw) -replace '(?m)^using [^\r\n]+;\r?\n', ''
$src = "using System;using System.Collections.Generic;using System.IO;using System.Text;using System.Linq;`n" + $src
Add-Type -TypeDefinition $src -Language CSharp
[Emu]::LoadHunk("$n\build\d", 0x100000)
[Emu]::A[7] = 0x0c0000; [Emu]::A[6] = 0xdff000; [Emu]::cyc = 0; [Emu]::profile = $true
foreach($r in 'initScroller','initMusic'){ $c0=[Emu]::cyc; [Emu]::frameInc.Clear(); try { [Emu]::Call([Emu]::symByName[$r]) } catch { "ERR $r " + $_.Exception.InnerException.Message }; "{0}: {1:n0} cycles = {2:n2} s at 7.09 MHz" -f $r, ([Emu]::cyc-$c0), (([Emu]::cyc-$c0)/7093790); [Emu]::frameInc.GetEnumerator() | sort Value -Descending | select -First 12 | % { "   " + [Emu]::Name($_.Key) + " " + $_.Value } }
