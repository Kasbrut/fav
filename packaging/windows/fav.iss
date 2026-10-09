#ifndef AppVersion
  #error AppVersion must be provided with /DAppVersion=...
#endif
#ifndef SourceDir
  #error SourceDir must be provided with /DSourceDir=...
#endif
#ifndef OutputDir
  #error OutputDir must be provided with /DOutputDir=...
#endif

[Setup]
AppId={{B2B4A5DB-7D21-4D44-BB0F-6FB607C0B1E4}
AppName=FAV
AppVersion={#AppVersion}
AppPublisher=FAV contributors
DefaultDirName={localappdata}\Programs\FAV
DefaultGroupName=FAV
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=fav-{#AppVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\fav.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\FAV"; Filename: "{app}\fav.exe"
Name: "{autodesktop}\FAV"; Filename: "{app}\fav.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Run]
Filename: "{app}\fav.exe"; Description: "Launch FAV"; Flags: nowait postinstall skipifsilent
