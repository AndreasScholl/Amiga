param([string]$hd, [string]$mode = "trigger", [int]$timeout = 240, [string[]]$extra = @())
# wall time from FS-UAE start until the program "d" starts (gdbserver trigger) or the emulator quits
$exe = "$env:USERPROFILE\.vscode\extensions\prb28.amiga-assembly-1.8.13\dist\bin\fs-uae\fs-uae-win32_x64.exe"
$log = "C:\Users\konta\FS-UAE\Cache\Logs\fs-uae.log.txt"
$a = @("--hard_drive_0=$hd", "--automatic_input_grab=0") + $extra
if ($mode -eq "trigger") { $a += @("--remote_debugger=200", "--remote_debugger_port=23456", "--remote_debugger_trigger=d") }
$sw = [Diagnostics.Stopwatch]::StartNew()
$p = Start-Process -FilePath $exe -ArgumentList ($a | % { '"' + $_ + '"' }) -WorkingDirectory (Split-Path $exe) -PassThru
$res = "timeout"
while ($sw.Elapsed.TotalSeconds -lt $timeout) {
  Start-Sleep -Milliseconds 100
  if ($p.HasExited) { $res = "beendet"; break }
  if ($mode -eq "trigger") {
    try { $fs = [IO.File]::Open($log, 'Open', 'Read', 'ReadWrite'); $sr = New-Object IO.StreamReader($fs); $txt = $sr.ReadToEnd(); $sr.Close() } catch { continue }
    if ($txt.Contains("GDBSERVER: Waiting for connection")) { $res = "Programmstart"; break }
  }
}
$t = $sw.Elapsed.TotalSeconds
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
"{0}: {1} nach {2:N1} s" -f (Split-Path $hd -Leaf), $res, $t
