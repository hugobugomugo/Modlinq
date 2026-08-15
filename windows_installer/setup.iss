; inno setup 6.0+ required: https://jrsoftware.org/isdl.php

#define MyAppName "Modlinq"
#define MyAppVersion "2.0.0"
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
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
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
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\mod_manager_flutter\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\assets\icon.png"; DestDir: "{app}\data\flutter_assets\assets"; Flags: ignoreversion

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

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    MsgBox('Mod symlinks require administrator rights. Run Modlinq as administrator, or enable Developer Mode in Windows settings.',
           mbInformation, MB_OK);
  end;
end;
