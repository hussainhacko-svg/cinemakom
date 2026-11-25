; Cinemakom Windows installer (Inno Setup 6.5+, docs/PACKAGING.md §4).
; Per-user install (no admin rights) into %LOCALAPPDATA%\Programs\Cinemakom.
;
; Build with:
;   ISCC.exe windows\packaging\cinemakom.iss
; Or override version / paths:
;   ISCC.exe /DMyAppVersion=1.0.0 /DOutputBaseFilename=cinemakom-v1.0.0-windows-x64-setup windows\packaging\cinemakom.iss

#define MyAppName "Cinemakom"
#define MyAppExeName "cinemakom.exe"
#define MyAppPublisher "Cinemakom"
#define MyAppURL "https://github.com/sharon-xa/cinemakom"
#define MyAppId "io.github.sharon_xa.cinemakom"

#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif
#ifndef OutputBaseFilename
  #define OutputBaseFilename "cinemakom-" + MyAppVersion + "-windows-x64-setup"
#endif

[Setup]
; Fixed AppId so newer versions install cleanly over previous ones. Never change it.
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
VersionInfoVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Let Windows Restart Manager close a running Cinemakom cleanly on upgrade or
; uninstall instead of aborting silent upgrades (e.g. winget) via AppMutex.
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll
RestartApplications=no
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
LicenseFile=..\..\LICENSE
OutputDir={#OutputDir}
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
#if FileExists(CompilerPath + "Languages\Arabic.isl")
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
#endif

[CustomMessages]
english.RemoveUserData=Also remove your Cinemakom library (watch history, favorites) and settings?%n%nDownloaded videos in your Videos folder will NOT be deleted.
#if FileExists(CompilerPath + "Languages\Arabic.isl")
arabic.RemoveUserData=هل تريد أيضًا حذف مكتبة سينماكم (سجل المشاهدة والمفضلة) والإعدادات؟%n%nلن يتم حذف الفيديوهات المحمّلة في مجلد الفيديوهات.
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  LocalDataDir: String;
  RoamingDataDir: String;
  LegacyDb: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    LocalDataDir := ExpandConstant('{localappdata}\io.github.sharon_xa\Cinemakom');
    RoamingDataDir := ExpandConstant('{userappdata}\io.github.sharon_xa\Cinemakom');
    LegacyDb := ExpandConstant('{userdocs}\cinemakom.sqlite');
    if (DirExists(LocalDataDir) or DirExists(RoamingDataDir) or FileExists(LegacyDb)) and (not UninstallSilent) then
    begin
      if MsgBox(ExpandConstant('{cm:RemoveUserData}'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        if DirExists(LocalDataDir) then
        begin
          DelTree(LocalDataDir, True, True, True);
          RemoveDir(ExpandConstant('{localappdata}\io.github.sharon_xa'));
        end;
        if DirExists(RoamingDataDir) then
        begin
          DelTree(RoamingDataDir, True, True, True);
          RemoveDir(ExpandConstant('{userappdata}\io.github.sharon_xa'));
        end;
        DeleteFile(LegacyDb);
        DeleteFile(LegacyDb + '-journal');
        DeleteFile(LegacyDb + '-wal');
        DeleteFile(LegacyDb + '-shm');
      end;
    end;
  end;
end;
