#define AppName "Evey Setup"
#define AppVersion "0.1.0"
#ifndef RepoRoot
#define RepoRoot "..\.."
#endif
#ifndef OutputDir
#define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{3E76D6B3-8B46-49E2-82D2-1E2F91C2A601}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=42-evey
DefaultDirName={localappdata}\EveyStack
DefaultGroupName=Evey Stack
OutputDir={#OutputDir}
OutputBaseFilename=EveySetup-{#AppVersion}-internal-test
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
UninstallDisplayName=Evey Stack
LicenseFile={#RepoRoot}\LICENSE

[Files]
Source: "{#RepoRoot}\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}\templates\*"; DestDir: "{app}\templates"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\windows\scripts\*"; DestDir: "{app}\windows\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RepoRoot}\docs\windows-install.md"; DestDir: "{app}\docs"; Flags: ignoreversion

[Icons]
Name: "{group}\Continue Evey Setup"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\windows\scripts\Install-Evey.ps1"" -InstallDirectory ""{app}"" -Tier ""{code:GetTier}"" -PluginPreset ""{code:GetPluginPreset}"" {code:GetDockerNoticeParam}"; WorkingDir: "{app}"

[Code]
var
  TierPage: TInputOptionWizardPage;
  PluginPage: TInputOptionWizardPage;
  SecretPage: TInputQueryWizardPage;
  DockerPage: TInputOptionWizardPage;
  CustomSetupExitCode: Integer;

function DockerNoticeAcceptedByParam(): Boolean;
begin
  Result := CompareText(ExpandConstant('{param:AcceptDockerNotice|}'), '1') = 0;
end;

function DockerNoticeAccepted(): Boolean;
begin
  Result := DockerPage.Values[0] or DockerNoticeAcceptedByParam();
end;

function GetCustomSetupExitCode: Integer;
begin
  Result := CustomSetupExitCode;
end;

procedure InitializeWizard();
begin
  CustomSetupExitCode := 0;

  TierPage := CreateInputOptionPage(wpSelectDir,
    'Choose stack size',
    'Start small unless this PC has enough memory.',
    'Base is recommended for first install.',
    True, False);
  TierPage.Add('base - Hermes Agent, LiteLLM, Ollama');
  TierPage.Add('services - base plus MQTT, SearXNG, Qdrant, ntfy');
  TierPage.Add('full - services plus n8n, Langfuse, Uptime Kuma');
  TierPage.Values[0] := True;

  PluginPage := CreateInputOptionPage(TierPage.ID,
    'Choose plugins',
    'Core plugins are recommended.',
    'You can add more plugins later.',
    True, False);
  PluginPage.Add('core - recommended bridge, goals, status, cost guard');
  PluginPage.Add('all - install every listed plugin group');
  PluginPage.Add('skip - do not install plugins now');
  PluginPage.Values[0] := True;

  SecretPage := CreateInputQueryPage(PluginPage.ID,
    'API keys',
    'Enter the keys used by your local agent stack.',
    'Values are hidden and written to .env. They are not passed to PowerShell command-line arguments.');
  SecretPage.Add('OpenRouter API key:', True);
  SecretPage.Add('Telegram bot token (optional):', True);
  SecretPage.Add('Discord bot token (optional):', True);

  DockerPage := CreateInputOptionPage(SecretPage.ID,
    'Docker Desktop notice',
    'Docker Desktop is required on Windows.',
    'You must personally accept Docker Desktop terms and any business license responsibility. This installer never accepts Docker terms for you.',
    False, False);
  DockerPage.Add('I understand Docker Desktop is required and I must accept Docker terms myself.');
  if DockerNoticeAcceptedByParam() then
    DockerPage.Values[0] := True;
end;

function GetTier(Param: String): String;
begin
  Result := 'base';
  if TierPage.Values[1] then Result := 'services';
  if TierPage.Values[2] then Result := 'full';
end;

function GetPluginPreset(Param: String): String;
begin
  Result := 'core';
  if PluginPage.Values[1] then Result := 'all';
  if PluginPage.Values[2] then Result := 'skip';
end;

function GetDockerNoticeParam(Param: String): String;
begin
  if DockerNoticeAccepted() then
    Result := '-AcceptDockerNotice'
  else
    Result := '';
end;

function EscapeEnvValue(Value: String): String;
begin
  Result := Value;
  StringChangeEx(Result, #13, '', True);
  StringChangeEx(Result, #10, '', True);
end;

function PowerShellQuote(Value: String): String;
begin
  Result := Value;
  StringChangeEx(Result, '''', '''''', True);
  Result := '''' + Result + '''';
end;

function QuoteArg(Value: String): String;
begin
  Result := Value;
  StringChangeEx(Result, '"', '\"', True);
  Result := '"' + Result + '"';
end;

function InstallerEnvPath(): String;
begin
  Result := ExpandConstant('{app}\.env');
end;

function ExistingInstallerEnvAvailable(): Boolean;
begin
  Result := FileExists(InstallerEnvPath());
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (PageID = SecretPage.ID) and ExistingInstallerEnvAvailable() then
    Result := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = SecretPage.ID then begin
    if (not ExistingInstallerEnvAvailable()) and (Trim(SecretPage.Values[0]) = '') then begin
      MsgBox('OpenRouter API key is required.', mbError, MB_OK);
      Result := False;
    end;
  end;

  if CurPageID = DockerPage.ID then begin
    if not DockerNoticeAccepted() then begin
      MsgBox('Please acknowledge the Docker Desktop notice before continuing.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure ProtectInstallerEnv(EnvPath: String);
var
  ResultCode: Integer;
begin
  if not Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -Command "$path=' + PowerShellQuote(EnvPath) + '; $sid=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; & icacls.exe $path /inheritance:r; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }; & icacls.exe $path /grant:r ""*${sid}:F"" ""*S-1-5-32-544:F"" ""*S-1-5-18:F""; exit $LASTEXITCODE"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then begin
    CustomSetupExitCode := 1;
    RaiseException('Could not start permission lock for .env file.');
  end;
  if ResultCode <> 0 then begin
    CustomSetupExitCode := ResultCode;
    RaiseException('Could not restrict .env file permissions.');
  end;
end;

procedure WriteInstallerEnv();
var
  EnvPath: String;
  EnvText: String;
begin
  EnvPath := InstallerEnvPath();
  if ExistingInstallerEnvAvailable() and (Trim(SecretPage.Values[0]) = '') then begin
    ProtectInstallerEnv(EnvPath);
    exit;
  end;

  EnvText :=
    '# Evey Stack - generated by Windows installer' + #13#10 +
    'OPENROUTER_API_KEY=' + EscapeEnvValue(SecretPage.Values[0]) + #13#10 +
    'TELEGRAM_BOT_TOKEN=' + EscapeEnvValue(SecretPage.Values[1]) + #13#10 +
    'DISCORD_BOT_TOKEN=' + EscapeEnvValue(SecretPage.Values[2]) + #13#10;
  if not SaveStringToFile(EnvPath, EnvText, False) then begin
    CustomSetupExitCode := 1;
    RaiseException('Could not write .env file.');
  end;
  ProtectInstallerEnv(EnvPath);
end;

procedure RunInstallFlow();
var
  Params: String;
  ResultCode: Integer;
  ShowCmd: Integer;
begin
  Params :=
    '-NoProfile -ExecutionPolicy Bypass -File ' +
    QuoteArg(ExpandConstant('{app}\windows\scripts\Install-Evey.ps1')) +
    ' -InstallDirectory ' + QuoteArg(ExpandConstant('{app}')) +
    ' -Tier ' + QuoteArg(GetTier('')) +
    ' -PluginPreset ' + QuoteArg(GetPluginPreset('')) +
    ' ' + GetDockerNoticeParam('');

  if WizardSilent() then
    ShowCmd := SW_HIDE
  else
    ShowCmd := SW_SHOW;

  if not Exec('powershell.exe', Params, ExpandConstant('{app}'), ShowCmd,
    ewWaitUntilTerminated, ResultCode) then begin
    CustomSetupExitCode := 1;
    RaiseException('Could not start Evey setup.');
  end;
  if ResultCode <> 0 then begin
    CustomSetupExitCode := ResultCode;
    RaiseException('Evey setup did not finish successfully. Check the EveySetup logs in ProgramData.');
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then begin
    WriteInstallerEnv();
    RunInstallFlow();
  end;
end;
