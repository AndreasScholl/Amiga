param([string]$dirA, [string]$dirB, [string]$pat = "*.png")
# compares the pictures of two harness runs pixel by pixel (same names)
Add-Type -AssemblyName System.Drawing
$code = @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class PixCmp {
  static int[] Load(string f, out int w, out int h) { using (var A = new Bitmap(f)) { w = A.Width; h = A.Height; var r = A.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb); var x = new int[w * h]; Marshal.Copy(r.Scan0, x, 0, w * h); A.UnlockBits(r); return x; } }
  public static string Cmp(string a, string b) {
    int w, h, w2, h2; var x = Load(a, out w, out h); var y = Load(b, out w2, out h2);
    if (w != w2 || h != h2) return "size differs";
    int d = 0, x0 = 9999, x1 = -1, y0 = 9999, y1 = -1;
    for (int i = 0; i < x.Length; i++) if (x[i] != y[i]) { d++; int px = i % w, py = i / w; x0 = Math.Min(x0, px); x1 = Math.Max(x1, px); y0 = Math.Min(y0, py); y1 = Math.Max(y1, py); }
    return d == 0 ? "identical" : d + " px differ, box x " + x0 + ".." + x1 + " y " + y0 + ".." + y1;
  }
}
'@
$refs = @([System.Drawing.Bitmap].Assembly.Location, [System.Drawing.Rectangle].Assembly.Location, [System.Runtime.InteropServices.Marshal].Assembly.Location)
Add-Type -TypeDefinition $code -ReferencedAssemblies $refs
Get-ChildItem (Join-Path $dirA $pat) | % { $_.Name + ": " + [PixCmp]::Cmp($_.FullName, (Join-Path $dirB $_.Name)) }
