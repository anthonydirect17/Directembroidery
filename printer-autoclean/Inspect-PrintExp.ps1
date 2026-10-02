<#
.SYNOPSIS
    READ-ONLY inspector for the PrintExp printer software. Clicks nothing, changes nothing.

.DESCRIPTION
    Collects what is needed to build an automatic head-cleaning script for PrintExp:
      * PrintExp version and install path
      * Every button / control PrintExp exposes to Windows (names, positions, types)
      * Screenshots of the PrintExp window
      * Optional "watch" step: while it watches, YOU click Clean in PrintExp as you normally
        would, and it records any window that pops up (for example a cleaning-options dialog).

    It uses only what ships with Windows (PowerShell 5.1, .NET, UI Automation). Nothing is
    installed, nothing goes online, and no PrintExp setting is touched.

    Output: a folder and a .zip on your Desktop named PrintExp-Inspect-<PC name>-<date>.
    Send the .zip back (from the offline laptop, copy it to a USB stick).

.PARAMETER WatchSeconds
    How long to watch for pop-up windows while you click Clean. Default 60. Use 0 to skip.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Inspect-PrintExp.ps1
#>
[CmdletBinding()]
param(
    [ValidateRange(0, 600)]
    [int]$WatchSeconds = 60,
    [string]$ProcessNamePattern = 'PrintExp*'
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class InspectWin32 {
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, StringBuilder lParam, uint flags, uint timeout, out IntPtr result);

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }

    public static List<IntPtr> TopWindowsOf(uint pid) {
        var list = new List<IntPtr>();
        EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }
    public static List<IntPtr> ChildrenOf(IntPtr parent) {
        var list = new List<IntPtr>();
        EnumChildWindows(parent, (h, l) => { list.Add(h); return true; }, IntPtr.Zero);
        return list;
    }
    public static string Text(IntPtr h) {
        // WM_GETTEXT with a timeout so a busy window cannot hang the inspector.
        var sb = new StringBuilder(512); IntPtr r;
        SendMessageTimeout(h, 0x000D, (IntPtr)512, sb, 0x0002, 1000, out r);
        return sb.ToString();
    }
    public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
}
'@

[void][InspectWin32]::SetProcessDPIAware()

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outDir = Join-Path ([Environment]::GetFolderPath('Desktop')) "PrintExp-Inspect-$env:COMPUTERNAME-$stamp"
New-Item -ItemType Directory -Path $outDir | Out-Null
$report = Join-Path $outDir 'report.txt'
$reportWriter = New-Object System.IO.StreamWriter -ArgumentList $report, $false, ([Text.Encoding]::UTF8)
$reportWriter.AutoFlush = $true

function Out-Report([string]$Text) {
    $reportWriter.WriteLine($Text)
}

function Get-RectText($r) { '{0},{1} {2}x{3}' -f $r.Left, $r.Top, ($r.Right - $r.Left), ($r.Bottom - $r.Top) }

function Save-WindowShot([IntPtr]$Hwnd, [string]$Name) {
    $r = New-Object InspectWin32+RECT
    if ([InspectWin32]::IsIconic($Hwnd)) { Out-Report "  (window $Name is minimized; no screenshot)"; return }
    [void][InspectWin32]::GetWindowRect($Hwnd, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    if ($w -le 0 -or $h -le 0) { return }
    $bmp = New-Object System.Drawing.Bitmap -ArgumentList $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    $ok = [InspectWin32]::PrintWindow($Hwnd, $hdc, 2)
    $g.ReleaseHdc($hdc)
    if (-not $ok) { $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size) }
    $g.Dispose()
    $file = Join-Path $outDir "$Name.png"
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Out-Report "  screenshot: $Name.png"
}

