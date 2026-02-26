[Setup]
AppName=SmartSpin2k Flasher
AppVersion={#GetEnv('APP_VERSION')}
AppPublisher=SmartSpin2k
AppPublisherURL=https://github.com/doudar/SmartSpin2kFlasher
DefaultDirName={autopf}\SmartSpin2k Flasher
DefaultGroupName=SmartSpin2k Flasher
OutputDir=..\
OutputBaseFilename=SmartSpin2kFlasher-windows-setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\smartspin2k_flasher.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequired=lowest

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\SmartSpin2k Flasher"; Filename: "{app}\smartspin2k_flasher.exe"
Name: "{group}\Uninstall SmartSpin2k Flasher"; Filename: "{uninstallexe}"
Name: "{autodesktop}\SmartSpin2k Flasher"; Filename: "{app}\smartspin2k_flasher.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\smartspin2k_flasher.exe"; Description: "Launch SmartSpin2k Flasher"; Flags: nowait postinstall skipifsilent
