#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
[Setup]
AppId={{66A88B7D-9972-4867-B1D4-C1693F5EA4C0}
AppName=风灵音乐 · Sylphy Music
AppVersion={#AppVersion}
VersionInfoVersion={#AppNumericVersion}
AppPublisher=Sylphy Music
AppPublisherURL=https://github.com/ymltsh/SylphyMusic
DefaultDirName={localappdata}\Programs\Sylphy Music
DefaultGroupName=Sylphy Music
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=sylphy-music-setup-{#ReleaseSuffix}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\sylphy_music.exe
CloseApplications=yes
RestartApplications=no
LicenseFile=..\..\LICENSE
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.zip"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\docs\THIRD_PARTY_LICENSES.txt"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\..\docs\NATIVE_DEPENDENCIES.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\..\docs\native_licenses\*"; DestDir: "{app}\docs\native_licenses"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Sylphy Music"; Filename: "{app}\sylphy_music.exe"
Name: "{autodesktop}\Sylphy Music"; Filename: "{app}\sylphy_music.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\sylphy_music.exe"; Description: "Launch Sylphy Music"; Flags: nowait postinstall skipifsilent
; No user-data deletion: updates/uninstall preserve the application support directory.
