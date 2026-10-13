; OwnMediaSetup.exe: a home media server in a few clicks. Asks where the movies, shows, music
; and photos are and for a name and password, downloads and installs Jellyfin, puts in the
; Homeplay Backup plugin with the OwnMedia phone app, sets the server up (configure.ps1) and opens the page with
; the QR code for the phone. On a computer that has Jellyfin already, only the plugin and the app
; are put in; its users and libraries stay as they are.
;
; Silent, for tests (e.g. in Windows Sandbox), the answers come from the command line:
;   OwnMediaSetup.exe /VERYSILENT /SUPPRESSMSGBOXES /NAME=Test /PASSWORD=test1234 [/MOVIES=... /SHOWS=...
;   /MUSIC=... /PHOTOS=... /HOMENETWORK=0] /LOG=C:\setup.log
;
; Built with Inno Setup 6 (installer/build.sh). Needs, built first: the plugin in
; server/Jellyfin.Plugin.HomeplayBackup/bin/Release/net10.0 and app/dist/OwnMedia-<AppVersion>.apk.

#define AppVersion "0.3.8"
; Jellyfin's installer is downloaded during setup and checked against this hash: the file is not
; signed, so the hash is what says it is the real one. Version 12.1, the one the plugin is built for.
#define JellyfinUrl "https://repo.jellyfin.org/files/server/windows/stable/v12.1/amd64/jellyfin_12.1_windows-x64.exe"
#define JellyfinFile "jellyfin_12.1_windows-x64.exe"
#define JellyfinSha256 "28e11b817b3410c860733591fbb88b9248b8d0b31cf2793b65ce0588cffe3da3"
#define PluginBin "..\server\Jellyfin.Plugin.HomeplayBackup\bin\Release\net10.0"
#define PhonePage "http://localhost:8096/Homeplay/Phone"

