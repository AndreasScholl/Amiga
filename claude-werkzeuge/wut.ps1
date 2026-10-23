param([string]$cfg, [string]$hd, [int]$timeout = 90, [string[]]$extra = @())
# WinUAE (bundled): wall time from start until the emulator quits (startup-sequence runs UAEquit)
$exe = "$env:USERPROFILE\.vscode\extensions\prb28.amiga-assembly-1.8.13\dist\bin\winuae\winuae.exe"
$a = @("-config=$cfg", "-s", "filesystem2=rw,DH0:dh0:$hd,0", "-log") + $extra
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $exe -ArgumentList ($a | % { '"' + $_ + '"' }) -WorkingDirectory (Split-Path $exe) -PassThru
if (-not $p.WaitForExit($timeout * 1000)) { Stop-Process -Id $p.Id -Force; "timeout nach $timeout s" } else { "{0}: beendet nach {1:N1} s" -f (Split-Path $cfg -Leaf), $sw.Elapsed.TotalSeconds }
