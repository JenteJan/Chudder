#define SourcePath ".."

#ifndef CHUDDER_VERSION
  #define CHUDDER_VERSION "latest"
#endif

[Setup]
AppId={{7C4E9A16-2B8D-4E51-9F3A-1D6C0B8E4A72}
AppName="Chudder"
AppVersion={#CHUDDER_VERSION}
AppPublisher="Jente"
AppPublisherURL="https://github.com/JenteJan/Chudder"
AppSupportURL="https://github.com/JenteJan/Chudder/issues"
AppUpdatesURL="https://github.com/JenteJan/Chudder/releases"
DefaultDirName={localappdata}\Programs\Chudder
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputBaseFilename=chudder_setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern

SetupLogging=yes
UninstallLogging=yes
UninstallDisplayName="Chudder"
UninstallDisplayIcon={app}\chudder.exe
SetupIconFile="{#SourcePath}\icons\production\chudder_icon.ico"
LicenseFile="{#SourcePath}\LICENSE"
WizardImageFile={#SourcePath}\assets\windows-installer\chudder-installer-100.bmp,{#SourcePath}\assets\windows-installer\chudder-installer-125.bmp,{#SourcePath}\assets\windows-installer\chudder-installer-150.bmp

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourcePath}\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Chudder"; Filename: "{app}\chudder.exe"
Name: "{autodesktop}\Chudder"; Filename: "{app}\chudder.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\chudder.exe"; Description: "{cm:LaunchProgram,Chudder}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  case CurUninstallStep of
    usUninstall:
      begin
        if MsgBox('Would you like to delete the application''s data? This action cannot be undone. Synced files will remain unaffected.', mbConfirmation, MB_YESNO) = IDYES then
        begin
            if DelTree(ExpandConstant('{localappdata}\Chudder'), True, True, True) = False then
            begin
                Log(ExpandConstant('{localappdata}\Chudder could not be deleted. Skipping...'));
            end;
        end;
      end;
  end;
end;
