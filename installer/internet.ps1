# Puts the OwnMedia server of this computer on the internet, so that friends (and the owner away
# from home) reach it. Run by OwnMediaSetup.exe as administrator when "Let friends watch from
# anywhere" is ticked:
#   1. installs Tailscale (the official package, checked by its signature) unless it is there;
#   2. signs in: the person picks an account in the browser window that opens;
#   3. turns on Tailscale Funnel for Jellyfin's port; the first time Tailscale asks, in the
#      browser, to allow it;
#   4. leaves the address (https://<computer>.<tailnet>.ts.net) in public-url.txt next to the setup
#      log, where the plugin takes it as the address of the invite links.
# Each step is skipped when already done, so running it again is harmless.
#
# Exit codes: 0 done; 3 Tailscale could not be installed; 4 nobody signed in in time;
# 5 Funnel was not allowed in time; 6 anything else. What happened is in setup.log.

param(
    [int] $Port = 8096,
    [int] $WaitMinutes = 15
)

$ErrorActionPreference = 'Stop'
$LogDir = Join-Path $env:ProgramData 'Homeplay'
$LogFile = Join-Path $LogDir 'setup.log'
$UrlFile = Join-Path $LogDir 'public-url.txt'
$Tailscale = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
$Package = 'https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi'

function Write-Log([string] $Message) {
    New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    Add-Content -Path $LogFile -Encoding UTF8 -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

# Opens a page in the person's browser. Through Explorer, so that the browser does not run as
# administrator like this script.
function Open-Page([string] $Url) {
    Write-Log "Opening $Url in the browser"
    Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList "`"$Url`""
}

function Install-Tailscale {
    if (Test-Path $Tailscale) {
        Write-Log 'Tailscale is installed already'
        return
    }
    Write-Log "Downloading Tailscale from $Package"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $msi = Join-Path $env:TEMP 'tailscale-setup.msi'
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing -Uri $Package -OutFile $msi
    # The package changes with every Tailscale release, so there is no fixed hash to check: it is
    # checked by its signature instead.
    $signature = Get-AuthenticodeSignature -FilePath $msi
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O="?Tailscale Inc') {
        throw "The downloaded Tailscale package is not signed by Tailscale ($($signature.Status), $($signature.SignerCertificate.Subject))"
    }
    Write-Log 'Installing Tailscale'
    $install = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$msi`" /quiet /norestart" -Wait -PassThru
    Remove-Item $msi -Force -ErrorAction SilentlyContinue
    if ($install.ExitCode -ne 0 -and $install.ExitCode -ne 3010) {
        throw "Tailscale setup ended with code $($install.ExitCode)"
    }
    for ($i = 0; $i -lt 60 -and -not (Test-Path $Tailscale); $i++) { Start-Sleep -Seconds 1 }
    if (-not (Test-Path $Tailscale)) { throw 'Tailscale is not where it should be after setup' }
}

# Tailscale's own view of this computer: BackendState (NeedsLogin, Running, ...), AuthURL and Self.
function Get-TailscaleState {
    # Windows PowerShell turns a native command's error output into a stopping error otherwise.
    $ErrorActionPreference = 'Continue'
    try {
        $text = (& $Tailscale status --json 2>$null) -join "`n"
        if ($text) { return $text | ConvertFrom-Json }
    } catch {
        # The service is still starting.
    }
    return $null
}

# Runs a Tailscale command that may wait for the person in the browser: every sign-in or approval
# page it prints, or Tailscale reports, is opened, and it is waited for until [Done] says so or
# the time is up. Returns whether [Done] was reached.
function Invoke-WithBrowser([string[]] $Arguments, [scriptblock] $Done) {
    $out = Join-Path $env:TEMP ('tailscale-{0}.txt' -f [guid]::NewGuid())
    $process = Start-Process -FilePath $Tailscale -ArgumentList $Arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    $opened = @{}
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    try {
        while ((Get-Date) -lt $deadline) {
            $text = (@($out, "$out.err") | Where-Object { Test-Path $_ } | ForEach-Object { Get-Content $_ -Raw }) -join "`n"
            $pages = @([regex]::Matches([string] $text, 'https://login\.tailscale\.com/\S+') | ForEach-Object { $_.Value })
            $state = Get-TailscaleState
            if ($state -and $state.AuthURL) { $pages += $state.AuthURL }
            foreach ($page in $pages) {
                if (-not $opened.ContainsKey($page)) {
                    $opened[$page] = $true
                    Open-Page $page
                }
            }
            if (& $Done) { return $true }
            if ($process.HasExited) {
                Start-Sleep -Seconds 2
                $finished = & $Done
                if (-not $finished) { Write-Log "tailscale $($Arguments -join ' ') ended: $($text.Trim())" }
                return $finished
            }
            Start-Sleep -Seconds 1
        }
        Write-Log "Gave up waiting for tailscale $($Arguments -join ' ')"
        return $false
    } finally {
        if (-not $process.HasExited) { $process.Kill() }
        Remove-Item $out, "$out.err" -Force -ErrorAction SilentlyContinue
    }
}

function Connect-Tailscale {
    for ($i = 0; $i -lt 30 -and -not (Get-TailscaleState); $i++) { Start-Sleep -Seconds 1 }
    $state = Get-TailscaleState
    if ($state -and $state.BackendState -eq 'Running') {
        Write-Log "Tailscale is signed in already as $($state.Self.DNSName)"
        return $true
    }
    Write-Log 'Signing in to Tailscale: waiting for the person in the browser'
    # Unattended: Tailscale keeps the server reachable when nobody is signed in to Windows.
    return Invoke-WithBrowser @('up', '--unattended') {
        $now = Get-TailscaleState
        $now -and $now.BackendState -eq 'Running'
    }
}

function Test-Funnel {
    $ErrorActionPreference = 'Continue'
    $text = (& $Tailscale funnel status 2>$null) -join "`n"
    return $text -match "Funnel on" -and $text -match "127\.0\.0\.1:$Port|localhost:$Port"
}

function Enable-Funnel {
    if (Test-Funnel) {
        Write-Log "Funnel is on already for port $Port"
        return $true
    }
    Write-Log "Turning on Funnel for port $Port"
    return Invoke-WithBrowser @('funnel', '--bg', "$Port") { Test-Funnel }
}

try {
    Write-Log 'Opening the server to the internet with Tailscale'
    try {
        Install-Tailscale
    } catch {
        Write-Log "Tailscale could not be installed: $($_.Exception.Message)"
        exit 3
    }
    if (-not (Connect-Tailscale)) {
        Write-Log 'Nobody signed in to Tailscale in time'
        exit 4
    }
    if (-not (Enable-Funnel)) {
        Write-Log 'Funnel was not turned on in time'
        exit 5
    }
    $name = (Get-TailscaleState).Self.DNSName.TrimEnd('.')
    $address = "https://$name"
    Set-Content -Path $UrlFile -Value $address -Encoding ASCII
    Write-Log "On the internet at $address"
    exit 0
} catch {
    Write-Log "Failed: $($_.Exception.Message)"
    exit 6
}
