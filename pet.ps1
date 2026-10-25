param(
  [string]$Image = "",
  [int]$Height = 300,
  [string]$StateDir = "$env:APPDATA\xyz.chatboxapp.app\chatbox-unbound"
)

$ErrorActionPreference = "Stop"

if (-not $Image) { $Image = Join-Path $PSScriptRoot "assets\hero-source.png" }
if (-not (Test-Path $Image)) { Write-Error "找不到图片: $Image"; exit 1 }
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force -Path $StateDir | Out-Null }

$stateFile = Join-Path $StateDir "pet-pos.txt"
$pidFile = Join-Path $StateDir "pet.pid"

$source = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class UnboundPet : Form
{
    [StructLayout(LayoutKind.Sequential)] private struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] private struct SIZE { public int cx; public int cy; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] private struct BLENDFUNCTION { public byte BlendOp; public byte BlendFlags; public byte SourceConstantAlpha; public byte AlphaFormat; }

    [DllImport("user32.dll")] private static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize, IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);
    [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hdc);
    [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();

    private const int WS_EX_LAYERED = 0x80000;
    private const int WS_EX_TOOLWINDOW = 0x80;
    private const int ULW_ALPHA = 0x2;
    private const byte AC_SRC_ALPHA = 0x1;

    private Bitmap source;
    private Bitmap frame;
    private string stateFile;
    private bool dragging;
    private bool moved;
    private Point dragOffset;
    private Point downScreen;
    private ContextMenuStrip menu;
    private Timer animTimer;
    private DateTime animStart;
    private double animFrom = 1.0;
    private double scale = 1.0;
    private Point anchorBottomCenter;
    private int animMs = 520;

    static UnboundPet() { try { SetProcessDPIAware(); } catch { } }

    public UnboundPet(string imagePath, int targetHeight, string stateFile)
    {
        this.stateFile = stateFile;
        Text = "chatbox-unbound-pet";
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;

        using (var src = Image.FromFile(imagePath))
        {
            int w = (int)Math.Round(src.Width * (targetHeight / (double)src.Height));
            source = new Bitmap(w, targetHeight, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(source))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.SmoothingMode = SmoothingMode.HighQuality;
                g.CompositingQuality = CompositingQuality.HighQuality;
                g.DrawImage(src, new Rectangle(0, 0, w, targetHeight));
            }
        }

        menu = new ContextMenuStrip();
        menu.Items.Add("回到右下角", null, delegate { ResetPosition(); });
        var top = new ToolStripMenuItem("总在最前");
        top.Checked = true;
        top.Click += delegate { TopMost = !TopMost; top.Checked = TopMost; };
        menu.Items.Add(top);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("退出宠物", null, delegate { SavePosition(); Close(); });

        animTimer = new Timer();
        animTimer.Interval = 15;
        animTimer.Tick += delegate { StepAnimation(); };

        RestorePosition();
        SetScale(1.0);
    }

    protected override CreateParams CreateParams
    {
        get
        {
            var cp = base.CreateParams;
            cp.ExStyle |= WS_EX_LAYERED | WS_EX_TOOLWINDOW;
            return cp;
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        SetScale(scale);
    }

    private void SetScale(double s)
    {
        scale = s;
        int w = Math.Max(32, (int)Math.Round(source.Width * s));
        int h = Math.Max(32, (int)Math.Round(source.Height * s));
        if (frame != null) { frame.Dispose(); frame = null; }
        frame = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (var g = Graphics.FromImage(frame))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.CompositingQuality = CompositingQuality.HighQuality;
            g.DrawImage(source, new Rectangle(0, 0, w, h));
        }

        if (anchorBottomCenter == Point.Empty)
        {
            anchorBottomCenter = new Point(Left + Width / 2, Top + Height);
        }
        int left = anchorBottomCenter.X - w / 2;
        int top = anchorBottomCenter.Y - h;
        SetBounds(left, top, w, h);
        Render();
    }

    private void Render()
    {
        if (!IsHandleCreated || frame == null) return;
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBitmap = IntPtr.Zero;
        IntPtr oldBitmap = IntPtr.Zero;
        try
        {
            hBitmap = frame.GetHbitmap(Color.FromArgb(0));
            oldBitmap = SelectObject(memDc, hBitmap);
            var size = new SIZE { cx = frame.Width, cy = frame.Height };
            var srcLoc = new POINT { X = 0, Y = 0 };
            var topLoc = new POINT { X = Left, Y = Top };
            var blend = new BLENDFUNCTION { BlendOp = 0, BlendFlags = 0, SourceConstantAlpha = 255, AlphaFormat = AC_SRC_ALPHA };
            UpdateLayeredWindow(Handle, screenDc, ref topLoc, ref size, memDc, ref srcLoc, 0, ref blend, ULW_ALPHA);
        }
        finally
        {
            if (hBitmap != IntPtr.Zero)
            {
                SelectObject(memDc, oldBitmap);
                DeleteObject(hBitmap);
            }
            DeleteDC(memDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    private void StepAnimation()
    {
        double t = (DateTime.UtcNow - animStart).TotalMilliseconds / animMs;
        if (t >= 1.0)
        {
            animTimer.Stop();
            SetScale(1.0);
            anchorBottomCenter = new Point(Left + Width / 2, Top + Height);
            return;
        }
        double amp = animFrom - 1.0;
        double s = 1.0 + amp * Math.Exp(-7.0 * t) * Math.Cos(15.0 * t);
        SetScale(s);
    }

    private void StartBounce(double from)
    {
        animFrom = from;
        animStart = DateTime.UtcNow;
        animTimer.Start();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button == MouseButtons.Right)
        {
            menu.Show(this, e.Location);
            return;
        }
        if (e.Button == MouseButtons.Left)
        {
            dragging = true;
            moved = false;
            downScreen = Cursor.Position;
            dragOffset = new Point(Cursor.Position.X - Left, Cursor.Position.Y - Top);
            anchorBottomCenter = new Point(Left + Width / 2, Top + Height);
            animTimer.Stop();
            SetScale(0.88);
            Capture = true;
        }
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (!dragging) return;
        var pos = Cursor.Position;
        if (Math.Abs(pos.X - downScreen.X) > 3 || Math.Abs(pos.Y - downScreen.Y) > 3) moved = true;
        if (moved)
        {
            Left = pos.X - dragOffset.X;
            Top = pos.Y - dragOffset.Y;
            anchorBottomCenter = new Point(Left + Width / 2, Top + Height);
            Render();
        }
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        if (e.Button != MouseButtons.Left) return;
        dragging = false;
        Capture = false;
        anchorBottomCenter = new Point(Left + Width / 2, Top + Height);
        if (moved)
        {
            SavePosition();
            SetScale(1.0);
            return;
        }
        StartBounce(0.88);
    }

    private void ResetPosition()
    {
        var area = Screen.PrimaryScreen.WorkingArea;
        var vs = SystemInformation.VirtualScreen;
        int w = Math.Max(32, (int)Math.Round(source.Width * scale));
        int h = Math.Max(32, (int)Math.Round(source.Height * scale));
        int x = area.Right - w - 40;
        int y = area.Bottom - h - 20;
        if (x + w > vs.Right - 8) x = vs.Right - w - 8;
        if (y + h > vs.Bottom - 8) y = vs.Bottom - h - 8;
        if (x < vs.Left + 8) x = vs.Left + 8;
        if (y < vs.Top + 8) y = vs.Top + 8;
        anchorBottomCenter = new Point(x + w / 2, y + h);
        SetBounds(x, y, w, h);
        Render();
        SavePosition();
    }

    private void RestorePosition()
    {
        bool ok = false;
        try
        {
            if (File.Exists(stateFile))
            {
                var parts = File.ReadAllText(stateFile).Trim().Split(',');
                int w = Math.Max(32, (int)Math.Round(source.Width * scale));
                int h = Math.Max(32, (int)Math.Round(source.Height * scale));
                int x = int.Parse(parts[0]);
                int y = int.Parse(parts[1]);
                var vs = SystemInformation.VirtualScreen;
                if (x > vs.Left - w && x < vs.Right && y > vs.Top - h && y < vs.Bottom)
                {
                    anchorBottomCenter = new Point(x + w / 2, y + h);
                    SetBounds(x, y, w, h);
                    ok = true;
                }
            }
        }
        catch { }
        if (!ok)
        {
            var area = Screen.PrimaryScreen.WorkingArea;
            int w = Math.Max(32, (int)Math.Round(source.Width * scale));
            int h = Math.Max(32, (int)Math.Round(source.Height * scale));
            anchorBottomCenter = new Point(area.Right - 40 - w / 2, area.Bottom - 20);
            SetBounds(area.Right - 40 - w, area.Bottom - 20 - h, w, h);
        }
    }

    private void SavePosition()
    {
        try { File.WriteAllText(stateFile, Left + "," + Top); } catch { }
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        SavePosition();
        base.OnFormClosing(e);
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies @("System.Drawing", "System.Windows.Forms")
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object UnboundPet -ArgumentList @($Image, $Height, $stateFile)
Set-Content -Path $pidFile -Value $PID -Encoding ascii
try {
  [System.Windows.Forms.Application]::Run($form)
} finally {
  if (Test-Path $pidFile) { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }
}
