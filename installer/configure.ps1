# Sets up Jellyfin for Homeplay, run by HomeplaySetup.exe as administrator: puts the Homeplay
# plugin (with the phone app) into Jellyfin's plugin folder, and on a fresh Jellyfin finishes its
# first-run wizard with the person's name and password, adds the libraries
# (movies, shows, music, photos), points the Homeplay plugin at the photo folder and lets phones
# on the home network in. Windows PowerShell 5.1, nothing to install.
#
#   powershell -ExecutionPolicy Bypass -File configure.ps1 -Settings C:\...\settings.json -Plugin C:\...\plugin
#
# settings.json: { "Name", "Password", "Movies", "Shows", "Music", "Photos", "HomeNetwork": true }.
# The file holds the password: the installer deletes it as soon as this script ends. The log
# (C:\ProgramData\Homeplay\setup.log) never has it.
#
# -Plugin is a folder with Jellyfin.Plugin.HomeplayBackup.dll, QRCoder.dll and Homeplay.apk.
#
# Exit codes: 0 done, 1 the server did not start, 2 setting it up failed (see the log).

param(
    [Parameter(Mandatory = $true)] [string] $Settings,
    [Parameter(Mandatory = $true)] [string] $Plugin,
    [string] $Server = 'http://localhost:8096'
)

$ErrorActionPreference = 'Stop'
$PluginId = 'ca1d038a-d3f7-4ef4-9839-1e93a8105618'
$LogDir = Join-Path $env:ProgramData 'Homeplay'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log = Join-Path $LogDir 'setup.log'

function Write-Log([string] $Message) {
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
    Add-Content -Path $Log -Value $line -Encoding UTF8
    Write-Host $line
}

# Jellyfin wants every client to say who it is; the token is added once signed in.
$DeviceId = [guid]::NewGuid().ToString('N')
$script:Token = $null
function Get-AuthHeader {
    $value = 'MediaBrowser Client="Homeplay Setup", Device="{0}", DeviceId="{1}", Version="1.0"' -f $env:COMPUTERNAME, $DeviceId
    if ($script:Token) { $value += ', Token="{0}"' -f $script:Token }
    @{ Authorization = $value }
}

# While Jellyfin starts it answers 503 for a while: such calls are tried again.
function Invoke-Jellyfin([string] $Method, [string] $Path, $Body = $null) {
    for ($try = 1; ; $try++) {
        try {
            return Invoke-JellyfinOnce $Method $Path $Body
        } catch {
            $status = $_.Exception.Response.StatusCode.value__
            if ($status -ne 503 -or $try -ge 40) { throw }
            Start-Sleep -Seconds 3
        }
    }
}

function Invoke-JellyfinOnce([string] $Method, [string] $Path, $Body) {
    $params = @{
        Method      = $Method
        Uri         = $Server + $Path
        Headers     = Get-AuthHeader
        ContentType = 'application/json; charset=utf-8'
        TimeoutSec  = 60
    }
    if ($null -ne $Body) {
        # Windows PowerShell sends strings in Latin-1 unless given bytes: names like "Анна" need UTF-8.
        $params.Body = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10 -Compress))
    }
    Invoke-RestMethod @params
}

function Wait-Server {
    $deadline = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $deadline) {
        try {
            return Invoke-RestMethod -Uri "$Server/System/Info/Public" -TimeoutSec 5
        } catch {
            Start-Sleep -Seconds 3
        }
    }
    return $null
}

