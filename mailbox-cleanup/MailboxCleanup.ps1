<#
.SYNOPSIS
    Keeps a Microsoft 365 mailbox to a rolling window (default: the last 2 years)
    by deleting older mail, oldest first, in safe daily-sized chunks.

.DESCRIPTION
    Direct Embroidery mailbox cleanup (direct@sarasotashirts.com).

    * Report mode (the default) changes NOTHING. It lists every message older than
      the cutoff, per folder, with sizes, and writes a CSV you can open in Excel.
    * Delete mode removes those messages oldest first, across ALL mail folders.

    How deletes work (and why there is a per-run limit):
    Messages are "soft deleted" (Microsoft Graph DELETE). They skip the Deleted
    Items folder and go straight to the hidden Recoverable Items folder, which does
    NOT count against the 99 GB mailbox quota. For 14 days they can still be
    restored from Outlook on the web: Deleted Items > "Recover items deleted from
    this folder". After 14 days Microsoft purges them for good.

    The Recoverable Items folder has its own hard limit of 30 GB. If it fills up,
    NOBODY can delete anything in the mailbox until Microsoft purges it. So this
    script checks how full it is before each run and only deletes enough to keep it
    under -RecoverableBudgetGB (default 15 GB). Run daily, it clears the backlog
    over a few weeks and then just trims each day's mail as it turns 2 years old.

    Sign-in: the first run opens a browser to sign in to Microsoft 365 (the normal
    GoDaddy / Microsoft sign-in page). The script then keeps a refresh token,
    encrypted for this Windows user account only (Windows DPAPI), so scheduled runs
    sign in silently. Delete the "state" folder or run -SignOut to forget it.

.PARAMETER Mode
    Report (default, read-only) or Delete.

.PARAMETER KeepYears
    Keep mail newer than this many years. Default 2.

.PARAMETER MaxGBPerRun
    Never delete more than this many GB in a single run. Default 15.

