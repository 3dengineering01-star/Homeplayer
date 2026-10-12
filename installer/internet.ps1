# Puts the OwnMedia server of this computer on the internet, so that friends (and the owner away
# from home) reach it. Run by OwnMediaSetup.exe as administrator when "Let friends watch from
# anywhere" is ticked:
#   1. installs Tailscale (the official package, checked by its signature) unless it is there;
#   2. signs in: the person picks an account in the browser window that opens;
#   3. turns on Tailscale Funnel for Jellyfin's port; the first time Tailscale asks, in the
#      browser, to allow it;
#   4. leaves the address (https://<computer>.<tailnet>.ts.net) in public-url.txt next to the setup
#      log, where the plugin takes it as the address of the invite links;
#   5. waits until the address is known on the internet: a new name takes some minutes to appear
#      there, and an invite opened before that does not work.
# Each step is skipped when already done, so running it again is harmless. -Step runs one of them
# (install, signin, funnel, wait), so that Setup can say what it waits for; without it, all.
#
# Exit codes: 0 done; 3 Tailscale could not be installed; 4 nobody signed in in time;
# 5 Funnel was not allowed in time; 6 anything else; 7 the address is not known on the internet
# yet (it works a little later). What happened is in setup.log.

param(
    [ValidateSet('all', 'install', 'signin', 'funnel', 'wait')]
    [string] $Step = 'all',
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
    Write-Log "Signature checked: $($signature.Status), $($signature.SignerCertificate.Subject)"
    Write-Log 'Installing Tailscale'
    # TS_NOLAUNCH: Tailscale's own welcome window would come up over Setup and the sign-in page.
    $install = Start-Process -FilePath 'msiexec.exe' -ArgumentList "/i `"$msi`" /quiet /norestart TS_NOLAUNCH=yes" -Wait -PassThru
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

# The DNS servers of ts.net (where every Funnel address lives), by their IP addresses. Asked
# through a public resolver: on a computer with Tailscale the usual resolver is Tailscale's own,
# which knows the address inside Tailscale (100.x), not on the internet. Public resolvers are not
# asked about the address itself while it is new: they would remember "no such name" for a while
# and hand it to friends.
function Get-NameServers {
    foreach ($resolver in @('1.1.1.1', '8.8.8.8')) {
        try {
            $hosts = @(Resolve-DnsName -Name 'ts.net' -Type NS -Server $resolver -DnsOnly -ErrorAction Stop |
                Where-Object { $_.Type -eq 'NS' } | ForEach-Object { $_.NameHost })
            $ips = @(foreach ($h in $hosts) {
                Resolve-DnsName -Name $h -Type A -Server $resolver -DnsOnly -ErrorAction SilentlyContinue |
                    Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.IPAddress }
            })
            if ($ips.Count -gt 0) { return $ips }
        } catch {
            # This resolver did not answer: try the next.
        }
    }
    return @()
}

# Tailscale's own addresses (100.64.0.0/10): the address inside Tailscale, not on the internet.
function Test-TailscaleAddress([string] $Ip) {
    $parts = $Ip.Split('.')
    return $parts.Count -eq 4 -and [int] $parts[0] -eq 100 -and [int] $parts[1] -ge 64 -and [int] $parts[1] -le 127
}

# The address as the internet sees it, from the DNS servers of ts.net: the public addresses of
# Tailscale's Funnel, or nothing while the name is new. Asked with nslookup: Windows sends every
# Resolve-DnsName question about *.ts.net to Tailscale (its NRPT rule), whatever server it names,
# while nslookup asks the server it is given. Its labels depend on the Windows language, so the
# answer is read as all IPv4 addresses in it except the server's own.
function Get-PublicAddresses([string] $Name, [string[]] $Servers) {
    $nslookup = Join-Path $env:WINDIR 'System32\nslookup.exe'
    $ErrorActionPreference = 'Continue'
    foreach ($server in $Servers) {
        $text = (& $nslookup -type=A $Name $server 2>$null) -join "`n"
        $found = @([regex]::Matches([string] $text, '\b\d{1,3}(\.\d{1,3}){3}\b') | ForEach-Object { $_.Value } |
            Where-Object { $_ -ne $server -and -not (Test-TailscaleAddress $_) } | Select-Object -Unique)
        if ($found.Count -gt 0) { return $found }
    }
    return @()
}

# Whether the server answers from the internet: a real HTTPS request to the public addresses.
# From this computer the name leads inside Tailscale, which works before the internet does, so
# curl is told to go to the public address while still asking for the name (its certificate).
function Test-FromInternet([string] $Name, [string[]] $Addresses) {
    $curl = Join-Path $env:WINDIR 'System32\curl.exe'
    if (-not (Test-Path $curl)) { return $true }
    $ErrorActionPreference = 'Continue'
    foreach ($ip in $Addresses) {
        $code = & $curl -s -o NUL -w '%{http_code}' --max-time 10 --resolve "${Name}:443:$ip" "https://$Name/System/Info/Public" 2>$null
        if ($code -eq '200') { return $true }
    }
    return $false
}

# Waits until a friend's phone can open the address: the name is known on the internet (a new one
# takes some minutes), and Funnel answers there (its certificate takes a few more).
function Wait-PublicName([string] $Name) {
    $servers = Get-NameServers
    if ($servers.Count -eq 0) {
        Write-Log 'No DNS servers found to ask about the address; not waiting'
        return $true
    }
    Write-Log "Waiting until https://$Name opens from the internet (asking $($servers -join ', '))"
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    $known = $false
    while ((Get-Date) -lt $deadline) {
        $addresses = Get-PublicAddresses $Name $servers
        if ($addresses.Count -gt 0) {
            if (-not $known) {
                Write-Log "$Name is known on the internet: $($addresses -join ', ')"
                $known = $true
            }
            if (Test-FromInternet $Name $addresses) {
                Write-Log "https://$Name opens from the internet"
                return $true
            }
        }
        Start-Sleep -Seconds 15
    }
    return $false
}

function Get-Address {
    $state = Get-TailscaleState
    if (-not $state -or -not $state.Self -or -not $state.Self.DNSName) { throw 'Tailscale gave no address for this computer' }
    return $state.Self.DNSName.TrimEnd('.')
}

try {
    if ($Step -eq 'all' -or $Step -eq 'install') {
        Write-Log 'Opening the server to the internet with Tailscale'
        try {
            Install-Tailscale
        } catch {
            Write-Log "Tailscale could not be installed: $($_.Exception.Message)"
            exit 3
        }
    }
    if (($Step -eq 'all' -or $Step -eq 'signin') -and -not (Connect-Tailscale)) {
        Write-Log 'Nobody signed in to Tailscale in time'
        exit 4
    }
    if ($Step -eq 'all' -or $Step -eq 'funnel') {
        if (-not (Enable-Funnel)) {
            Write-Log 'Funnel was not turned on in time'
            exit 5
        }
        $address = "https://$(Get-Address)"
        Set-Content -Path $UrlFile -Value $address -Encoding ASCII
        Write-Log "On the internet at $address"
    }
    if (($Step -eq 'all' -or $Step -eq 'wait') -and -not (Wait-PublicName (Get-Address))) {
        Write-Log 'The address is not known on the internet yet; it works a little later'
        exit 7
    }
    exit 0
} catch {
    Write-Log "Failed: $($_.Exception.Message)"
    exit 6
}