# Phones find the server and connect over the home network: Jellyfin's port and its discovery
# port, for private networks only, so a laptop on a café's Wi-Fi stays closed.
function Open-Firewall {
    # Windows often files a new Wi-Fi as public, where the rules below do not apply.
    Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' -and $_.IPv4Connectivity -ne 'Disconnected' } |
        ForEach-Object {
            Write-Log "Network '$($_.Name)' set to private"
            Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
        }
    $rules = @(
        @{ Name = 'Homeplay-Jellyfin-TCP'; DisplayName = 'Homeplay: Jellyfin server (TCP 8096)'; Protocol = 'TCP'; LocalPort = 8096 },
        @{ Name = 'Homeplay-Jellyfin-Discovery'; DisplayName = 'Homeplay: Jellyfin discovery (UDP 7359)'; Protocol = 'UDP'; LocalPort = 7359 }
    )
    foreach ($r in $rules) {
        Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
        New-NetFirewallRule @r -Direction Inbound -Action Allow -Profile Private, Domain | Out-Null
        Write-Log "Firewall: $($r.DisplayName)"
    }
}

# Jellyfin's service runs as Network Service, which may not read the person's own folders
# (Videos, Music under C:\Users\...): it is let in, to read, and for photos also to write.
function Grant-Server([string] $Folder, [string] $Rights) {
    & icacls.exe $Folder /grant "*S-1-5-20:(OI)(CI)$Rights" /C /Q | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Log "icacls exit code $LASTEXITCODE for $Folder" }
}

# Jellyfin's data folder, as its installer recorded it.
function Get-DataFolder {
    foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Jellyfin\Server', 'HKLM:\SOFTWARE\Jellyfin\Server') {
        $value = (Get-ItemProperty -Path $key -Name DataFolder -ErrorAction SilentlyContinue).DataFolder
        if ($value) { return $value }
    }
    Join-Path $env:ProgramData 'Jellyfin\Server'
}

# The plugin goes to plugins\Homeplay Backup_<version>; older versions of it are taken away.
# Returns whether anything changed, i.e. Jellyfin has to start again to load it.
function Install-Plugin {
    $dll = Join-Path $Plugin 'Jellyfin.Plugin.HomeplayBackup.dll'
    $version = (Get-Item $dll).VersionInfo.FileVersion
    $plugins = Join-Path (Get-DataFolder) 'plugins'
    $target = Join-Path $plugins "Homeplay Backup_$version"
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    $changed = $false
    Get-ChildItem -Path $plugins -Directory -Filter 'Homeplay Backup_*' |
        Where-Object { $_.FullName -ne $target } |
        ForEach-Object {
            Write-Log "Removing old plugin $($_.Name)"
            Remove-Item -Recurse -Force $_.FullName
            $changed = $true
        }
    foreach ($file in Get-ChildItem -Path $Plugin -File) {
        $to = Join-Path $target $file.Name
        if (-not (Test-Path $to) -or (Get-FileHash $to).Hash -ne (Get-FileHash $file.FullName).Hash) {
            Copy-Item -Force $file.FullName $to
            $changed = $true
        }
    }
    Write-Log "Plugin $version in $target$(if ($changed) { ' (new)' })"
    $changed
}

# Jellyfin loads plugins when it starts: the service (or the tray app) starts again.
function Restart-Jellyfin {
    $service = Get-Service -Name JellyfinServer -ErrorAction SilentlyContinue
    if ($service) {
        Write-Log 'Restarting the Jellyfin service'
        Restart-Service -Name JellyfinServer -Force
        return
    }
    $running = Get-Process -Name jellyfin -ErrorAction SilentlyContinue
    if ($running) {
        Write-Log 'Restarting Jellyfin'
        $exe = $running[0].Path
        $running | Stop-Process -Force
        Start-Sleep -Seconds 3
        $tray = Join-Path (Split-Path $exe) 'jellyfin-windows-tray\Jellyfin.Windows.Tray.exe'
        if (Test-Path $tray) { Start-Process $tray } else { Start-Process $exe -WindowStyle Hidden }
    }
}