[Setup]
AppId={{6F1C2E0A-7B4D-4C55-9A3E-2D8B1F0C9E41}
AppName=OwnMedia Server
AppVersion={#AppVersion}
AppPublisher=OwnMedia
AppVerName=OwnMedia Server {#AppVersion}
; A server set up before the name OwnMedia keeps its folder: Setup reuses the folder of the
; install it updates.
DefaultDirName={autopf}\OwnMedia
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
SetupIconFile=homeplay.ico
UninstallDisplayIcon={app}\homeplay.ico
UninstallDisplayName=OwnMedia Server
OutputDir=dist
OutputBaseFilename=OwnMediaSetup
Compression=lzma2
SolidCompression=yes

[Files]
Source: "configure.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "internet.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "homeplay.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PluginBin}\Jellyfin.Plugin.HomeplayBackup.dll"; DestDir: "{app}\plugin"; Flags: ignoreversion
Source: "{#PluginBin}\QRCoder.dll"; DestDir: "{app}\plugin"; Flags: ignoreversion
; The plugin is GPL; its source is public. The notices go with it.
Source: "..\server\LICENSE"; DestDir: "{app}\plugin"; DestName: "LICENSE.txt"; Flags: ignoreversion
Source: "..\server\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}\plugin"; Flags: ignoreversion
Source: "..\app\dist\OwnMedia-{#AppVersion}.apk"; DestDir: "{app}\plugin"; DestName: "OwnMedia.apk"; Flags: ignoreversion

[INI]
; A Start menu link back to the phone page, for the next phone.
Filename: "{autoprograms}\OwnMedia - connect a phone.url"; Section: "InternetShortcut"; Key: "URL"; String: "{#PhonePage}"
Filename: "{autoprograms}\OwnMedia - connect a phone.url"; Section: "InternetShortcut"; Key: "IconFile"; String: "{app}\homeplay.ico"
Filename: "{autoprograms}\OwnMedia - connect a phone.url"; Section: "InternetShortcut"; Key: "IconIndex"; String: "0"

[InstallDelete]
; Left by a setup from before the name OwnMedia: they would be copied to the server again.
Type: files; Name: "{app}\plugin\Homeplay.apk"
Type: files; Name: "{app}\plugin\HomeplaySetup.exe"
Type: files; Name: "{autoprograms}\Homeplay - connect a phone.url"

[UninstallDelete]
Type: files; Name: "{autoprograms}\OwnMedia - connect a phone.url"
Type: files; Name: "{app}\plugin\OwnMediaSetup.exe"

[Run]
Filename: "{#PhonePage}"; Description: "Show how to connect your phone"; Flags: postinstall shellexec nowait skipifsilent

[Code]
var
  FoldersPage: TInputDirWizardPage;
  AccountPage: TInputQueryWizardPage;
  HomeNetwork: TNewCheckBox;
  InternetPage: TInputOptionWizardPage;
  DownloadPage: TDownloadWizardPage;
  HasJellyfin: Boolean;
  SetupFailed: String;

function JellyfinInstalled: Boolean;
var
  Folder: String;
begin
  Result := RegQueryStringValue(HKLM32, 'SOFTWARE\Jellyfin\Server', 'InstallFolder', Folder)
    or RegQueryStringValue(HKLM64, 'SOFTWARE\Jellyfin\Server', 'InstallFolder', Folder);
end;

procedure InitializeWizard;
var
  Home: String;
begin
  HasJellyfin := JellyfinInstalled;
  Home := GetEnv('USERPROFILE');

  FoldersPage := CreateInputDirPage(wpWelcome,
    'Your movies, shows, music and photos',
    'OwnMedia shows on your phone what is in these folders.',
    'Put new movies and music into them any time: they show up by themselves. ' +
    'Photos from your phone are saved into the last one. Leave a line empty to skip it.',
    False, '');
  FoldersPage.Add('Movies:');
  FoldersPage.Add('TV shows (a folder for each show):');
  FoldersPage.Add('Music:');
  FoldersPage.Add('Photos:');
  FoldersPage.Values[0] := ExpandConstant('{param:MOVIES|' + Home + '\Videos\Movies}');
  FoldersPage.Values[1] := ExpandConstant('{param:SHOWS|' + Home + '\Videos\Shows}');
  FoldersPage.Values[2] := ExpandConstant('{param:MUSIC|' + Home + '\Music}');
  FoldersPage.Values[3] := ExpandConstant('{param:PHOTOS|' + Home + '\Pictures\OwnMedia}');

  AccountPage := CreateInputQueryPage(FoldersPage.ID,
    'Your name and password',
    'You sign in with them in the OwnMedia app on your phone.',
    'Choose a password you will remember.');
  AccountPage.Add('Name:', False);
  AccountPage.Add('Password:', True);
  AccountPage.Add('Password again:', True);
  AccountPage.Values[0] := ExpandConstant('{param:NAME|' + GetUserNameString + '}');
  AccountPage.Values[1] := ExpandConstant('{param:PASSWORD|}');
  AccountPage.Values[2] := AccountPage.Values[1];

  HomeNetwork := TNewCheckBox.Create(AccountPage);
  HomeNetwork.Parent := AccountPage.Surface;
  HomeNetwork.Top := AccountPage.Edits[2].Top + AccountPage.Edits[2].Height + ScaleY(20);
  HomeNetwork.Width := AccountPage.SurfaceWidth;
  HomeNetwork.Height := ScaleY(34);
  HomeNetwork.Caption := 'This computer is at home: let phones on this Wi-Fi connect to it';
  // The question is on a page an update skips: an update leaves Windows' network and firewall as
  // they are unless asked otherwise with /HOMENETWORK=1.
  if HasJellyfin then
    HomeNetwork.Checked := ExpandConstant('{param:HOMENETWORK|0}') = '1'
  else
    HomeNetwork.Checked := ExpandConstant('{param:HOMENETWORK|1}') <> '0';

  // Shown on updates too: a server set up before can be opened to friends later.
  InternetPage := CreateInputOptionPage(AccountPage.ID,
    'Watch from anywhere',
    'Friends, and you away from home, reach this server over the internet.',
    'OwnMedia does it with Tailscale, a free service that gives the server a safe address ' +
    'without router settings. Setup installs it; you only sign in once in your browser ' +
    '(the Google, Microsoft or Apple button is quickest) and press Connect. ' +
    'Then "Share with friends" in the app makes invite links right away.',
    False, False);
  InternetPage.Add('Let friends watch from anywhere');
  // A silent install opens no browser unless asked to with /INTERNET=1.
  if WizardSilent then
    InternetPage.Values[0] := ExpandConstant('{param:INTERNET|0}') = '1'
  else
    InternetPage.Values[0] := ExpandConstant('{param:INTERNET|1}') <> '0';

  DownloadPage := CreateDownloadPage('Downloading Jellyfin',
    'Jellyfin is the free media server OwnMedia plays from.', nil);
end;

// With Jellyfin already there, its users and libraries stay: nothing to ask.
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := HasJellyfin and ((PageID = FoldersPage.ID) or (PageID = AccountPage.ID));
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = AccountPage.ID then begin
    if Trim(AccountPage.Values[0]) = '' then begin
      MsgBox('Please enter a name.', mbError, MB_OK);
      Result := False;
    end else if Length(AccountPage.Values[1]) < 4 then begin
      MsgBox('The password needs at least 4 characters.', mbError, MB_OK);
      Result := False;
    end else if AccountPage.Values[1] <> AccountPage.Values[2] then begin
      MsgBox('The two passwords are different. Please type them again.', mbError, MB_OK);
      AccountPage.Values[1] := '';
      AccountPage.Values[2] := '';
      Result := False;
    end;
  end else if (CurPageID = wpReady) and not HasJellyfin then begin
    DownloadPage.Clear;
    DownloadPage.Add('{#JellyfinUrl}', '{#JellyfinFile}', '{#JellyfinSha256}');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
      except
        if DownloadPage.AbortedByUser then
          Log('Download aborted')
        else
          MsgBox('Jellyfin could not be downloaded. Check the internet connection and try again.' + #13#10#13#10 +
            GetExceptionMessage, mbError, MB_OK);
        Result := False;
      end;
    finally
      DownloadPage.Hide;
    end;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  if HasJellyfin then
    Result := 'Jellyfin is already on this computer. Setup adds OwnMedia to it; ' +
      'its users and libraries stay as they are.'
  else
    Result := 'Setup downloads and installs Jellyfin (about 200 MB), then sets it up:' + NewLine +
      Space + 'Movies: ' + FoldersPage.Values[0] + NewLine +
      Space + 'TV shows: ' + FoldersPage.Values[1] + NewLine +
      Space + 'Music: ' + FoldersPage.Values[2] + NewLine +
      Space + 'Photos: ' + FoldersPage.Values[3] + NewLine +
      Space + 'Name: ' + AccountPage.Values[0];
  if InternetPage.Values[0] then
    Result := Result + NewLine + NewLine + 'Then it opens the server to the internet with Tailscale: ' +
      'a browser window opens for you to sign in and allow it.';
end;

function JsonString(S: String): String;
var
  I: Integer;
  C: Integer;
begin
  // Character codes, not #-literals: a line starting with # is a preprocessor directive.
  Result := '"';
  for I := 1 to Length(S) do begin
    C := Ord(S[I]);
    case C of
      34: Result := Result + '\"';
      92: Result := Result + '\\';
      8: Result := Result + '\b';
      9: Result := Result + '\t';
      10: Result := Result + '\n';
      12: Result := Result + '\f';
      13: Result := Result + '\r';
    else
      if C < 32 then
        Result := Result + Format('\u%.4x', [C])
      else
        Result := Result + S[I];
    end;
  end;
  Result := Result + '"';
end;

function JsonBool(B: Boolean): String;
begin
  if B then Result := 'true' else Result := 'false';
end;

procedure Status(Text: String);
begin
  WizardForm.StatusLabel.Caption := Text;
  WizardForm.FilenameLabel.Caption := '';
end;

// A silent install never clicks Next on the Ready page: Jellyfin is fetched here instead.
function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  if not HasJellyfin and not FileExists(ExpandConstant('{tmp}\{#JellyfinFile}')) then
    try
      DownloadTemporaryFile('{#JellyfinUrl}', '{#JellyfinFile}', '{#JellyfinSha256}', nil);
    except
      Result := 'Jellyfin could not be downloaded: ' + GetExceptionMessage;
    end;
end;

procedure SetUpServer;
var
  Settings: String;
  Lines: TArrayOfString;
  Code: Integer;
begin
  if not HasJellyfin then begin
    Status('Installing Jellyfin...');
    if not Exec(ExpandConstant('{tmp}\{#JellyfinFile}'), '/S', '', SW_HIDE, ewWaitUntilTerminated, Code) or (Code <> 0) then begin
      SetupFailed := 'Jellyfin could not be installed (code ' + IntToStr(Code) + ').';
      Exit;
    end;
  end;

  Status('Setting up the server. This takes a minute or two...');
  // A copy of this very installer goes next to the plugin: friends invited to this server
  // download it from the invite page to make a server of their own.
  if not CopyFile(ExpandConstant('{srcexe}'), ExpandConstant('{app}\plugin\OwnMediaSetup.exe'), False) then
    Log('Could not copy the installer next to the plugin');
  // The password goes to the script in a file in Setup's own temporary folder, deleted right after.
  Settings := ExpandConstant('{tmp}\settings.json');
  SetArrayLength(Lines, 1);
  Lines[0] := '{' +
    '"Name":' + JsonString(Trim(AccountPage.Values[0])) + ',' +
    '"Password":' + JsonString(AccountPage.Values[1]) + ',' +
    '"Movies":' + JsonString(FoldersPage.Values[0]) + ',' +
    '"Shows":' + JsonString(FoldersPage.Values[1]) + ',' +
    '"Music":' + JsonString(FoldersPage.Values[2]) + ',' +
    '"Photos":' + JsonString(FoldersPage.Values[3]) + ',' +
    '"HomeNetwork":' + JsonBool(HomeNetwork.Checked) + '}';
  SaveStringsToUTF8File(Settings, Lines, False);
  try
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\configure.ps1') + '"' +
      ' -Settings "' + Settings + '" -Plugin "' + ExpandConstant('{app}\plugin') + '"',
      '', SW_HIDE, ewWaitUntilTerminated, Code) then
      Code := -1;
  finally
    DeleteFile(Settings);
  end;
  case Code of
    0: ;
    1: SetupFailed := 'Jellyfin did not start.';
  else
    SetupFailed := 'The server could not be set up (code ' + IntToStr(Code) + ').';
  end;
end;

function SetWindowPos(Wnd: HWND; InsertAfter: HWND; X, Y, Width, Height: Integer; Flags: Cardinal): Boolean;
  external 'SetWindowPos@user32.dll stdcall';

// The browser windows were on top, and Windows does not let a window in the back take the focus:
// Setup is put above them for a moment instead, so that its last page is seen.
procedure ComeBackOnTop;
begin
  BringToFrontAndRestore;
  // HWND_TOPMOST, then HWND_NOTOPMOST; SWP_NOSIZE or SWP_NOMOVE or SWP_SHOWWINDOW.
  SetWindowPos(WizardForm.Handle, HWND(-1), 0, 0, 0, 0, $43);
  SetWindowPos(WizardForm.Handle, HWND(-2), 0, 0, 0, 0, $43);
end;

// Runs one step of internet.ps1 and gives back its exit code.
function InternetStep(Step, Text: String): Integer;
var
  Code: Integer;
begin
  Status(Text);
  if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\internet.ps1') + '" -Step ' + Step,
    '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Code := -1;
  Result := Code;
end;

// Opens the server to the internet with Tailscale (internet.ps1), a step at a time so that the
// status line says what Setup waits for. Not having it is no failure: the server works at home
// all the same, and running Setup again tries again.
procedure OpenToInternet;
var
  Code: Integer;
  Problem: String;
begin
  Code := InternetStep('install', 'Installing Tailscale...');
  if Code = 0 then
    Code := InternetStep('signin', 'In the browser window that opens, sign in to Tailscale and press Connect...');
  if Code = 0 then
    Code := InternetStep('funnel', 'Turning on access from the internet. If Tailscale asks in the browser, press Enable Funnel...');
  if Code = 0 then
    Code := InternetStep('wait', 'Waiting until the server opens from the internet. This can take up to 10 minutes...');
  ComeBackOnTop;
  case Code of
    0: Exit;
    3: Problem := 'Tailscale could not be installed. Check the internet connection.';
    4: Problem := 'Nobody signed in to Tailscale in time.';
    5: Problem := 'Tailscale did not get the permission to put the server on the internet in time.';
    7: begin
      SuppressibleMsgBox('The server is on the internet, but its address is still new: invite links may ' +
        'not open for a few more minutes. Wait a little before sending them.', mbInformation, MB_OK, IDOK);
      Exit;
    end;
  else
    Problem := 'The server could not be opened to the internet (code ' + IntToStr(Code) + ').';
  end;
  SuppressibleMsgBox(Problem + #13#10#13#10 +
    'The server works at home as before. To let friends watch from anywhere, run OwnMediaSetup ' +
    'again. What happened is written in ' + ExpandConstant('{commonappdata}\Homeplay\setup.log') + '.',
    mbInformation, MB_OK, IDOK);
end;

// A silent install that could not set the server up says so in its exit code.
function GetCustomSetupExitCode: Integer;
begin
  if SetupFailed <> '' then Result := 2 else Result := 0;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    SetUpServer;
    if SetupFailed <> '' then
      SuppressibleMsgBox(SetupFailed + #13#10#13#10 + 'What happened is written in ' +
        ExpandConstant('{commonappdata}\Homeplay\setup.log') + '.', mbError, MB_OK, IDOK)
    else if InternetPage.Values[0] then
      OpenToInternet;
  end;
end;
