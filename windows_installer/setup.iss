; inno setup 6.0+ required: https://jrsoftware.org/isdl.php

#define MyAppName "Modlinq"
; the build passes the version in MODLINQ_VERSION; a dev build carries a
; suffix like 2.0.2-dev.9, which is why this is a string and not a number
#define MyAppVersion GetEnv('MODLINQ_VERSION')
#if MyAppVersion == ""
  #define MyAppVersion "0.0.0"
#endif
#define MyAppPublisher "hugobugomugo"
#define MyAppURL "https://github.com/hugobugomugo/Modlinq"
#define MyAppExeName "modlinq.exe"
#define MyAppId "{{B8E5F7A1-2C3D-4E5F-9A1B-3C4D5E6F7A8B}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
; {autopf} is Program Files for this 64-bit build; the wizard still lets the
; user point it somewhere else, which is what portable-minded users expect
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
RestartApplications=no
LicenseFile=..\LICENSE
OutputDir=output
OutputBaseFilename=modlinq-setup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; admin needed for symlink creation
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; on by default: most users expect a desktop entry after installing an app
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\mod_manager_flutter\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\assets\icon.png"; DestDir: "{app}\data\flutter_assets\assets"; Flags: ignoreversion
; the portable copy has no uninstaller, and a user who lost unins000.exe still needs a way out
Source: "uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion

[UninstallDelete]
; flutter writes next to the exe at runtime, so the folder is never empty
; just because every installed file is gone
Type: filesandordirs; Name: "{app}"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
var
  Version: TWindowsVersion;
begin
  GetWindowsVersionEx(Version);
  if Version.Major < 10 then
  begin
    MsgBox('Modlinq requires Windows 10 or newer.', mbError, MB_OK);
    Result := False;
  end
  else
    Result := True;
end;

var
  RemoveUserData: Boolean;

function InitializeUninstall(): Boolean;
begin
  RemoveUserData := MsgBox(
    'Also delete Modlinq settings, logs and cached files?' + #13#10 +
    'Your imported mod library is kept.' + #13#10 + #13#10 +
    'Mods already installed into your games are NOT removed here. To take '
    + 'those out too, cancel and use "Uninstall Modlinq" inside the app first.',
    mbConfirmation, MB_YESNO) = IDYES;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  // Reuses the shipped script rather than repeating its rules here, and runs
  // while {app} still exists so the script is still on disk.
  if (CurUninstallStep = usUninstall) and RemoveUserData then
    Exec('powershell.exe',
      '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\uninstall.ps1')
        + '" -AppDataOnly -RemoveAppData -KeepLibrary',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    MsgBox('Mod symlinks require administrator rights. Run Modlinq as administrator, or enable Developer Mode in Windows settings.',
           mbInformation, MB_OK);
  end;
end;
