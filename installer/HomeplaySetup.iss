; HomeplaySetup.exe: a home media server in a few clicks. Asks where the movies, shows, music
; and photos are and for a name and password, downloads and installs Jellyfin, puts in the
; Homeplay plugin with the phone app, sets the server up (configure.ps1) and opens the page with
; the QR code for the phone. On a computer that has Jellyfin already, only the plugin and the app
; are put in; its users and libraries stay as they are.
;
; Silent, for tests (e.g. in Windows Sandbox), the answers come from the command line:
;   HomeplaySetup.exe /VERYSILENT /SUPPRESSMSGBOXES /NAME=Test /PASSWORD=test1234 [/MOVIES=... /SHOWS=...
;   /MUSIC=... /PHOTOS=... /HOMENETWORK=0] /LOG=C:\setup.log
;
; Built with Inno Setup 6 (installer/build.sh). Needs, built first: the plugin in
; server/Jellyfin.Plugin.HomeplayBackup/bin/Release/net10.0 and app/dist/Homeplay-<AppVersion>.apk.

#define AppVersion "0.2.0"
; Jellyfin's installer is downloaded during setup and checked against this hash: the file is not
; signed, so the hash is what says it is the real one. Version 12.1, the one the plugin is built for.
#define JellyfinUrl "https://repo.jellyfin.org/files/server/windows/stable/v12.1/amd64/jellyfin_12.1_windows-x64.exe"
#define JellyfinFile "jellyfin_12.1_windows-x64.exe"
#define JellyfinSha256 "28e11b817b3410c860733591fbb88b9248b8d0b31cf2793b65ce0588cffe3da3"
#define PluginBin "..\server\Jellyfin.Plugin.HomeplayBackup\bin\Release\net10.0"
#define PhonePage "http://localhost:8096/Homeplay/Phone"

[Setup]
AppId={{6F1C2E0A-7B4D-4C55-9A3E-2D8B1F0C9E41}
AppName=Homeplay Server
AppVersion={#AppVersion}
AppPublisher=Homeplay
AppVerName=Homeplay Server {#AppVersion}
DefaultDirName={autopf}\Homeplay
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
UninstallDisplayName=Homeplay Server
OutputDir=dist
OutputBaseFilename=HomeplaySetup
Compression=lzma2
SolidCompression=yes

[Files]
Source: "configure.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "homeplay.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PluginBin}\Jellyfin.Plugin.HomeplayBackup.dll"; DestDir: "{app}\plugin"; Flags: ignoreversion
Source: "{#PluginBin}\QRCoder.dll"; DestDir: "{app}\plugin"; Flags: ignoreversion
Source: "..\app\dist\Homeplay-{#AppVersion}.apk"; DestDir: "{app}\plugin"; DestName: "Homeplay.apk"; Flags: ignoreversion

[INI]
; A Start menu link back to the phone page, for the next phone.
Filename: "{autoprograms}\Homeplay - connect a phone.url"; Section: "InternetShortcut"; Key: "URL"; String: "{#PhonePage}"
Filename: "{autoprograms}\Homeplay - connect a phone.url"; Section: "InternetShortcut"; Key: "IconFile"; String: "{app}\homeplay.ico"
Filename: "{autoprograms}\Homeplay - connect a phone.url"; Section: "InternetShortcut"; Key: "IconIndex"; String: "0"

[UninstallDelete]
Type: files; Name: "{autoprograms}\Homeplay - connect a phone.url"

[Run]
Filename: "{#PhonePage}"; Description: "Show how to connect your phone"; Flags: postinstall shellexec nowait

[Code]
var
  FoldersPage: TInputDirWizardPage;
  AccountPage: TInputQueryWizardPage;
  HomeNetwork: TNewCheckBox;
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
    'Homeplay shows on your phone what is in these folders.',
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
  FoldersPage.Values[3] := ExpandConstant('{param:PHOTOS|' + Home + '\Pictures\Homeplay}');

  AccountPage := CreateInputQueryPage(FoldersPage.ID,
    'Your name and password',
    'You sign in with them in the Homeplay app on your phone.',
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
  HomeNetwork.Checked := ExpandConstant('{param:HOMENETWORK|1}') <> '0';

  DownloadPage := CreateDownloadPage('Downloading Jellyfin',
    'Jellyfin is the free media server Homeplay plays from.', nil);
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
    Result := 'Jellyfin is already on this computer. Setup adds Homeplay to it; ' +
      'its users and libraries stay as they are.'
  else
    Result := 'Setup downloads and installs Jellyfin (about 200 MB), then sets it up:' + NewLine +
      Space + 'Movies: ' + FoldersPage.Values[0] + NewLine +
      Space + 'TV shows: ' + FoldersPage.Values[1] + NewLine +
      Space + 'Music: ' + FoldersPage.Values[2] + NewLine +
      Space + 'Photos: ' + FoldersPage.Values[3] + NewLine +
      Space + 'Name: ' + AccountPage.Values[0];
end;

function JsonString(S: String): String;
var
  I: Integer;
  C: Char;
begin
  Result := '"';
  for I := 1 to Length(S) do begin
    C := S[I];
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(C) < 32 then
        Result := Result + Format('\u%.4x', [Ord(C)])
      else
        Result := Result + C;
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

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    SetUpServer;
    if SetupFailed <> '' then
      MsgBox(SetupFailed + #13#10#13#10 + 'What happened is written in ' +
        ExpandConstant('{commonappdata}\Homeplay\setup.log') + '.', mbError, MB_OK);
  end;
end;