.PARAMETER RecoverableBudgetGB
    Only delete while the Recoverable Items folder stays under this size. Default 15.
    (Microsoft's limits: purging starts at 20 GB, hard stop at 30 GB.)

.PARAMETER MaxItemsPerRun
    Safety cap on the number of messages deleted per run. Default 25000.

.PARAMETER TestOne
    With -Mode Delete: delete only the single oldest message, then stop. Use this once
    to confirm deletes work and that you can see the message under
    "Recover items deleted from this folder" in Outlook on the web.

.PARAMETER BackupPath
    Optional. Before deleting each message, save a full copy (.eml, attachments
    included) under this folder. A message is only deleted after its copy is saved.

.PARAMETER Force
    Skip the "type DELETE to continue" prompt. Used by the scheduled task.

.PARAMETER InstallSchedule
    Create a Windows scheduled task that runs "-Mode Delete -Force" daily at
    -ScheduleTime. The task runs as you, while you are logged in.

.PARAMETER UninstallSchedule
    Remove that scheduled task.

.PARAMETER SignOut
    Forget the saved sign-in and exit.

.EXAMPLE
    .\MailboxCleanup.ps1
    Sign in, then report what would be deleted. Nothing is changed.

.EXAMPLE
    .\MailboxCleanup.ps1 -Mode Delete -TestOne
    Delete only the single oldest message (to verify everything works).

.EXAMPLE
    .\MailboxCleanup.ps1 -Mode Delete
    Delete up to 15 GB of the oldest out-of-window mail.

.EXAMPLE
    .\MailboxCleanup.ps1 -InstallSchedule -ScheduleTime 02:30
    Run the cleanup automatically every day at 2:30 AM.
#>
[CmdletBinding()]
param(
    [ValidateSet('Report', 'Delete')]
    [string]$Mode = 'Report',

    [ValidateRange(1, 50)]
    [int]$KeepYears = 2,

    [ValidateRange(0.1, 100)]
    [double]$MaxGBPerRun = 15,

    [ValidateRange(1, 95)]
    [double]$RecoverableBudgetGB = 15,

    [ValidateRange(1, 1000000)]
    [int]$MaxItemsPerRun = 25000,

    [switch]$TestOne,

    [string]$BackupPath,

    [switch]$Force,

    [switch]$InstallSchedule,

    [switch]$UninstallSchedule,

    [ValidatePattern('^\d{1,2}:\d{2}$')]
    [string]$ScheduleTime = '02:30',

    [switch]$SignOut,

    # Advanced / testing only.
    [string]$GraphBaseUrl = 'https://graph.microsoft.com/v1.0',
    [string]$LoginBaseUrl = 'https://login.microsoftonline.com/organizations',
    [string]$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e'  # Microsoft Graph Command Line Tools (public client)
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

$ScriptVersion = '1.0.0'
$TaskName = 'Direct Embroidery Mailbox Cleanup'
$Scopes = 'https://graph.microsoft.com/Mail.ReadWrite offline_access openid profile'
$BatchSize = 20                 # Microsoft Graph JSON batch maximum
$PageSize = 500
$GB = [double]1GB

$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $ScriptPath
$StateDir = Join-Path $ScriptDir 'state'
$LogDir = Join-Path $ScriptDir 'logs'
$TokenFile = Join-Path $StateDir 'refresh-token.dat'
foreach ($d in @($StateDir, $LogDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}
$RunStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile = Join-Path $LogDir "MailboxCleanup_$RunStamp.log"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http
$Http = New-Object System.Net.Http.HttpClient
$Http.Timeout = [TimeSpan]::FromMinutes(5)
$script:AccessToken = $null
$script:AccessTokenExpiry = [datetime]::MinValue
$script:SignedInAccount = $null

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    switch ($Level) {
        'WARN' { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Format-GB([double]$Bytes) { '{0:N2} GB' -f ($Bytes / $GB) }

function ConvertTo-UtcDate($Value) {
    # Windows PowerShell 5.1 leaves JSON dates as strings; PowerShell 7 turns them into DateTime.
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    return [datetime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)
}

function Get-Total($Items, [string]$Property) {
    # Sums a numeric property. Returns 0 for an empty list (summing an empty list fails under StrictMode).
    $total = 0L
    foreach ($i in $Items) { $total += [long]$i.$Property }
    return $total
}

function Remove-OldLogs {
    Get-ChildItem -Path $LogDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-120) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# Sign-in (OAuth 2.0 authorization code + PKCE, loopback redirect)
# ---------------------------------------------------------------------------

function Protect-Text([string]$Text) {
    ConvertTo-SecureString -String $Text -AsPlainText -Force | ConvertFrom-SecureString
}

function Unprotect-Text([string]$Cipher) {
    $secure = ConvertTo-SecureString -String $Cipher
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function ConvertTo-Base64Url([byte[]]$Bytes) {
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-QueryValue([string]$Query, [string]$Name) {
    foreach ($pair in $Query.TrimStart('?').Split('&')) {
        $kv = $pair.Split('=', 2)
        if ($kv.Count -eq 2 -and $kv[0] -eq $Name) { return [Uri]::UnescapeDataString($kv[1].Replace('+', ' ')) }
    }
    return $null
}

function Invoke-TokenRequest([hashtable]$Form) {
    $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    foreach ($k in $Form.Keys) { $pairs.Add((New-Object 'System.Collections.Generic.KeyValuePair[string,string]' -ArgumentList $k, $Form[$k])) }
    $content = New-Object System.Net.Http.FormUrlEncodedContent -ArgumentList (, $pairs)
    $resp = $Http.PostAsync("$LoginBaseUrl/oauth2/v2.0/token", $content).GetAwaiter().GetResult()
    $body = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $json = $null
    try { $json = $body | ConvertFrom-Json } catch { }
    if (-not $resp.IsSuccessStatusCode) {
        $desc = if ($json -and $json.PSObject.Properties['error_description']) { $json.error_description } else { $body }
        throw "Sign-in failed ($([int]$resp.StatusCode)): $desc"
    }
    return $json
}

function Get-IdTokenAccount($TokenResponse) {
    # Reads the signed-in account from the id_token Microsoft returns with every token
    # (openid/profile scopes). Used instead of Graph /me, which needs User.Read.
    if (-not ($TokenResponse.PSObject.Properties['id_token'] -and $TokenResponse.id_token)) { return $null }
    try {
        $payload = ([string]$TokenResponse.id_token).Split('.')[1].Replace('-', '+').Replace('_', '/')
        switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        $upn = ''
        foreach ($n in @('preferred_username', 'upn', 'email')) {
            if ($claims.PSObject.Properties[$n] -and $claims.$n) { $upn = [string]$claims.$n; break }
        }
        $name = if ($claims.PSObject.Properties['name']) { [string]$claims.name } else { '' }
        if (-not $upn) { return $null }
        return [pscustomobject]@{ displayName = $name; userPrincipalName = $upn }
    }
    catch { return $null }
}

function Save-TokenResponse($TokenResponse) {
    $account = Get-IdTokenAccount $TokenResponse
    if ($account) { $script:SignedInAccount = $account }
    $script:AccessToken = $TokenResponse.access_token
    $script:AccessTokenExpiry = (Get-Date).AddSeconds([int]$TokenResponse.expires_in - 120)
    if ($TokenResponse.PSObject.Properties['refresh_token'] -and $TokenResponse.refresh_token) {
        Set-Content -Path $TokenFile -Value (Protect-Text $TokenResponse.refresh_token) -Encoding ASCII
    }
}

function Start-InteractiveSignIn {
    if (-not [Environment]::UserInteractive -or $Force) {
        throw 'No saved sign-in. Run the script once by hand (without -Force) to sign in.'
    }
    $verifier = ConvertTo-Base64Url ([Guid]::NewGuid().ToByteArray() + [Guid]::NewGuid().ToByteArray() + [Guid]::NewGuid().ToByteArray())
    $sha = [Security.Cryptography.SHA256]::Create()
    $challenge = ConvertTo-Base64Url ($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier)))
    $state = [Guid]::NewGuid().ToString('N')

    # Listen on both IPv4 and IPv6 loopback; browsers may resolve "localhost" to either.
    $v4 = New-Object System.Net.Sockets.TcpListener -ArgumentList ([Net.IPAddress]::Loopback), 0
    $v4.Start()
    $port = ([Net.IPEndPoint]$v4.LocalEndpoint).Port
    $v6 = $null
    try { $v6 = New-Object System.Net.Sockets.TcpListener -ArgumentList ([Net.IPAddress]::IPv6Loopback), $port; $v6.Start() } catch { $v6 = $null }

    $redirectUri = "http://localhost:$port"
    $authUrl = "$LoginBaseUrl/oauth2/v2.0/authorize?client_id=$ClientId&response_type=code" +
        "&redirect_uri=$([Uri]::EscapeDataString($redirectUri))" +
        "&scope=$([Uri]::EscapeDataString($Scopes))" +
        "&state=$state&code_challenge=$challenge&code_challenge_method=S256&prompt=select_account"

    Write-Log 'Opening your browser to sign in to Microsoft 365 (direct@sarasotashirts.com)...'
    Write-Host "If the browser does not open, copy this link into it:`n$authUrl`n"
    try { Start-Process $authUrl } catch { }

    $code = $null; $err = $null
    $deadline = (Get-Date).AddMinutes(10)
    try {
        while ((Get-Date) -lt $deadline -and -not $code -and -not $err) {
            $listener = $null
            if ($v4.Pending()) { $listener = $v4 } elseif ($v6 -and $v6.Pending()) { $listener = $v6 }
            if (-not $listener) { Start-Sleep -Milliseconds 200; continue }
            $client = $listener.AcceptTcpClient()
            try {
                $stream = $client.GetStream()
                $stream.ReadTimeout = 5000
                $reader = New-Object System.IO.StreamReader -ArgumentList $stream, ([Text.Encoding]::ASCII), $false, 8192, $true
                $requestLine = $reader.ReadLine()
                $target = if ($requestLine) { $requestLine.Split(' ')[1] } else { '' }
                $query = if ($target -and $target.Contains('?')) { $target.Substring($target.IndexOf('?')) } else { '' }
                $msg = 'Waiting for sign-in...'
                if ($query) {
                    if ((Get-QueryValue $query 'state') -ne $state) { $msg = 'Ignored: unexpected request.' }
                    elseif (Get-QueryValue $query 'error') {
                        $err = '{0}: {1}' -f (Get-QueryValue $query 'error'), (Get-QueryValue $query 'error_description')
                        $msg = "Sign-in failed: $err"
                    }
                    else { $code = Get-QueryValue $query 'code'; $msg = 'Signed in. You can close this tab and return to the script.' }
                }
                $html = "<html><body style='font-family:sans-serif'><h3>Direct Embroidery mailbox cleanup</h3><p>$([Net.WebUtility]::HtmlEncode($msg))</p></body></html>"
                $bytes = [Text.Encoding]::UTF8.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/html; charset=utf-8`r`nContent-Length: $([Text.Encoding]::UTF8.GetByteCount($html))`r`nConnection: close`r`n`r`n$html")
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush()
            }
            catch { }
            finally { $client.Close() }
        }
    }
    finally {
        $v4.Stop()
        if ($v6) { $v6.Stop() }
    }
    if ($err) { throw "Sign-in failed: $err" }
    if (-not $code) { throw 'Sign-in timed out after 10 minutes.' }

    Save-TokenResponse (Invoke-TokenRequest @{
            client_id     = $ClientId
            grant_type    = 'authorization_code'
            code          = $code
            redirect_uri  = $redirectUri
            code_verifier = $verifier
            scope         = $Scopes
        })
    Write-Log 'Sign-in complete. Sign-in saved for scheduled runs (encrypted for this Windows user).'
}

function Update-AccessToken {
    if (Test-Path $TokenFile) {
        try {
            $refresh = Unprotect-Text (Get-Content -Path $TokenFile -Raw).Trim()
            Save-TokenResponse (Invoke-TokenRequest @{
                    client_id     = $ClientId
                    grant_type    = 'refresh_token'
                    refresh_token = $refresh
                    scope         = $Scopes
                })
            return
        }
        catch {
            Write-Log "Saved sign-in could not be used ($($_.Exception.Message))." 'WARN'
        }
    }
    Start-InteractiveSignIn
}

function Get-AccessToken {
    if (-not $script:AccessToken -or (Get-Date) -ge $script:AccessTokenExpiry) { Update-AccessToken }
    return $script:AccessToken
}

# ---------------------------------------------------------------------------
# Microsoft Graph helpers
# ---------------------------------------------------------------------------

function Get-RetryDelaySeconds($Response, [int]$Attempt) {
    $delay = [Math]::Min(60, [Math]::Pow(2, $Attempt))
    if ($Response -and $Response.Headers.RetryAfter -and $Response.Headers.RetryAfter.Delta) {
        $delay = [Math]::Max($delay, $Response.Headers.RetryAfter.Delta.Value.TotalSeconds)
    }
    return [int][Math]::Ceiling($delay)
}

function Invoke-Graph {
    param(
        [string]$Method = 'GET',
        [string]$Uri,
        $Body = $null,
        [string]$OutFile = $null
    )
    if ($Uri -notmatch '^https?://') { $Uri = $GraphBaseUrl + $Uri }
    $attempt = 0
    $refreshedOn401 = $false
    while ($true) {
        $attempt++
        $req = New-Object System.Net.Http.HttpRequestMessage -ArgumentList (New-Object System.Net.Http.HttpMethod -ArgumentList $Method), $Uri
        $req.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue -ArgumentList 'Bearer', (Get-AccessToken)
        if ($null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 10 -Compress
            $req.Content = New-Object System.Net.Http.StringContent -ArgumentList $json, ([Text.Encoding]::UTF8), 'application/json'
        }
        $resp = $null
        try {
            $resp = $Http.SendAsync($req).GetAwaiter().GetResult()
        }
        catch {
            if ($attempt -ge 6) { throw }
            Start-Sleep -Seconds (Get-RetryDelaySeconds $null $attempt)
            continue
        }
        $status = [int]$resp.StatusCode
        if ($status -eq 401 -and -not $refreshedOn401) {
            $refreshedOn401 = $true
            $script:AccessToken = $null
            $attempt--
            continue
        }
        if (($status -eq 429 -or $status -ge 500) -and $attempt -lt 8) {
            Start-Sleep -Seconds (Get-RetryDelaySeconds $resp $attempt)
            continue
        }
        if (-not $resp.IsSuccessStatusCode) {
            $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $ex = New-Object System.Exception -ArgumentList "Graph $Method $Uri failed ($status): $text"
            $ex.Data['Status'] = $status
            throw $ex
        }
        if ($OutFile) {
            $fs = [IO.File]::Create($OutFile)
            try { [void]$resp.Content.CopyToAsync($fs).GetAwaiter().GetResult() } finally { $fs.Dispose() }
            return $null
        }
        $text = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        return ($text | ConvertFrom-Json)
    }
}

function Get-ExtendedPropertyValue($Item) {
    if ($Item.PSObject.Properties['singleValueExtendedProperties'] -and $Item.singleValueExtendedProperties) {
        foreach ($p in @($Item.singleValueExtendedProperties)) {
            $v = 0L
            if ([long]::TryParse([string]$p.value, [ref]$v)) { return $v }
        }
    }
    return 0L
}

# PidTagMessageSizeExtended (folders, 64-bit) and PidTagMessageSize (messages, 32-bit).
$FolderSizeExpand = '$expand=' + [Uri]::EscapeDataString("singleValueExtendedProperties(`$filter=id eq 'Long 0x0E08')")
$MessageSizeExpand = '$expand=' + [Uri]::EscapeDataString("singleValueExtendedProperties(`$filter=id eq 'Integer 0x0E08')")

function Get-AllPages([string]$Uri) {
    $items = New-Object System.Collections.Generic.List[object]
    $next = $Uri
    while ($next) {
        $page = Invoke-Graph -Uri $next
        if ($page.PSObject.Properties['value']) { foreach ($v in @($page.value)) { $items.Add($v) } }
        $next = if ($page.PSObject.Properties['@odata.nextLink']) { $page.'@odata.nextLink' } else { $null }
    }
    return , $items
}

$script:SizesAvailable = $true
$SizeFallbackItemCap = 5000

function Get-AllPagesWithSize([string]$UriWithSize, [string]$UriWithoutSize) {
    # Message/folder sizes come from an extended property. If Microsoft ever rejects that
    # request, carry on without sizes (the run is then limited by item count instead).
    if ($script:SizesAvailable) {
        try { return , (Get-AllPages $UriWithSize) }
        catch {
            if (-not ($_.Exception.Data.Contains('Status') -and $_.Exception.Data['Status'] -eq 400)) { throw }
            $script:SizesAvailable = $false
            Write-Log "Microsoft would not return item sizes ($($_.Exception.Message)). Continuing without sizes; deletes will be limited to $SizeFallbackItemCap messages per run." 'WARN'
        }
    }
    return , (Get-AllPages $UriWithoutSize)
}

function Get-MailFolderTree {
    # Returns every mail folder (not search folders) with its full path and size.
    $result = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Queue
    $top = Get-AllPagesWithSize "/me/mailFolders?`$top=100&$FolderSizeExpand" '/me/mailFolders?$top=100'
    foreach ($f in $top) { $queue.Enqueue(@{ Folder = $f; Path = $f.displayName }) }
    while ($queue.Count -gt 0) {
        $entry = $queue.Dequeue()
        $f = $entry.Folder
        if ($f.PSObject.Properties['@odata.type'] -and $f.'@odata.type' -like '*mailSearchFolder*') { continue }
        $result.Add([pscustomobject]@{
                Id         = $f.id
                Path       = $entry.Path
                TotalItems = [int]$f.totalItemCount
                SizeBytes  = [long](Get-ExtendedPropertyValue $f)
            })
        if ([int]$f.childFolderCount -gt 0) {
            $childUri = "/me/mailFolders/$([Uri]::EscapeDataString($f.id))/childFolders?`$top=100"
            $children = Get-AllPagesWithSize "$childUri&$FolderSizeExpand" $childUri
            foreach ($c in $children) { $queue.Enqueue(@{ Folder = $c; Path = "$($entry.Path)\$($c.displayName)" }) }
        }
    }
    return , $result
}

function Get-RecoverableItemsBytes {
    try {
        $f = Invoke-Graph -Uri "/me/mailFolders/recoverableitemsdeletions?$FolderSizeExpand"
        return [long](Get-ExtendedPropertyValue $f)
    }
    catch {
        Write-Log "Could not read the Recoverable Items size: $($_.Exception.Message)" 'WARN'
        return -1L
    }
}

function Get-OldMessages($Folder, [string]$CutoffIso) {
    $filter = [Uri]::EscapeDataString("receivedDateTime lt $CutoffIso")
    $select = 'id,receivedDateTime,subject,from,hasAttachments'
    $baseUri = "/me/mailFolders/$([Uri]::EscapeDataString($Folder.Id))/messages?`$filter=$filter&`$select=$select&`$top=$PageSize"
    $list = Get-AllPagesWithSize "$baseUri&$MessageSizeExpand" $baseUri
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($m in $list) {
        $fromAddress = ''
        if ($m.PSObject.Properties['from'] -and $m.from -and $m.from.PSObject.Properties['emailAddress'] -and $m.from.emailAddress -and
            $m.from.emailAddress.PSObject.Properties['address']) { $fromAddress = [string]$m.from.emailAddress.address }
        $out.Add([pscustomobject]@{
                Id             = $m.id
                Received       = ConvertTo-UtcDate $m.receivedDateTime
                Folder         = $Folder.Path
                From           = $fromAddress
                Subject        = [string]$m.subject
                HasAttachments = [bool]$m.hasAttachments
                SizeBytes      = [long](Get-ExtendedPropertyValue $m)
            })
    }
    return , $out
}

function Get-SafeFileName([string]$Name, [int]$Max = 60) {
    if (-not $Name) { $Name = 'no subject' }
    # Characters Windows does not allow in file names, plus control characters.
    $invalid = [IO.Path]::GetInvalidFileNameChars() + [char[]]'<>:"/\|?*'
    $clean = -join ($Name.ToCharArray() | ForEach-Object { if ($invalid -contains $_ -or [int]$_ -lt 32) { '_' } else { $_ } })
    $clean = $clean.Trim().TrimEnd('.')
    if ($clean.Length -gt $Max) { $clean = $clean.Substring(0, $Max) }
    if (-not $clean) { $clean = 'no subject' }
    return $clean
}

function Save-MessageBackup($Msg) {
    $folderParts = @($Msg.Folder.Split('\') | ForEach-Object { Get-SafeFileName $_ 80 })
    $dir = $BackupPath
    foreach ($part in $folderParts + @($Msg.Received.ToString('yyyy'))) { $dir = Join-Path $dir $part }
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $idTail = ($Msg.Id -replace '[^A-Za-z0-9]', '')
    if ($idTail.Length -gt 10) { $idTail = $idTail.Substring($idTail.Length - 10) }
    $file = Join-Path $dir ('{0}_{1}_{2}.eml' -f $Msg.Received.ToString('yyyy-MM-dd_HHmmss'), (Get-SafeFileName $Msg.Subject), $idTail)
    $tmp = "$file.partial"
    Invoke-Graph -Uri "/me/messages/$([Uri]::EscapeDataString($Msg.Id))/`$value" -OutFile $tmp
    if ((Get-Item $tmp).Length -le 0) { Remove-Item $tmp -Force; throw 'Empty download' }
    Move-Item -Path $tmp -Destination $file -Force
}

function Remove-MessagesBatch($Batch) {
    # Deletes up to 20 messages in one Graph JSON batch, retrying throttled items.
    # Returns @{ Deleted = [list]; Failed = [list]; QuotaHit = bool }
    $pending = @{}
    for ($i = 0; $i -lt $Batch.Count; $i++) { $pending[[string]$i] = $Batch[$i] }
    $deleted = New-Object System.Collections.Generic.List[object]
    $failed = New-Object System.Collections.Generic.List[object]
    $quotaHit = $false
    $attempt = 0
    while ($pending.Count -gt 0 -and $attempt -lt 8) {
        $attempt++
        $requests = @()
        foreach ($k in $pending.Keys) {
            $requests += @{ id = $k; method = 'DELETE'; url = "/me/messages/$([Uri]::EscapeDataString($pending[$k].Id))" }
        }
        $result = Invoke-Graph -Method 'POST' -Uri '/$batch' -Body @{ requests = $requests }
        $retryAfter = 0
        foreach ($r in @($result.responses)) {
            $key = [string]$r.id
            if (-not $pending.ContainsKey($key)) { continue }
            $status = [int]$r.status
            if ($status -eq 204 -or $status -eq 200) {
                $deleted.Add($pending[$key]); $pending.Remove($key)
            }
            elseif ($status -eq 404) {
                # Already gone (deleted by someone else in the meantime).
                $pending.Remove($key)
            }
            elseif ($status -eq 429 -or $status -ge 500) {
                $ra = 0
                if ($r.PSObject.Properties['headers'] -and $r.headers -and $r.headers.PSObject.Properties['Retry-After']) {
                    [void][int]::TryParse([string]$r.headers.'Retry-After', [ref]$ra)
                }
                $retryAfter = [Math]::Max($retryAfter, [Math]::Max($ra, [Math]::Min(60, [Math]::Pow(2, $attempt))))
            }
            else {
                $text = ''
                if ($r.PSObject.Properties['body'] -and $r.body) { $text = ($r.body | ConvertTo-Json -Depth 5 -Compress) }
                if ($text -match 'Quota') { $quotaHit = $true }
                $failed.Add([pscustomobject]@{ Message = $pending[$key]; Error = "$status $text" })
                $pending.Remove($key)
            }
        }
        if ($pending.Count -gt 0) { Start-Sleep -Seconds ([int][Math]::Ceiling([Math]::Max(1, $retryAfter))) }
    }
    foreach ($k in @($pending.Keys)) {
        $failed.Add([pscustomobject]@{ Message = $pending[$k]; Error = 'Still throttled after retries' })
    }
    return @{ Deleted = $deleted; Failed = $failed; QuotaHit = $quotaHit }
}

# ---------------------------------------------------------------------------
# Scheduled task management
# ---------------------------------------------------------------------------

function Install-CleanupSchedule {
    $exe = (Get-Process -Id $PID).Path
    $taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -Mode Delete -Force -KeepYears $KeepYears -MaxGBPerRun $MaxGBPerRun -RecoverableBudgetGB $RecoverableBudgetGB"
    if ($BackupPath) { $taskArgs += " -BackupPath `"$((Resolve-Path $BackupPath).ProviderPath)`"" }
    $parts = $ScheduleTime.Split(':')
    $at = (Get-Date).Date.AddHours([int]$parts[0]).AddMinutes([int]$parts[1])
    $action = New-ScheduledTaskAction -Execute $exe -Argument $taskArgs -WorkingDirectory $ScriptDir
    $trigger = New-ScheduledTaskTrigger -Daily -At $at
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 6) -MultipleInstances IgnoreNew
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
        -Description 'Deletes Direct Embroidery mail older than the retention window (MailboxCleanup.ps1).' -Force | Out-Null
    Write-Log "Scheduled task '$TaskName' installed: daily at $ScheduleTime as $user (runs while you are logged in; catches up after the PC wakes)."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    Remove-OldLogs
    Write-Log "MailboxCleanup.ps1 v$ScriptVersion  Mode=$Mode  KeepYears=$KeepYears  MaxGBPerRun=$MaxGBPerRun  RecoverableBudgetGB=$RecoverableBudgetGB$(if ($TestOne) { '  TestOne' })$(if ($BackupPath) { "  BackupPath=$BackupPath" })"

    if ($SignOut) {
        if (Test-Path $TokenFile) { Remove-Item $TokenFile -Force }
        Write-Log 'Saved sign-in removed.'
        exit 0
    }
    if ($UninstallSchedule) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "Scheduled task '$TaskName' removed (if it existed)."
        exit 0
    }

    # Confirms mail access (Mail.ReadWrite is the only Graph permission requested; /me would need User.Read).
    [void](Invoke-Graph -Uri '/me/mailFolders/inbox?$select=id')
    $me = $script:SignedInAccount
    if (-not $me) { $me = [pscustomobject]@{ displayName = ''; userPrincipalName = '(account name not returned by sign-in)' } }
    Write-Log "Signed in as $($me.displayName) <$($me.userPrincipalName)>"

    if ($InstallSchedule) {
        Install-CleanupSchedule
        exit 0
    }

    $cutoff = (Get-Date).ToUniversalTime().AddYears(-$KeepYears)
    $cutoffIso = $cutoff.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-Log "Keeping everything received on or after $($cutoff.ToLocalTime().ToString('yyyy-MM-dd HH:mm')) (local time). Older mail is in scope."

    # --- Inventory -----------------------------------------------------------
    $folders = Get-MailFolderTree
    $mailboxBytes = (Get-Total $folders 'SizeBytes')
    Write-Log ("Found {0} mail folders, {1:N0} items, {2} in total." -f $folders.Count, (Get-Total $folders 'TotalItems'), (Format-GB $mailboxBytes))

    $candidates = New-Object System.Collections.Generic.List[object]
    $folderRows = New-Object System.Collections.Generic.List[object]
    foreach ($f in $folders) {
        if ($f.TotalItems -eq 0) { continue }
        $old = Get-OldMessages $f $cutoffIso
        foreach ($m in $old) { $candidates.Add($m) }
        $oldBytes = (Get-Total $old 'SizeBytes')
        if ($old.Count -gt 0) {
            $folderRows.Add([pscustomobject]@{ Folder = $f.Path; Items = $f.TotalItems; Size = $f.SizeBytes; OldItems = $old.Count; OldSize = $oldBytes })
        }
    }
    $candidateBytes = (Get-Total $candidates 'SizeBytes')

    Write-Log '--- Mail older than the cutoff, by folder ---'
    foreach ($row in ($folderRows | Sort-Object OldSize -Descending)) {
        Write-Log ("{0,-40} {1,8:N0} of {2,8:N0} items   {3,10} of {4,10}" -f $row.Folder, $row.OldItems, $row.Items, (Format-GB $row.OldSize), (Format-GB $row.Size))
    }
    Write-Log ("TOTAL out of window: {0:N0} messages, {1}" -f $candidates.Count, (Format-GB $candidateBytes))
    if ($candidates.Count -gt 0) {
        $withAtt = @($candidates | Where-Object { $_.HasAttachments })
        Write-Log ("  of which {0:N0} have attachments ({1})" -f $withAtt.Count, (Format-GB ((Get-Total $withAtt 'SizeBytes'))))
    }

    $riBytes = Get-RecoverableItemsBytes
    if ($riBytes -ge 0) { Write-Log "Recoverable Items (deleted, restorable for 14 days) currently holds $(Format-GB $riBytes). Budget: $RecoverableBudgetGB GB." }

    $sorted = @($candidates | Sort-Object Received)

    if ($Mode -eq 'Report') {
        $csv = Join-Path $LogDir "Report_$RunStamp.csv"
        $sorted | Select-Object @{ n = 'Received'; e = { $_.Received.ToLocalTime().ToString('yyyy-MM-dd HH:mm') } }, Folder, From, Subject, HasAttachments,
        @{ n = 'SizeMB'; e = { [Math]::Round($_.SizeBytes / 1MB, 2) } } | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
        Write-Log "Report only - nothing was changed. Full list: $csv"
        if ($candidateBytes -gt 0) {
            $perRun = [Math]::Min($MaxGBPerRun, $RecoverableBudgetGB)
            Write-Log ("At up to {0} GB per run, clearing the backlog takes about {1} run(s), spaced roughly 2 weeks apart while Microsoft purges the Recoverable Items folder." -f $perRun, [Math]::Ceiling(($candidateBytes / $GB) / $perRun))
        }
        exit 0
    }

    # --- Delete --------------------------------------------------------------
    if ($sorted.Count -eq 0) { Write-Log 'Nothing to delete. Mailbox is already within the retention window.'; exit 0 }

    $budgetBytes = [long]($MaxGBPerRun * $GB)
    if ($riBytes -ge 0) {
        $riRoom = [long]($RecoverableBudgetGB * $GB) - $riBytes
        if ($riRoom -lt $budgetBytes) { $budgetBytes = $riRoom }
    }
    else {
        Write-Log 'Recoverable Items size unknown; limiting this run to 5 GB to be safe.' 'WARN'
        $budgetBytes = [Math]::Min($budgetBytes, [long](5 * $GB))
    }
    if ($budgetBytes -lt [long](0.25 * $GB) -and -not $TestOne) {
        Write-Log ("Recoverable Items is at {0}, at or near the {1} GB budget. Skipping deletes this run; Microsoft purges deleted items after 14 days and a later run will continue." -f (Format-GB $riBytes), $RecoverableBudgetGB) 'WARN'
        exit 0
    }

    if (-not $script:SizesAvailable -and $MaxItemsPerRun -gt $SizeFallbackItemCap) { $MaxItemsPerRun = $SizeFallbackItemCap }
    $plan = New-Object System.Collections.Generic.List[object]
    $planBytes = 0L
    foreach ($m in $sorted) {
        if ($plan.Count -ge $MaxItemsPerRun) { break }
        if ($TestOne) { $plan.Add($m); $planBytes += $m.SizeBytes; break }
        if (($planBytes + $m.SizeBytes) -gt $budgetBytes) { break }
        $plan.Add($m); $planBytes += $m.SizeBytes
    }
    if ($plan.Count -eq 0) { Write-Log 'The oldest message alone is larger than what this run may delete. Skipping until the budget frees up.' 'WARN'; exit 0 }
    Write-Log ("This run will delete {0:N0} messages ({1}), oldest first: {2} to {3}." -f $plan.Count, (Format-GB $planBytes),
        $plan[0].Received.ToLocalTime().ToString('yyyy-MM-dd'), $plan[$plan.Count - 1].Received.ToLocalTime().ToString('yyyy-MM-dd'))

    if ($BackupPath) {
        if (-not (Test-Path $BackupPath)) { New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null }
        $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot((Resolve-Path $BackupPath).ProviderPath))
        if ($drive.AvailableFreeSpace -lt ($planBytes * 1.5 + 2 * $GB)) {
            throw ("Not enough free space for the backup on {0}: {1} free, need about {2}." -f $drive.Name, (Format-GB $drive.AvailableFreeSpace), (Format-GB ($planBytes * 1.5 + 2 * $GB)))
        }
    }

    if (-not $Force) {
        Write-Host ''
        Write-Host ("About to delete {0:N0} messages ({1}) from {2}." -f $plan.Count, (Format-GB $planBytes), $me.userPrincipalName) -ForegroundColor Yellow
        Write-Host 'They can be restored for 14 days from Outlook on the web: Deleted Items > "Recover items deleted from this folder".' -ForegroundColor Yellow
        $answer = Read-Host 'Type DELETE to continue'
        if ($answer -cne 'DELETE') { Write-Log 'Cancelled by user. Nothing was deleted.'; exit 0 }
    }

    $deletedCsv = Join-Path $LogDir "Deleted_$RunStamp.csv"
    $deletedCount = 0; $deletedBytes = 0L; $failedCount = 0; $backupFailures = 0
    $started = Get-Date
    for ($i = 0; $i -lt $plan.Count; $i += $BatchSize) {
        $chunk = $plan.GetRange($i, [Math]::Min($BatchSize, $plan.Count - $i)).ToArray()
        if ($BackupPath) {
            $ready = New-Object System.Collections.Generic.List[object]
            foreach ($m in $chunk) {
                try { Save-MessageBackup $m; $ready.Add($m) }
                catch { $backupFailures++; Write-Log "Backup failed, NOT deleting: $($m.Received.ToString('yyyy-MM-dd')) '$($m.Subject)': $($_.Exception.Message)" 'WARN' }
            }
            $chunk = $ready.ToArray()
            if ($chunk.Count -eq 0) { continue }
        }
        $res = Remove-MessagesBatch $chunk
        foreach ($m in $res.Deleted) { $deletedCount++; $deletedBytes += $m.SizeBytes }
        if ($res.Deleted.Count -gt 0) {
            $res.Deleted | Select-Object @{ n = 'Received'; e = { $_.Received.ToLocalTime().ToString('yyyy-MM-dd HH:mm') } }, Folder, From, Subject, HasAttachments,
            @{ n = 'SizeMB'; e = { [Math]::Round($_.SizeBytes / 1MB, 2) } } | Export-Csv -Path $deletedCsv -NoTypeInformation -Encoding UTF8 -Append
        }
        foreach ($f in $res.Failed) {
            $failedCount++
            Write-Log "Delete failed: $($f.Message.Received.ToString('yyyy-MM-dd')) '$($f.Message.Subject)': $($f.Error)" 'WARN'
        }
        if ($res.QuotaHit) { Write-Log 'Microsoft reported a quota problem while deleting. Stopping this run.' 'ERROR'; break }
        if ($failedCount -ge 200 -and $failedCount -gt $deletedCount) { Write-Log 'Too many failures. Stopping this run.' 'ERROR'; break }
        if ((($i / $BatchSize) % 25) -eq 0 -or ($i + $BatchSize) -ge $plan.Count) {
            $elapsed = (Get-Date) - $started
            Write-Log ("Progress: {0:N0}/{1:N0} deleted ({2}), {3:N0} failed, {4:N0} min elapsed." -f $deletedCount, $plan.Count, (Format-GB $deletedBytes), $failedCount, $elapsed.TotalMinutes)
        }
    }

    Write-Log ("DONE: deleted {0:N0} messages ({1}). Failed: {2:N0}.{3} Remaining out of window: {4:N0} messages ({5})." -f $deletedCount, (Format-GB $deletedBytes), $failedCount,
        $(if ($BackupPath) { " Backup failures (kept in mailbox): $backupFailures." } else { '' }),
        ($sorted.Count - $deletedCount), (Format-GB ($candidateBytes - $deletedBytes)))
    if ($deletedCount -gt 0) { Write-Log "List of deleted messages: $deletedCsv" }
    if ($failedCount -gt 0 -or $backupFailures -gt 0) { exit 3 }
    exit 0
}
catch {
    Write-Log $_.Exception.Message 'ERROR'
    Write-Log ($_.ScriptStackTrace -replace '\r?\n', ' | ') 'ERROR'
    exit 1
}
