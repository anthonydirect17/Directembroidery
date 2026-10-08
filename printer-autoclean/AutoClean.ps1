<#
.SYNOPSIS
    Direct Embroidery DTF printer auto-clean for Hosonsoft PrintExp.
    Runs PrintExp's normal "Clean > <head group> > Normal", only when every safety check passes.
    The head group is "2 head-All" unless machine-settings.json says otherwise.

.DESCRIPTION
    Never clicks by screen position. Acts only on PrintExp controls it has verified by
    control ID and text, and never starts PrintExp.

    Modes
      Discover  Opens the Clean menu, reads its items and command IDs, highlights
                "<head group> > Normal" WITHOUT choosing it, then closes the menu. No clean.
                Saves what it learned to config.json.
      DryRun    Runs every pre-check and takes a screenshot. No clean.
      Clean     Pre-checks, then the clean, then confirms it in PrintExp's own log.
      Scheduled What the scheduled task runs: Clean, unless a fresh request.txt asks for
                another mode (used for testing without an admin prompt each time).
      Install   Creates the daily scheduled task (needs an admin PowerShell).

    Pre-checks (all must pass, otherwise it logs and skips):
      * exactly one PrintExp_X64 running; its version matches config.json
      * main window present, enabled (no dialog blocking it) and responding
      * no other visible PrintExp window (error box, dialog, open menu)
      * status label reads "Device Ready"; Pause and Cancel are disabled (not printing)
      * Clean button: ID 11030, text "Clean", enabled
      * PrintExp has an open network connection to the printer board (port 5001)
      * at least MinHoursBetween since the last automatic clean; one run at a time

    machine-settings.json (optional, for a PrintExp that differs from Machine 2's), e.g.
      { "MenuGroup": "4 head-All", "CleanVid": 57 }
      MenuGroup  Clean menu entry whose sub-menu holds "Clean normal" (default "2 head-All")
      CleanVid   code PrintExp writes to its log when a clean starts, "VID=<n>]" (default 31)

    While a clean runs, PrintExp's log is not opened: the script watches only its size and time
    stamp, and reads it once the clean is over. (Machine 1's 2022 PrintExp dropped log lines when
    the log was read during a clean.)

    Windows PowerShell 5.1, built-in Windows features only. Must run elevated, because
    PrintExp runs elevated and Windows blocks messages from a normal program to it.
#>
[CmdletBinding()]
param(
    [ValidateSet('Discover', 'DryRun', 'Clean', 'Scheduled', 'Install', 'MailSetup', 'MailTest')]
    [string]$Mode = 'DryRun',
    [ValidateSet('Auto', 'Command', 'Menu')]
    [string]$Method = '',
    [double]$MinHoursBetween = 4,
    [int]$NormalPosHint = -1,
    [string[]]$Times = @('09:00', '21:00'),
    [string]$StatusFolder = 'C:\Users\AnthonyDirect\My Drive\Printer AutoClean (DTF)'
)

$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.2.0'
$TaskName = 'Direct Embroidery DTF AutoClean'
$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptPath
$LogDir = Join-Path $ScriptDir 'logs'
$ShotDir = Join-Path $LogDir 'shots'
$StateDir = Join-Path $ScriptDir 'state'
$ConfigFile = Join-Path $ScriptDir 'config.json'
$RequestFile = Join-Path $ScriptDir 'request.txt'
$SettingsFile = Join-Path $ScriptDir 'machine-settings.json'
# Defaults match Machine 2's PrintExp. machine-settings.json overrides them (read in Main).
$MenuGroup = '2 head-All'
$CleanVid = 31
foreach ($d in @($LogDir, $ShotDir, $StateDir)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir ("AutoClean_{0}.log" -f (Get-Date -Format 'yyyyMMdd'))

# Known PrintExp controls (from the 2026-10-07 inspection)
$ID_CLEAN = 11030; $ID_PAUSE = 11027; $ID_CANCEL = 11028; $ID_STATUS = 31028
$WM_COMMAND = 0x0111; $WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101; $WM_CANCELMODE = 0x001F
$VK_DOWN = 0x28; $VK_RIGHT = 0x27; $VK_RETURN = 0x0D; $VK_ESCAPE = 0x1B
$MF_BYPOSITION = 0x400; $MF_HILITE = 0x80; $MF_OWNERDRAW = 0x100; $MF_POPUP = 0x10

Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class AcWin {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW", CharSet = CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeoutText(IntPtr h, uint m, IntPtr w, StringBuilder l, uint f, uint t, out IntPtr r);
    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
    public static extern IntPtr SendMessageTimeoutPtr(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr r);
    [DllImport("user32.dll")] public static extern int GetMenuItemCount(IntPtr m);
    [DllImport("user32.dll")] public static extern uint GetMenuItemID(IntPtr m, int pos);
    [DllImport("user32.dll")] public static extern IntPtr GetSubMenu(IntPtr m, int pos);
    [DllImport("user32.dll")] public static extern uint GetMenuState(IntPtr m, uint id, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetMenuString(IntPtr m, uint id, StringBuilder sb, int n, uint flags);
    [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a, bool i, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern bool QueryFullProcessImageName(IntPtr h, int f, StringBuilder sb, ref int n);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
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
        var sb = new StringBuilder(512); IntPtr r;
        SendMessageTimeoutText(h, 0x000D, (IntPtr)512, sb, 0x0002, 2000, out r);
        return sb.ToString();
    }
    public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
    public static bool Responds(IntPtr h) { IntPtr r; return SendMessageTimeoutPtr(h, 0, IntPtr.Zero, IntPtr.Zero, 0x0002, 2000, out r) != IntPtr.Zero; }
    public static IntPtr MenuOf(IntPtr menuWnd) { IntPtr r; SendMessageTimeoutPtr(menuWnd, 0x01E1, IntPtr.Zero, IntPtr.Zero, 0x0002, 2000, out r); return r; }
    public static string MenuText(IntPtr m, int pos) { var sb = new StringBuilder(256); GetMenuString(m, (uint)pos, sb, 256, 0x400); return sb.ToString(); }
    public static string ImagePath(uint pid) {
        IntPtr h = OpenProcess(0x1000, false, pid);
        if (h == IntPtr.Zero) return "";
        try { var sb = new StringBuilder(1024); int n = 1024; return QueryFullProcessImageName(h, 0, sb, ref n) ? sb.ToString() : ""; }
        finally { CloseHandle(h); }
    }
}
'@
[void][AcWin]::SetProcessDPIAware()

function Write-Log([string]$Message, [string]$Level = 'INFO') {
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# Machine label used in status lines and alert emails (machine-name.txt, else the PC name).
$MachineName = $env:COMPUTERNAME
$MachineFile = Join-Path $ScriptDir 'machine-name.txt'
if (Test-Path $MachineFile) { $mn = (Get-Content $MachineFile -Raw).Trim(); if ($mn) { $MachineName = $mn } }

# ---------------------------------------------------------------------------
# Alert email through Microsoft 365 (Graph, delegated Mail.Send, sign-in once with -Mode MailSetup).
# The refresh token is kept in state\mail-token.dat, encrypted for this Windows user (DPAPI).
# alert-email.txt holds the address(es) to send to, one per line.
# ---------------------------------------------------------------------------
$MailClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'   # Microsoft Graph Command Line Tools (public client)
$MailScopes = 'https://graph.microsoft.com/Mail.Send offline_access openid profile'
$LoginUrl = 'https://login.microsoftonline.com/organizations/oauth2/v2.0'
$MailTokenFile = Join-Path $StateDir 'mail-token.dat'
$AlertToFile = Join-Path $ScriptDir 'alert-email.txt'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Save-MailToken($Resp) {
    if ($Resp.PSObject.Properties['refresh_token'] -and $Resp.refresh_token) {
        Set-Content -Path $MailTokenFile -Value (ConvertTo-SecureString -String $Resp.refresh_token -AsPlainText -Force | ConvertFrom-SecureString) -Encoding ASCII
    }
}

function Get-MailAccessToken {
    if (-not (Test-Path $MailTokenFile)) { throw 'Alert email is not set up (run -Mode MailSetup).' }
    $sec = ConvertTo-SecureString -String (Get-Content $MailTokenFile -Raw).Trim()
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $refresh = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    # Retry: right after a new sign-in Microsoft can briefly refuse the token (permission still applying).
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $resp = Invoke-RestMethod -Method Post -Uri "$LoginUrl/token" -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 30 -Body @{
                client_id = $MailClientId; grant_type = 'refresh_token'; refresh_token = $refresh; scope = $MailScopes }
            Save-MailToken $resp
            return $resp.access_token
        }
        catch {
            $detail = $_.Exception.Message
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try { $e = $_.ErrorDetails.Message | ConvertFrom-Json; $detail = "$($e.error): $(($e.error_description -split "`r?`n")[0])" } catch { $detail = $_.ErrorDetails.Message }
            }
            Write-Log "Email sign-in token attempt $attempt failed: $detail" 'WARN'
            if ($attempt -eq 3) { throw "Email sign-in failed: $detail" }
            Start-Sleep -Seconds (5 * $attempt)
        }
    }
}

function Start-MailSignIn {
    # Browser sign-in (auth code + PKCE, loopback redirect). Sign in as direct@sarasotashirts.com.
    $b64 = { param($bytes) [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
    $verifier = & $b64 ([Guid]::NewGuid().ToByteArray() + [Guid]::NewGuid().ToByteArray() + [Guid]::NewGuid().ToByteArray())
    $challenge = & $b64 ([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier)))
    $state = [Guid]::NewGuid().ToString('N')
    $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([Net.IPAddress]::Loopback), 0
    $listener.Start()
    $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $redirect = "http://localhost:$port"
    $url = "$LoginUrl/authorize?client_id=$MailClientId&response_type=code&redirect_uri=$([Uri]::EscapeDataString($redirect))" +
        "&scope=$([Uri]::EscapeDataString($MailScopes))&state=$state&code_challenge=$challenge&code_challenge_method=S256&prompt=select_account"
    Write-Log 'Opening the browser to sign in for alert emails (sign in as direct@sarasotashirts.com)...'
    Write-Host "If no browser opens, paste this link into one:`n$url`n"
    try { Start-Process $url } catch { }
    $code = $null; $err = $null; $deadline = (Get-Date).AddMinutes(10)
    try {
        while ((Get-Date) -lt $deadline -and -not $code -and -not $err) {
            if (-not $listener.Pending()) { Start-Sleep -Milliseconds 200; continue }
            $client = $listener.AcceptTcpClient()
            try {
                $stream = $client.GetStream(); $stream.ReadTimeout = 5000
                $reader = New-Object System.IO.StreamReader -ArgumentList $stream, ([Text.Encoding]::ASCII), $false, 8192, $true
                $line = $reader.ReadLine()
                $q = @{}
                if ($line -and $line.Split(' ')[1].Contains('?')) {
                    foreach ($pair in $line.Split(' ')[1].Split('?', 2)[1].Split('&')) { $kv = $pair.Split('=', 2); if ($kv.Count -eq 2) { $q[$kv[0]] = [Uri]::UnescapeDataString($kv[1].Replace('+', ' ')) } }
                }
                $msg = 'Waiting for sign-in...'
                if ($q['state'] -eq $state) {
                    if ($q['error']) { $err = "$($q['error']): $($q['error_description'])"; $msg = "Sign-in failed: $err" }
                    elseif ($q['code']) { $code = $q['code']; $msg = 'Signed in. You can close this tab.' }
                }
                $html = "<html><body style='font-family:sans-serif'><h3>DTF printer alert email</h3><p>$([Net.WebUtility]::HtmlEncode($msg))</p></body></html>"
                $bytes = [Text.Encoding]::UTF8.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $([Text.Encoding]::UTF8.GetByteCount($html))`r`nConnection: close`r`n`r`n$html")
                $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
            }
            catch { }
            finally { $client.Close() }
        }
    }
    finally { $listener.Stop() }
    if ($err) { throw "Sign-in failed: $err" }
    if (-not $code) { throw 'Sign-in timed out after 10 minutes.' }
    $resp = Invoke-RestMethod -Method Post -Uri "$LoginUrl/token" -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 30 -Body @{
        client_id = $MailClientId; grant_type = 'authorization_code'; code = $code; redirect_uri = $redirect; code_verifier = $verifier; scope = $MailScopes }
    Save-MailToken $resp
    Write-Log 'Alert email sign-in saved (encrypted for this Windows user).'
}

function Send-AlertMail([string]$Subject, [string]$Text) {
    if (-not (Test-Path $AlertToFile)) { throw 'alert-email.txt is missing.' }
    $to = @(Get-Content $AlertToFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[^@\s]+@[^@\s]+$' })
    if ($to.Count -eq 0) { throw 'alert-email.txt has no address.' }
    $recipients = @($to | ForEach-Object { @{ emailAddress = @{ address = $_ } } })
    $msg = @{ message = @{ subject = $Subject; body = @{ contentType = 'Text'; content = $Text }; toRecipients = $recipients }; saveToSentItems = $true }
    $json = $msg | ConvertTo-Json -Depth 8
    $token = Get-MailAccessToken
    [void](Invoke-RestMethod -Method Post -Uri 'https://graph.microsoft.com/v1.0/me/sendMail' -Headers @{ Authorization = "Bearer $token" } `
            -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 30)
    Write-Log "Alert email sent to $($to -join ', ')."
}

function Write-Status([string]$Result) {
    # One line per run in the Drive folder, so it can be checked from a phone.
    try {
        if (Test-Path -LiteralPath $StatusFolder) {
            $f = Join-Path $StatusFolder "status_$env:COMPUTERNAME.txt"
            Add-Content -LiteralPath $f -Value ('{0}  {1}  {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $MachineName, $Result) -Encoding UTF8
        }
    }
    catch { Write-Log "Could not write the Drive status line: $($_.Exception.Message)" 'WARN' }
    # Email on anything other than PASS / OK: a cap problem, a failed clean, or a run that could not clean.
    if ($Result -notmatch '^\S+\s+(PASS|OK)\b' -and (Test-Path $MailTokenFile)) {
        $kind = 'problem'; if ($Result -match '\b(ALERT|FAIL|SKIP|ERROR|CHECK|WARN)\b') { $kind = $Matches[1] }
        $subject = '{0} DTF printer: {1}' -f $MachineName, $kind
        $text = "$MachineName DTF printer auto-clean, $(Get-Date -Format 'yyyy-MM-dd HH:mm')`r`n`r`n$Result`r`n`r`n" +
            "What it means:`r`n" +
            "ALERT = the clean ran but the capping station did not report back up normally, or PrintExp logged an error. Have someone check that the heads are capped.`r`n" +
            "FAIL or ERROR = the clean did not run.`r`n" +
            "SKIP = the clean was skipped for the reason above (for example PrintExp closed, a dialog open, or the printer not connected).`r`n`r`n" +
            "Log on the PC: $LogFile"
        try { Send-AlertMail $subject $text } catch { Write-Log "Alert email failed: $($_.Exception.Message)" 'WARN' }
    }
}

function Save-Shot([IntPtr]$Hwnd, [string]$Name, [switch]$FromScreen) {
    try {
        $r = New-Object AcWin+RECT
        [void][AcWin]::GetWindowRect($Hwnd, [ref]$r)
        $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
        if ($w -le 0 -or $h -le 0) { return }
        $bmp = New-Object System.Drawing.Bitmap -ArgumentList $w, $h
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        if ($FromScreen) { $g.CopyFromScreen($r.Left, $r.Top, 0, 0, $bmp.Size) }
        else { $hdc = $g.GetHdc(); [void][AcWin]::PrintWindow($Hwnd, $hdc, 2); $g.ReleaseHdc($hdc) }
        $g.Dispose()
        $file = Join-Path $ShotDir ("{0}_{1}.png" -f $Stamp, $Name)
        $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        Write-Log "Screenshot: $file"
    }
    catch { Write-Log "Screenshot $Name failed: $($_.Exception.Message)" 'WARN' }
}

function Send-Key([IntPtr]$Hwnd, [int]$Vk) {
    [void][AcWin]::PostMessage($Hwnd, $WM_KEYDOWN, [IntPtr]$Vk, [IntPtr]1)
    [void][AcWin]::PostMessage($Hwnd, $WM_KEYUP, [IntPtr]$Vk, [IntPtr]([int]0xC0000001 -band 0xC0000001))
    Start-Sleep -Milliseconds 400
}

function Get-MenuWindows([uint32]$ProcId) {
    @([AcWin]::TopWindowsOf($ProcId) | Where-Object { [AcWin]::IsWindowVisible($_) -and [AcWin]::Cls($_) -eq '#32768' })
}

function Close-Menus([uint32]$ProcId, [IntPtr]$Owner) {
    for ($k = 0; $k -lt 6; $k++) {
        $open = Get-MenuWindows $ProcId
        if ($open.Count -eq 0) { return $true }
        Send-Key $open[-1] $VK_ESCAPE
    }
    [void][AcWin]::PostMessage($Owner, $WM_CANCELMODE, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 500
    return ((Get-MenuWindows $ProcId).Count -eq 0)
}

function Read-MenuTree([IntPtr]$HMenu) {
    $items = @()
    $n = [AcWin]::GetMenuItemCount($HMenu)
    for ($p = 0; $p -lt $n; $p++) {
        $st = [AcWin]::GetMenuState($HMenu, [uint32]$p, $MF_BYPOSITION)
        $sub = [AcWin]::GetSubMenu($HMenu, $p)
        $items += [pscustomobject]@{
            Pos = $p; Text = [AcWin]::MenuText($HMenu, $p); Id = [AcWin]::GetMenuItemID($HMenu, $p)
            Hilite = [bool]($st -band $MF_HILITE); OwnerDraw = [bool]($st -band $MF_OWNERDRAW); SubMenu = $sub
        }
    }
    return , $items
}

# ---------------------------------------------------------------------------
# PrintExp state
# ---------------------------------------------------------------------------

function Get-PrintExp {
    # Returns a state object with every check result. Ok = all safety checks passed.
    $s = [ordered]@{ Ok = $false; Reasons = @(); Proc = $null; Path = ''; Version = ''; Main = [IntPtr]::Zero
        Clean = [IntPtr]::Zero; Toolbar = [IntPtr]::Zero; Status = ''; Minimized = $false; Board = '-' }
    $procs = @(Get-Process -Name 'PrintExp_X64' -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { $s.Reasons += 'PrintExp is not running'; return [pscustomobject]$s }
    if ($procs.Count -gt 1) { $s.Reasons += "$($procs.Count) copies of PrintExp are running"; return [pscustomobject]$s }
    $p = $procs[0]; $s.Proc = $p
    $s.Path = [AcWin]::ImagePath([uint32]$p.Id)
    if ($s.Path) { $fi = Get-Item -LiteralPath $s.Path; $s.Version = '{0} / {1} bytes' -f $fi.VersionInfo.FileVersion, $fi.Length }

    $tops = @([AcWin]::TopWindowsOf([uint32]$p.Id) | Where-Object { [AcWin]::IsWindowVisible($_) })
    $mains = @($tops | Where-Object { [AcWin]::Cls($_) -eq '#32770' -and [AcWin]::Text($_) -eq 'PrintExp' })
    if ($mains.Count -ne 1) { $s.Reasons += "found $($mains.Count) PrintExp main windows (expected 1)"; return [pscustomobject]$s }
    $main = $mains[0]; $s.Main = $main
    $others = @($tops | Where-Object { $_ -ne $main })
    foreach ($o in $others) { $s.Reasons += ('another PrintExp window is open: class "{0}" title "{1}"' -f [AcWin]::Cls($o), [AcWin]::Text($o)) }
    if (-not [AcWin]::IsWindowEnabled($main)) { $s.Reasons += 'main window is disabled (a dialog is open)' }
    if (-not [AcWin]::Responds($main)) { $s.Reasons += 'PrintExp is not responding' }
    $s.Minimized = [AcWin]::IsIconic($main)

    $kids = [AcWin]::ChildrenOf($main)
    $byId = @{}
    foreach ($k in $kids) { $id = [AcWin]::GetDlgCtrlID($k); if (-not $byId.ContainsKey($id)) { $byId[$id] = @() }; $byId[$id] += $k }

    $cleans = @($byId[$ID_CLEAN] | Where-Object { $_ -and [AcWin]::Cls($_) -eq 'Button' -and [AcWin]::Text($_) -eq 'Clean' })
    if ($cleans.Count -ne 1) { $s.Reasons += "Clean button not found exactly once (found $($cleans.Count))" }
    else {
        $s.Clean = $cleans[0]; $s.Toolbar = [AcWin]::GetParent($cleans[0])
        if (-not [AcWin]::IsWindowEnabled($s.Clean)) { $s.Reasons += 'Clean button is disabled' }
    }
    foreach ($pair in @(@($ID_PAUSE, 'Pause'), @($ID_CANCEL, 'Cancel'))) {
        $b = @($byId[$pair[0]] | Where-Object { $_ -and [AcWin]::Text($_) -eq $pair[1] })
        if ($b.Count -ne 1) { $s.Reasons += "$($pair[1]) button not found" }
        elseif ([AcWin]::IsWindowEnabled($b[0])) { $s.Reasons += "$($pair[1]) button is active (a print is running)" }
    }
    $st = @($byId[$ID_STATUS])
    if ($st.Count -ge 1) { $s.Status = [AcWin]::Text($st[0]) }
    if ($s.Status -ne 'Device Ready') { $s.Reasons += "status reads '$($s.Status)' (need 'Device Ready')" }

    $tcp = @(Get-NetTCPConnection -OwningProcess $p.Id -RemotePort 5001 -State Established -ErrorAction SilentlyContinue)
    if ($tcp.Count -eq 0) { $s.Reasons += 'no network connection from PrintExp to the printer board (port 5001)' }
    else { $s.Board = $tcp[0].RemoteAddress }

    $s.Ok = ($s.Reasons.Count -eq 0)
    return [pscustomobject]$s
}

function Get-PrintExpLogLines([string]$ExePath) {
    $f = Join-Path (Split-Path $ExePath) ("Log\Log[{0}].txt" -f (Get-Date -Format 'yyyy_MM_dd'))
    if (-not [IO.File]::Exists($f)) { return , @() }
    $fs = [IO.File]::Open($f, 'Open', 'Read', 'ReadWrite')
    try {
        $sr = New-Object IO.StreamReader -ArgumentList $fs, ([Text.Encoding]::GetEncoding(936))
        $lines = @($sr.ReadToEnd() -split "`r?`n" | Where-Object { $_.Trim() })
        $sr.Dispose()
    }
    finally { $fs.Dispose() }
    return , $lines
}

function Wait-CleanConfirmed([string]$ExePath, [int]$Baseline, [int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
        $now = Get-PrintExpLogLines $ExePath
        if ($now.Count -gt $Baseline) {
            $new = @($now[$Baseline..($now.Count - 1)])
            if (@($new | Where-Object { $_ -match ('VID={0}\]' -f $CleanVid) }).Count -gt 0) { return , $new }
        }
    }
    return $null
}

function Wait-LogQuiet([string]$ExePath, [int]$MinSeconds, [int]$QuietSeconds, [int]$MaxSeconds) {
    # Waits until PrintExp's log has not changed for QuietSeconds (and at least MinSeconds have passed).
    # Looks only at the file's size and time stamp, never opens it, so PrintExp can always write to it.
    $f = Join-Path (Split-Path $ExePath) ("Log\Log[{0}].txt" -f (Get-Date -Format 'yyyy_MM_dd'))
    $sig = { $fi = New-Object IO.FileInfo -ArgumentList $f; if ($fi.Exists) { '{0}/{1}' -f $fi.Length, $fi.LastWriteTimeUtc.Ticks } else { '' } }
    $start = Get-Date; $quietSince = $start; $last = & $sig
    while (((Get-Date) - $start).TotalSeconds -lt $MaxSeconds) {
        Start-Sleep -Seconds 2
        $now = & $sig
        if ($now -ne $last) { $last = $now; $quietSince = Get-Date }
        if (((Get-Date) - $start).TotalSeconds -ge $MinSeconds -and ((Get-Date) - $quietSince).TotalSeconds -ge $QuietSeconds) { return }
    }
    Write-Log "PrintExp log still changing after $MaxSeconds s; reading it anyway." 'WARN'
}

function Open-CleanMenu($S) {
    # Same message the Clean button sends to its panel when clicked (BN_CLICKED). No mouse.
    $wParam = [IntPtr]($ID_CLEAN -band 0xFFFF)
    [void][AcWin]::PostMessage($S.Toolbar, $WM_COMMAND, $wParam, $S.Clean)
    for ($k = 0; $k -lt 20; $k++) {
        Start-Sleep -Milliseconds 250
        $m = Get-MenuWindows ([uint32]$S.Proc.Id)
        if ($m.Count -ge 1) { return $m[0] }
    }
    return [IntPtr]::Zero
}

# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

function Invoke-Discover {
    $s = Get-PrintExp
    Write-Log ("PrintExp: {0}  version {1}  status '{2}'" -f $s.Path, $s.Version, $s.Status)
    if (-not $s.Ok) { foreach ($r in $s.Reasons) { Write-Log "Check failed: $r" 'WARN' }; Write-Log 'Discover stopped before touching PrintExp.' 'WARN'; return 'SKIP discover: ' + ($s.Reasons -join '; ') }
    Save-Shot $s.Main 'discover-before'
    $menuWnd = Open-CleanMenu $s
    if ($menuWnd -eq [IntPtr]::Zero) { Write-Log 'The Clean menu did not appear.' 'ERROR'; return 'FAIL discover: menu did not appear' }
    $result = 'FAIL discover'
    try {
        Start-Sleep -Milliseconds 300
        Save-Shot $menuWnd 'discover-menu1' -FromScreen
        $root = [AcWin]::MenuOf($menuWnd)
        $l1 = Read-MenuTree $root
        Write-Log ("Clean menu: {0} items" -f $l1.Count)
        foreach ($i in $l1) {
            Write-Log ("  [{0}] '{1}' id={2} ownerdraw={3} submenu={4}" -f $i.Pos, $i.Text, [long]$i.Id, $i.OwnerDraw, ($i.SubMenu -ne [IntPtr]::Zero))
            if ($i.SubMenu -ne [IntPtr]::Zero) {
                foreach ($j in (Read-MenuTree $i.SubMenu)) { Write-Log ("      [{0}] '{1}' id={2} ownerdraw={3}" -f $j.Pos, $j.Text, [long]$j.Id, $j.OwnerDraw) }
            }
        }
        # Find <head group> > Normal by text (positions as a fallback check only).
        $all = @($l1 | Where-Object { $_.Text -match ('^\s*' + [regex]::Escape($MenuGroup)) })
        if ($all.Count -ne 1) { Write-Log "Could not find '$MenuGroup' exactly once by name (found $($all.Count); menu text may be owner-drawn)." 'WARN'; return "CHECK discover: '$MenuGroup' not found once in the Clean menu, see log and screenshots" }
        # Open the head group sub-menu by keyboard (nothing is chosen) so its items are drawn and can be read.
        Send-Key $menuWnd $VK_DOWN
        for ($k = 0; $k -lt $all[0].Pos; $k++) { Send-Key $menuWnd $VK_DOWN }
        Send-Key $menuWnd $VK_RIGHT
        Start-Sleep -Milliseconds 500
        $subWnd = @(Get-MenuWindows ([uint32]$s.Proc.Id) | Where-Object { [AcWin]::MenuOf($_) -eq $all[0].SubMenu })
        Write-Log ("$MenuGroup sub-menu window open: {0}" -f ($subWnd.Count -eq 1))
        if ($subWnd.Count -eq 1) { Save-Shot $subWnd[0] 'discover-submenu' -FromScreen }
        $subItems = Read-MenuTree $all[0].SubMenu
        foreach ($j in $subItems) { Write-Log ("  sub [{0}] '{1}' id={2} highlighted={3}" -f $j.Pos, $j.Text, [long]$j.Id, $j.Hilite) }
        $normal = @($subItems | Where-Object { $_.Text -match '^\s*Normal' })
        if ($normal.Count -ne 1 -and $NormalPosHint -ge 0 -and $NormalPosHint -lt $subItems.Count) {
            # Item text is drawn as a picture; position confirmed by a person from the screenshot.
            $normal = @($subItems[$NormalPosHint])
            Write-Log "Using position $NormalPosHint for 'Normal' (confirmed from the sub-menu screenshot)."
        }
        if ($normal.Count -ne 1) { Write-Log "Could not identify 'Normal' under '$MenuGroup' by text. See the discover-submenu screenshot." 'WARN'; return 'CHECK discover: Normal not identified, see screenshot' }
        Write-Log ("Target: '$MenuGroup' (position {0}) > '{1}' (position {2}), command ID {3}" -f $all[0].Pos, $normal[0].Text, $normal[0].Pos, [long]$normal[0].Id)

        $kbOk = $false
        if ($subWnd.Count -eq 1) {
            for ($k = 0; $k -lt 8; $k++) {
                $now = Read-MenuTree $all[0].SubMenu
                if ($now[$normal[0].Pos].Hilite) { $kbOk = $true; break }
                Send-Key $subWnd[0] $VK_DOWN
            }
            Save-Shot $subWnd[0] 'discover-menu2' -FromScreen
        }
        Write-Log ("Keyboard path to highlight '$MenuGroup > Normal': {0}" -f $(if ($kbOk) { 'works' } else { 'did NOT work' }))

        $cfg = [ordered]@{
            Discovered = (Get-Date -Format 's'); PrintExpPath = $s.Path; PrintExpVersion = $s.Version
            AllPos = $all[0].Pos; NormalPos = $normal[0].Pos; NormalText = $normal[0].Text
            CommandId = [long]$normal[0].Id; KeyboardPathWorks = $kbOk; Method = 'Auto'
            MenuGroup = $MenuGroup; TopCount = $l1.Count
        }
        if (Test-Path $ConfigFile) {
            $old = Get-Content $ConfigFile -Raw | ConvertFrom-Json
            if ($old.PSObject.Properties['Method'] -and $old.CommandId -eq $cfg.CommandId) { $cfg.Method = $old.Method }
        }
        $cfg | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding ASCII
        Write-Log "Saved $ConfigFile"
        $result = "OK discover: $MenuGroup > Normal = command $($cfg.CommandId), keyboard path $(if ($kbOk) { 'ok' } else { 'not ok' })"
    }
    finally {
        $closed = Close-Menus ([uint32]$s.Proc.Id) $s.Toolbar
        Write-Log ("Menu closed without choosing anything: {0}" -f $closed)
        Start-Sleep -Seconds 1
        Save-Shot $s.Main 'discover-after'
    }
    return $result
}

function Invoke-Clean([switch]$Dry) {
    $s = Get-PrintExp
    Write-Log ("PrintExp: {0}  version {1}  status '{2}'  board {3}  minimized {4}" -f $s.Path, $s.Version, $s.Status,
        $s.Board, $s.Minimized)

    $cfg = $null
    if (Test-Path $ConfigFile) { $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json }
    $reasons = @($s.Reasons)
    if (-not $cfg) { $reasons += 'config.json missing: run Discover first' }
    elseif ($s.Path -and ($cfg.PrintExpPath -ne $s.Path -or $cfg.PrintExpVersion -ne $s.Version)) {
        $reasons += "PrintExp changed since Discover (now $($s.Version) at $($s.Path)): run Discover again"
    }
    if ($cfg -and $cfg.PSObject.Properties['MenuGroup'] -and $cfg.MenuGroup -ne $MenuGroup) {
        $reasons += "machine-settings.json head group '$MenuGroup' differs from Discover's '$($cfg.MenuGroup)': run Discover again"
    }
    $lastFile = Join-Path $StateDir 'last-clean.txt'
    if (-not $Dry -and (Test-Path $lastFile)) {
        $last = [datetime]::Parse((Get-Content $lastFile -Raw).Trim(), [Globalization.CultureInfo]::InvariantCulture)
        $hours = ((Get-Date) - $last).TotalHours
        if ($hours -lt $MinHoursBetween) { $reasons += ('last automatic clean was {0:N1} h ago (minimum {1} h)' -f $hours, $MinHoursBetween) }
    }
    if ($reasons.Count -gt 0) {
        foreach ($r in $reasons) { Write-Log "Check failed: $r" 'WARN' }
        Write-Log 'Skipped. Nothing was sent to PrintExp.' 'WARN'
        return ('SKIP ' + ($reasons -join '; '))
    }
    Write-Log 'All pre-checks passed.'
    Save-Shot $s.Main 'before'
    if ($Dry) { Write-Log 'Dry run: no clean.'; return 'OK dry run: all checks passed' }

    $use = $Method
    if (-not $use) { $use = [string]$cfg.Method }
    if (-not $use) { $use = 'Auto' }
    $baseline = (Get-PrintExpLogLines $s.Path).Count
    $confirmed = $null
    $how = ''

    if ($use -eq 'Command' -or $use -eq 'Auto') {
        # The same message PrintExp gets when you pick "Normal" in the menu, sent to the panel that owns the menu.
        Write-Log ("Sending menu command {0} ($MenuGroup > Normal) to the Clean button's panel." -f $cfg.CommandId)
        [void][AcWin]::PostMessage($s.Toolbar, $WM_COMMAND, [IntPtr]([int]$cfg.CommandId -band 0xFFFF), [IntPtr]::Zero)
        $confirmed = Wait-CleanConfirmed $s.Path $baseline 20
        if ($confirmed) { $how = 'Command' }
        else { Write-Log 'No clean seen in the PrintExp log after the menu command.' 'WARN' }
    }
    if (-not $confirmed -and ($use -eq 'Menu' -or $use -eq 'Auto')) {
        if ($use -eq 'Auto') {
            # Make sure nothing started late before trying the second way.
            $late = Wait-CleanConfirmed $s.Path $baseline 10
            if ($late) { $confirmed = $late; $how = 'Command' }
        }
        if (-not $confirmed) {
            $s2 = Get-PrintExp
            if (-not $s2.Ok) { Write-Log ('Checks failed before the menu path: ' + ($s2.Reasons -join '; ')) 'ERROR'; return 'FAIL ' + ($s2.Reasons -join '; ') }
            Write-Log "Opening the Clean menu and choosing $MenuGroup > Normal by keyboard (verified highlight)."
            $menuWnd = Open-CleanMenu $s2
            if ($menuWnd -eq [IntPtr]::Zero) { Write-Log 'Clean menu did not appear.' 'ERROR'; return 'FAIL menu did not appear' }
            $root = [AcWin]::MenuOf($menuWnd)
            $l1 = Read-MenuTree $root
            $allSub = [AcWin]::GetSubMenu($root, [int]$cfg.AllPos)
            # Older config.json files (Machine 2, v1.0 Discover) have no MenuGroup / TopCount: 2 head-All, 3 items.
            $topCount = 3; if ($cfg.PSObject.Properties['TopCount']) { $topCount = [int]$cfg.TopCount }
            $group = '2 head-All'; if ($cfg.PSObject.Properties['MenuGroup']) { $group = [string]$cfg.MenuGroup }
            $okStruct = ($l1.Count -eq $topCount -and $allSub -ne [IntPtr]::Zero -and $l1[[int]$cfg.AllPos].Text -match ('^\s*' + [regex]::Escape($group)))
            $subItems = if ($allSub -ne [IntPtr]::Zero) { Read-MenuTree $allSub } else { @() }
            if ($okStruct) { $okStruct = ($subItems.Count -gt [int]$cfg.NormalPos -and $subItems[[int]$cfg.NormalPos].Text -eq $cfg.NormalText -and [long]$subItems[[int]$cfg.NormalPos].Id -eq [long]$cfg.CommandId) }
            if (-not $okStruct) { [void](Close-Menus ([uint32]$s2.Proc.Id) $s2.Toolbar); Write-Log 'Menu does not match what Discover saw. Closed it; nothing chosen.' 'ERROR'; return 'FAIL menu changed, nothing chosen' }
            for ($k = 0; $k -le [int]$cfg.AllPos; $k++) { Send-Key $menuWnd $VK_DOWN }
            Send-Key $menuWnd $VK_RIGHT
            $subWnd = @(Get-MenuWindows ([uint32]$s2.Proc.Id) | Where-Object { [AcWin]::MenuOf($_) -eq $allSub })
            $hl = $false
            if ($subWnd.Count -eq 1) {
                for ($k = 0; $k -lt 8; $k++) {
                    $now = Read-MenuTree $allSub
                    $others = @($now | Where-Object { $_.Hilite -and $_.Pos -ne [int]$cfg.NormalPos })
                    if ($now[[int]$cfg.NormalPos].Hilite -and $others.Count -eq 0) { $hl = $true; break }
                    Send-Key $subWnd[0] $VK_DOWN
                }
            }
            if (-not $hl) { [void](Close-Menus ([uint32]$s2.Proc.Id) $s2.Toolbar); Write-Log 'Could not highlight Normal. Closed the menu; nothing chosen.' 'ERROR'; return 'FAIL could not highlight Normal' }
            Send-Key $subWnd[0] $VK_RETURN
            # Leave PrintExp's log alone while the clean runs (a normal clean takes 54 to 83 s), then read it once.
            Write-Log 'Normal chosen. Waiting for the clean to finish before reading the PrintExp log.'
            Wait-LogQuiet $s2.Path 90 30 300
            $now = Get-PrintExpLogLines $s2.Path
            if ($now.Count -gt $baseline) {
                $newLines = @($now[$baseline..($now.Count - 1)])
                $vidAt = -1
                for ($k = 0; $k -lt $newLines.Count; $k++) { if ($newLines[$k] -match ('VID={0}\]' -f $CleanVid)) { $vidAt = $k; break } }
                if ($vidAt -ge 0) { $confirmed = @($newLines[0..$vidAt]); $how = 'Menu' }
            }
            if ((Get-MenuWindows ([uint32]$s2.Proc.Id)).Count -gt 0) { [void](Close-Menus ([uint32]$s2.Proc.Id) $s2.Toolbar) }
        }
    }

    if (-not $confirmed) {
        Write-Log 'FAIL: PrintExp did not log a clean.' 'ERROR'
        Save-Shot $s.Main 'after'
        return 'FAIL no clean seen in PrintExp log'
    }
    Write-Log "Clean started (method: $how). PrintExp log:"
    foreach ($l in $confirmed) { Write-Log "  PrintExp: $l" }
    (Get-Date).ToString('s') | Set-Content -Path $lastFile -Encoding ASCII
    if ($use -eq 'Auto' -and $cfg.Method -ne $how) {
        $cfg.Method = $how
        $cfg | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding ASCII
        Write-Log "Saved method '$how' for future runs."
    }

    # Wait for the capping station to settle and the printer to report ready again.
    # (A normal clean on 2026-10-07 took 54 s with pauses up to 13 s between cap moves.)
    Wait-LogQuiet $s.Path 0 30 240
    $after = Get-PrintExp
    $all = Get-PrintExpLogLines $s.Path
    $new = @($all[$baseline..($all.Count - 1)])

    # Capping station check, from the printer's own limit-switch reports in PrintExp's log:
    #   "ink stack lowering, finding lower limit"   = \u58A8\u6808\u4E0B\u964D (cap down)
    #   "ink stack has left the limit"              = \u58A8\u6808\u79BB\u5F00\u9650\u4F4D (cap back up, switch confirmed)
    # Normal clean on this printer: 10 down, 10 up, last cap line = back up. Error words: timeout, failed, error, abnormal.
    $capLines = @($new | Where-Object { $_ -match 'MoveToLimit' })
    $downs = @($capLines | Where-Object { $_ -match '\u58A8\u6808\u4E0B\u964D' }).Count
    $ups = @($capLines | Where-Object { $_ -match '\u58A8\u6808\u79BB\u5F00\u9650\u4F4D' }).Count
    $endsUp = ($capLines.Count -gt 0 -and $capLines[-1] -match '\u58A8\u6808\u79BB\u5F00\u9650\u4F4D')
    $errs = @($new | Where-Object { $_ -match '\u8D85\u65F6|\u5931\u8D25|\u9519\u8BEF|\u5F02\u5E38|(?i)error|fail|timeout' })
    Write-Log ("After clean: status '{0}', cap down {1}, cap up confirmed {2}, ended with cap up: {3}, error lines: {4}" -f $after.Status, $downs, $ups, $endsUp, $errs.Count)
    foreach ($e in $errs) { Write-Log "  PrintExp error line: $e" 'WARN' }
    Save-Shot $s.Main 'after'

    $problems = @()
    if ($downs -eq 0) { $problems += 'no cap movement logged' }
    if ($downs -ne $ups) { $problems += "cap went down $downs times but only $ups rises were confirmed" }
    if (-not $endsUp) { $problems += 'last cap report is not "back up" (cap may be down, heads may be uncapped)' }
    if ($downs -gt 0 -and ($downs -lt 8 -or $downs -gt 12)) { $problems += "$downs cap cycles (normal is 10)" }
    if ($errs.Count -gt 0) { $problems += "$($errs.Count) error lines in PrintExp log" }
    if ($after.Status -ne 'Device Ready') { $problems += "status now '$($after.Status)'" }
    if ($problems.Count -gt 0) { return "ALERT clean ran ($how) but: " + ($problems -join '; ') }
    return "PASS clean ran ($how), cap $downs down / $ups up, ended capped, Device Ready"
}

function Install-Task {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Install must run from an administrator PowerShell.' }
    $exe = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -Mode Scheduled"
    $action = New-ScheduledTaskAction -Execute $exe -Argument $taskArgs -WorkingDirectory $ScriptDir
    $triggers = @()
    # Times may arrive as one comma-separated value when run with -File.
    $list = @($Times | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($t in $list) {
        if ($t -notmatch '^(\d{1,2}):(\d{2})$' -or [int]$Matches[1] -gt 23 -or [int]$Matches[2] -gt 59) { throw "Bad time '$t' (use HH:MM)." }
        $triggers += New-ScheduledTaskTrigger -Daily -At ((Get-Date).Date.AddHours([int]$Matches[1]).AddMinutes([int]$Matches[2]))
    }
    $Times = $list
    # Missed runs are skipped (no StartWhenAvailable), one at a time, 15 minute limit.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $triggers -Settings $settings -Principal $taskPrincipal `
        -Description "DTF printer: PrintExp Clean > $MenuGroup > Normal, only when all safety checks pass (AutoClean.ps1)." -Force | Out-Null
    Write-Log "Scheduled task '$TaskName' installed: daily at $($Times -join ' and ') as $user, highest privileges, only while signed in."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$mutex = New-Object System.Threading.Mutex -ArgumentList $false, 'Global\DirectEmbroideryDtfAutoClean'
if (-not $mutex.WaitOne(0)) { Write-Log 'Another AutoClean run is active. Exiting.' 'WARN'; exit 0 }
try {
    Get-ChildItem -Path $LogDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-60) } | Remove-Item -Force -ErrorAction SilentlyContinue

    if (Test-Path $SettingsFile) {
        $ms = Get-Content $SettingsFile -Raw | ConvertFrom-Json
        if ($ms.PSObject.Properties['MenuGroup']) {
            if (-not ([string]$ms.MenuGroup).Trim()) { throw 'machine-settings.json: MenuGroup is empty.' }
            $MenuGroup = ([string]$ms.MenuGroup).Trim()
        }
        if ($ms.PSObject.Properties['CleanVid']) {
            if ([string]$ms.CleanVid -notmatch '^\d{1,4}$') { throw "machine-settings.json: CleanVid '$($ms.CleanVid)' is not a number." }
            $CleanVid = [int]$ms.CleanVid
        }
    }

    $run = $Mode
    if ($Mode -eq 'Scheduled') {
        $run = 'Clean'
        $isRequest = $false
        if (Test-Path $RequestFile) {
            $ageMin = ((Get-Date) - (Get-Item $RequestFile).LastWriteTime).TotalMinutes
            $want = (Get-Content $RequestFile -Raw).Trim()
            Remove-Item $RequestFile -Force
            if ($ageMin -le 15 -and $want -match '^(Discover|DryRun|Clean|MailTest)(:(Command|Menu|Auto|\d))?$') {
                $run = $Matches[1]; $isRequest = $true
                $opt = $Matches[3]; if ($opt -match '^\d$') { $NormalPosHint = [int]$opt } elseif ($opt) { $Method = $opt }
                Write-Log "Test request: $want"
            }
            else {
                Write-Log ("Ignored stale or invalid test request '{0}' ({1:N0} min old). Nothing sent to PrintExp." -f $want, $ageMin) 'WARN'
                exit 0
            }
        }
        if ($run -eq 'Clean' -and -not $isRequest -and -not (Test-Path (Join-Path $StateDir 'autoclean-on.txt'))) {
            # The on/off switch (DTF-AutoClean-Switch.ps1). Off = scheduled runs do nothing.
            Write-Log 'Auto-clean is switched OFF. Nothing sent to PrintExp.'
            exit 0
        }
    }
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Log "AutoClean.ps1 v$ScriptVersion  Mode=$run  Method=$(if ($Method) { $Method } else { 'config' })  elevated=$elevated  group='$MenuGroup'  cleanVid=$CleanVid"

    switch ($run) {
        'Install' { Install-Task; exit 0 }
        'MailSetup' { Start-MailSignIn; Send-AlertMail "$MachineName DTF printer: alert email test" "This is a test. Alert emails from the $MachineName DTF printer auto-clean will arrive like this."; exit 0 }
        'MailTest' { Send-AlertMail "$MachineName DTF printer: alert email test" "Test from the scheduled task (runs as administrator). Alerts will arrive like this."; Write-Log 'RESULT: OK mail test'; exit 0 }
        'Discover' { $res = Invoke-Discover }
        'DryRun' { $res = Invoke-Clean -Dry }
        'Clean' { $res = Invoke-Clean }
    }
    Write-Log "RESULT: $res"
    Write-Status "$run  $res"
    if ($res -like 'FAIL*') { exit 2 }
    if ($res -like 'ALERT*') { exit 3 }
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    Write-Log ($_.ScriptStackTrace -replace '\r?\n', ' | ') 'ERROR'
    Write-Status "ERROR $($_.Exception.Message)"
    exit 1
}
finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