function Save-ScreenShot([string]$Name) {
    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bmp = New-Object System.Drawing.Bitmap -ArgumentList $bounds.Width, $bounds.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bmp.Size)
    $g.Dispose()
    $bmp.Save((Join-Path $outDir "$Name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Get-Patterns($el) {
    $names = @()
    foreach ($p in $el.GetSupportedPatterns()) { $names += ($p.ProgrammaticName -replace 'PatternIdentifiers.Pattern', '') }
    return ($names -join ',')
}

function Write-UiaTree($Root, [string]$Label) {
    Out-Report ''
    Out-Report "=== UI Automation tree: $Label ==="
    $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
    $script:nodeCount = 0
    function Walk($el, [int]$depth) {
        if ($depth -gt 14 -or $script:nodeCount -gt 4000) { return }
        $script:nodeCount++
        try {
            $c = $el.Current
            $r = $c.BoundingRectangle
            $rect = if ($r.IsEmpty) { '-' } else { '{0:N0},{1:N0} {2:N0}x{3:N0}' -f $r.X, $r.Y, $r.Width, $r.Height }
            Out-Report ('{0}[{1}] name="{2}" autoId="{3}" class="{4}" rect={5} enabled={6} offscreen={7} patterns={8} hwnd=0x{9:X}' -f
                ('  ' * $depth), $c.ControlType.ProgrammaticName.Replace('ControlType.', ''), $c.Name, $c.AutomationId, $c.ClassName,
                $rect, $c.IsEnabled, $c.IsOffscreen, (Get-Patterns $el), $c.NativeWindowHandle)
        }
        catch { Out-Report ('{0}(unreadable element: {1})' -f ('  ' * $depth), $_.Exception.Message) }
        $child = $null
        try { $child = $walker.GetFirstChild($el) } catch { }
        while ($child) {
            Walk $child ($depth + 1)
            try { $child = $walker.GetNextSibling($child) } catch { $child = $null }
        }
    }
    Walk $Root 0
}

function Write-Win32Tree([IntPtr]$Hwnd, [string]$Label) {
    Out-Report ''
    Out-Report "=== Win32 child windows: $Label ==="
    foreach ($h in [InspectWin32]::ChildrenOf($Hwnd)) {
        $r = New-Object InspectWin32+RECT
        [void][InspectWin32]::GetWindowRect($h, [ref]$r)
        Out-Report ('hwnd=0x{0:X} parent=0x{1:X} id={2} class="{3}" text="{4}" rect={5} visible={6} enabled={7}' -f
            $h.ToInt64(), ([InspectWin32]::GetParent($h)).ToInt64(), [InspectWin32]::GetDlgCtrlID($h), [InspectWin32]::Cls($h),
            [InspectWin32]::Text($h), (Get-RectText $r), [InspectWin32]::IsWindowVisible($h), [InspectWin32]::IsWindowEnabled($h))
    }
}

function Write-WindowDetails([IntPtr]$Hwnd, [string]$Label) {
    $r = New-Object InspectWin32+RECT
    [void][InspectWin32]::GetWindowRect($Hwnd, [ref]$r)
    Out-Report ''
    Out-Report ('##### WINDOW {0}: hwnd=0x{1:X} title="{2}" class="{3}" rect={4} visible={5} enabled={6} minimized={7}' -f
        $Label, $Hwnd.ToInt64(), [InspectWin32]::Text($Hwnd), [InspectWin32]::Cls($Hwnd), (Get-RectText $r),
        [InspectWin32]::IsWindowVisible($Hwnd), [InspectWin32]::IsWindowEnabled($Hwnd), [InspectWin32]::IsIconic($Hwnd))
    Save-WindowShot $Hwnd $Label
    Write-Win32Tree $Hwnd $Label
    try { Write-UiaTree ([System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)) $Label }
    catch { Out-Report "UI Automation could not read this window: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------

Write-Host 'PrintExp inspector (read-only). Make sure PrintExp is open, connected to the printer, and NOT minimized.' -ForegroundColor Cyan

Out-Report "PrintExp inspector report  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Out-Report "Computer: $env:COMPUTERNAME   User: $env:USERNAME"
$os = Get-CimInstance Win32_OperatingSystem
Out-Report "Windows: $($os.Caption) $($os.Version) build $($os.BuildNumber)   PowerShell: $($PSVersionTable.PSVersion)"
$screens = [System.Windows.Forms.Screen]::AllScreens | ForEach-Object { '{0} {1}x{2}' -f $_.DeviceName, $_.Bounds.Width, $_.Bounds.Height }
Out-Report "Screens: $($screens -join '; ')"
try {
    $sleep = (powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null | Select-String 'Current AC Power Setting Index') -join ' '
    Out-Report "Sleep after (AC, seconds as hex; 0x00000000 = never): $sleep"
}
catch { }

$procs = @(Get-Process | Where-Object { $_.ProcessName -like $ProcessNamePattern })
if ($procs.Count -eq 0) {
    $procs = @(Get-Process | Where-Object { $_.MainWindowTitle -match 'PrintExp|Hoson' })
}
if ($procs.Count -eq 0) {
    Out-Report 'PrintExp is NOT running. Start PrintExp and run this again.'
    Write-Host 'PrintExp is not running. Please open PrintExp (connected to the printer) and run this again.' -ForegroundColor Red
    Write-Host "Report: $report"
    $reportWriter.Close()
    exit 1
}

foreach ($p in $procs) {
    $path = $null; $ver = $null
    try { $path = $p.MainModule.FileName; $ver = $p.MainModule.FileVersionInfo } catch { }
    Out-Report ''
    Out-Report "Process: $($p.ProcessName)  PID $($p.Id)  Path: $path"
    if ($ver) { Out-Report "  FileVersion: $($ver.FileVersion)  ProductVersion: $($ver.ProductVersion)  Product: $($ver.ProductName)  Company: $($ver.CompanyName)  Description: $($ver.FileDescription)" }
    if ($path) {
        $dir = Split-Path $path
        Out-Report "  Files in program folder (top level):"
        Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Select-Object -First 200 | ForEach-Object {
            Out-Report ('    {0,-50} {1,12:N0} bytes  {2}' -f $_.Name, $_.Length, $_.LastWriteTime.ToString('yyyy-MM-dd'))
        }
    }
}

$pidSet = @($procs | ForEach-Object { [uint32]$_.Id })
$seen = @{}
$i = 0
foreach ($procId in $pidSet) {
    foreach ($h in [InspectWin32]::TopWindowsOf($procId)) {
        if (-not [InspectWin32]::IsWindowVisible($h)) { continue }
        $seen[$h.ToInt64()] = $true
        $i++
        Write-WindowDetails $h ("main-{0}" -f $i)
    }
}
Save-ScreenShot 'whole-screen-before'
Write-Host "Recorded $i PrintExp window(s)." -ForegroundColor Green

if ($WatchSeconds -gt 0) {
    Write-Host ''
    Write-Host "WATCH STEP ($WatchSeconds seconds):" -ForegroundColor Yellow
    Write-Host '  1. Click Clean in PrintExp now, exactly as you normally do.' -ForegroundColor Yellow
    Write-Host '  2. If a window pops up, leave it open for 5 seconds so it can be recorded,' -ForegroundColor Yellow
    Write-Host '     then finish the clean as you normally would (or cancel it).' -ForegroundColor Yellow
    Write-Host '  The script only watches and takes screenshots. It does not click.' -ForegroundColor Yellow
    $deadline = (Get-Date).AddSeconds($WatchSeconds)
    $popups = 0
    $shot = 0
    $nextShot = Get-Date
    while ((Get-Date) -lt $deadline) {
        foreach ($procId in $pidSet) {
            foreach ($h in [InspectWin32]::TopWindowsOf($procId)) {
                if ($seen.ContainsKey($h.ToInt64()) -or -not [InspectWin32]::IsWindowVisible($h)) { continue }
                $seen[$h.ToInt64()] = $true
                $popups++
                Start-Sleep -Milliseconds 700   # let the window finish drawing
                Write-WindowDetails $h ("popup-{0}" -f $popups)
                Write-Host "  Recorded pop-up window #$popups." -ForegroundColor Green
            }
        }
        if ((Get-Date) -ge $nextShot -and $shot -lt 6) {
            $shot++
            Save-ScreenShot ("whole-screen-during-{0}" -f $shot)
            $nextShot = (Get-Date).AddSeconds(8)
        }
        Start-Sleep -Milliseconds 300
    }
    Out-Report ''
    Out-Report "Watch step finished: $popups pop-up window(s) recorded."
    # Main window again, to capture any status change after the clean.
    $j = 0
    foreach ($procId in $pidSet) {
        foreach ($h in [InspectWin32]::TopWindowsOf($procId)) {
            if (-not [InspectWin32]::IsWindowVisible($h)) { continue }
            $j++
            Save-WindowShot $h ("after-{0}" -f $j)
        }
    }
}

$reportWriter.Close()
$zip = "$outDir.zip"
Compress-Archive -Path (Join-Path $outDir '*') -DestinationPath $zip -Force
Write-Host ''
Write-Host "Done. Send this file back: $zip" -ForegroundColor Cyan
