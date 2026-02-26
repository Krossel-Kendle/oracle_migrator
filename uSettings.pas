unit uSettings;

interface

uses
  System.SysUtils,
  System.IniFiles,
  System.IOUtils,
  uTypes;

type
  TMigratorSettings = record
    LastMode: TMigratorMode;
    ServerPort: Integer;
    SourceServerIP: string;
    SourceAgentPort: Integer;
    SourceAgentPassword: string;
    TargetServerIP: string;
    TargetAgentPort: Integer;
    TargetAgentPassword: string;
    AgentDpumpRoot: string;
    ServerCacheRoot: string;
    ServerCacheKeepDays: Integer;
    OracleClientBin: string;
    class function Defaults: TMigratorSettings; static;
  end;

  TMigratorSettingsService = class
  private
    class function GetIniPath: string; static;
  public
    class function Load: TMigratorSettings; static;
    class procedure Save(const Settings: TMigratorSettings); static;
  end;

implementation

const
  SECTION_GENERAL = 'general';

  KEY_LAST_MODE = 'last_mode';
  KEY_SERVER_PORT = 'server_port';
  KEY_SOURCE_SERVER_IP = 'source_server_ip';
  KEY_SOURCE_AGENT_PORT = 'source_agent_port';
  KEY_SOURCE_AGENT_PASSWORD = 'source_agent_password';
  KEY_TARGET_SERVER_IP = 'target_server_ip';
  KEY_TARGET_AGENT_PORT = 'target_agent_port';
  KEY_TARGET_AGENT_PASSWORD = 'target_agent_password';
  KEY_AGENT_DPUMP_ROOT = 'agent_dpump_root';
  KEY_SERVER_CACHE_ROOT = 'server_cache_root';
  KEY_SERVER_CACHE_KEEP_DAYS = 'server_cache_keep_days';
  KEY_ORACLE_CLIENT_BIN = 'oracle_client_bin';

class function TMigratorSettings.Defaults: TMigratorSettings;
begin
  Result.LastMode := mmNone;
  Result.ServerPort := 5050;
  Result.SourceServerIP := '127.0.0.1';
  Result.SourceAgentPort := Result.ServerPort;
  Result.SourceAgentPassword := '';
  Result.TargetServerIP := '127.0.0.1';
  Result.TargetAgentPort := Result.ServerPort;
  Result.TargetAgentPassword := '';
  Result.AgentDpumpRoot := 'C:\dpump\kapps_migrator';
  Result.ServerCacheRoot := 'C:\dpump\kapps_migrator_server\cache';
  Result.ServerCacheKeepDays := 14;
  Result.OracleClientBin := '';
end;

class function TMigratorSettingsService.GetIniPath: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'settings.ini');
end;

class function TMigratorSettingsService.Load: TMigratorSettings;
var
  Ini: TMemIniFile;
  IniPath: string;
begin
  Result := TMigratorSettings.Defaults;
  IniPath := GetIniPath;
  if not TFile.Exists(IniPath) then
    Exit;

  Ini := TMemIniFile.Create(IniPath);
  try
    Result.LastMode := ParseMode(Ini.ReadString(SECTION_GENERAL, KEY_LAST_MODE, ModeToString(Result.LastMode)));
    Result.ServerPort := Ini.ReadInteger(SECTION_GENERAL, KEY_SERVER_PORT, Result.ServerPort);
    Result.SourceServerIP := Ini.ReadString(SECTION_GENERAL, KEY_SOURCE_SERVER_IP, Result.SourceServerIP);
    Result.SourceAgentPort := Ini.ReadInteger(SECTION_GENERAL, KEY_SOURCE_AGENT_PORT, Result.SourceAgentPort);
    Result.SourceAgentPassword := Ini.ReadString(SECTION_GENERAL, KEY_SOURCE_AGENT_PASSWORD, Result.SourceAgentPassword);
    Result.TargetServerIP := Ini.ReadString(SECTION_GENERAL, KEY_TARGET_SERVER_IP, Result.TargetServerIP);
    Result.TargetAgentPort := Ini.ReadInteger(SECTION_GENERAL, KEY_TARGET_AGENT_PORT, Result.TargetAgentPort);
    Result.TargetAgentPassword := Ini.ReadString(SECTION_GENERAL, KEY_TARGET_AGENT_PASSWORD, Result.TargetAgentPassword);
    Result.AgentDpumpRoot := Ini.ReadString(SECTION_GENERAL, KEY_AGENT_DPUMP_ROOT, Result.AgentDpumpRoot);
    Result.ServerCacheRoot := Ini.ReadString(SECTION_GENERAL, KEY_SERVER_CACHE_ROOT, Result.ServerCacheRoot);
    Result.ServerCacheKeepDays := Ini.ReadInteger(SECTION_GENERAL, KEY_SERVER_CACHE_KEEP_DAYS,
      Result.ServerCacheKeepDays);
    if Trim(Result.SourceServerIP) = '' then
      Result.SourceServerIP := '127.0.0.1';
    if Result.SourceAgentPort <= 0 then
      Result.SourceAgentPort := Result.ServerPort;
    if Trim(Result.TargetServerIP) = '' then
      Result.TargetServerIP := '127.0.0.1';
    if Result.TargetAgentPort <= 0 then
      Result.TargetAgentPort := Result.ServerPort;
    if Result.ServerCacheKeepDays < 1 then
      Result.ServerCacheKeepDays := 1;
    Result.OracleClientBin := Ini.ReadString(SECTION_GENERAL, KEY_ORACLE_CLIENT_BIN, Result.OracleClientBin);
  finally
    Ini.Free;
  end;
end;

class procedure TMigratorSettingsService.Save(const Settings: TMigratorSettings);
var
  Ini: TMemIniFile;
begin
  Ini := TMemIniFile.Create(GetIniPath);
  try
    Ini.WriteString(SECTION_GENERAL, KEY_LAST_MODE, ModeToString(Settings.LastMode));
    Ini.WriteInteger(SECTION_GENERAL, KEY_SERVER_PORT, Settings.ServerPort);
    Ini.WriteString(SECTION_GENERAL, KEY_SOURCE_SERVER_IP, Settings.SourceServerIP);
    Ini.WriteInteger(SECTION_GENERAL, KEY_SOURCE_AGENT_PORT, Settings.SourceAgentPort);
    Ini.WriteString(SECTION_GENERAL, KEY_SOURCE_AGENT_PASSWORD, Settings.SourceAgentPassword);
    Ini.WriteString(SECTION_GENERAL, KEY_TARGET_SERVER_IP, Settings.TargetServerIP);
    Ini.WriteInteger(SECTION_GENERAL, KEY_TARGET_AGENT_PORT, Settings.TargetAgentPort);
    Ini.WriteString(SECTION_GENERAL, KEY_TARGET_AGENT_PASSWORD, Settings.TargetAgentPassword);
    Ini.WriteString(SECTION_GENERAL, KEY_AGENT_DPUMP_ROOT, Settings.AgentDpumpRoot);
    Ini.WriteString(SECTION_GENERAL, KEY_SERVER_CACHE_ROOT, Settings.ServerCacheRoot);
    Ini.WriteInteger(SECTION_GENERAL, KEY_SERVER_CACHE_KEEP_DAYS, Settings.ServerCacheKeepDays);
    Ini.WriteString(SECTION_GENERAL, KEY_ORACLE_CLIENT_BIN, Settings.OracleClientBin);
    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

end.