function Add-Library([string] $Name, [string] $Kind, [string] $Folder, [string] $Rights = 'RX') {
    if (-not $Folder) { return }
    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    Grant-Server $Folder $Rights
    $query = 'name={0}&collectionType={1}&paths={2}&refreshLibrary=false' -f `
        [uri]::EscapeDataString($Name), $Kind, [uri]::EscapeDataString($Folder)
    # Watched for changes: a movie copied into the folder shows up without a manual scan.
    Invoke-Jellyfin POST "/Library/VirtualFolders?$query" @{ LibraryOptions = @{ Enabled = $true; EnableRealtimeMonitor = $true; EnablePhotos = $true } } | Out-Null
    Write-Log "Library '$Name' ($Kind): $Folder"
}

$cfg = Get-Content -Raw -Encoding UTF8 -Path $Settings | ConvertFrom-Json
Write-Log "Setting up Jellyfin at $Server"

try {
    if (Install-Plugin) { Restart-Jellyfin }
} catch {
    Write-Log "Could not put the plugin in place: $($_.Exception.Message)"
    exit 2
}

$info = Wait-Server
if (-not $info) {
    Write-Log 'Jellyfin did not answer within 5 minutes'
    exit 1
}
Write-Log "Jellyfin $($info.Version), '$($info.ServerName)'"

try {
    # Unticked ("not at home", or an update on a server set up by hand): Windows' network and
    # firewall settings stay exactly as they are.
    if ([bool] $cfg.HomeNetwork) { Open-Firewall } else { Write-Log 'Network and firewall left as they are' }

    if ($info.StartupWizardCompleted) {
        # Jellyfin was here before: its users and libraries stay as they are. The plugin and the
        # app file are in place already; only the phone page is left to show.
        Write-Log 'Jellyfin was set up before: users and libraries left as they are'
        exit 0
    }

    $culture = Get-Culture
    $country = try { (New-Object Globalization.RegionInfo $culture.Name).TwoLetterISORegionName } catch { 'US' }
    # The name phones show when they find the server; Windows' own computer name
    # ("DESKTOP-4F2K9QX") would say nothing to the person.
    Invoke-Jellyfin POST '/Startup/Configuration' @{
        ServerName                = "$($cfg.Name)'s Homeplay"
        UICulture                 = 'en-US'
        MetadataCountryCode       = $country
        PreferredMetadataLanguage = $culture.TwoLetterISOLanguageName
    } | Out-Null
    # Asking for the first user creates it; then it gets the person's name and password.
    Invoke-Jellyfin GET '/Startup/User' | Out-Null
    Invoke-Jellyfin POST '/Startup/User' @{ Name = $cfg.Name; Password = $cfg.Password } | Out-Null
    try {
        Invoke-Jellyfin POST '/Startup/RemoteAccess' @{ EnableRemoteAccess = $true } | Out-Null
    } catch {
        Write-Log 'No remote access step in this Jellyfin: skipped'
    }
    Invoke-Jellyfin POST '/Startup/Complete' | Out-Null
    Write-Log "First-run wizard done, user '$($cfg.Name)'"

    $auth = Invoke-Jellyfin POST '/Users/AuthenticateByName' @{ Username = $cfg.Name; Pw = $cfg.Password }
    $script:Token = $auth.AccessToken

    Add-Library 'Movies' 'movies' $cfg.Movies
    Add-Library 'Shows' 'tvshows' $cfg.Shows
    Add-Library 'Music' 'music' $cfg.Music
    Add-Library 'Photos' 'homevideos' $cfg.Photos 'M'

    if ($cfg.Photos) {
        # The plugin has this one setting, so it is sent whole rather than read and changed: in
        # Windows PowerShell the settings read back right after setup came as an empty string.
        Invoke-Jellyfin POST "/Plugins/$PluginId/Configuration" @{ BackupFolder = $cfg.Photos } | Out-Null
        Write-Log "Photos from phones go to $($cfg.Photos)"
    }

    Invoke-Jellyfin POST '/Library/Refresh' | Out-Null
    Write-Log 'Done; libraries are being scanned'
    exit 0
} catch {
    Write-Log "Failed: $($_.Exception.Message)"
    exit 2
}
