unit uTypes;

interface

uses
  System.SysUtils;

type
  TMigratorMode = (mmNone, mmServer, mmSource, mmTarget);
  TConnectionStatus = (csDisconnected, csConnected, csAuthFailed, csConnectionFailed);
  TLogLevel = (llInfo, llWarning, llError);
  TMigrationStage = (msIdle, msPrecheck, msPrepareFolders, msPrepareDirectory, msExport,
    msTransport, msClean, msImport, msPostCheck, msCompleted, msFailed);
  TMigrationResult = (mrSuccess, mrSuccessWithWarnings, mrFailed);

  TTablespaceInfo = record
    PrimaryTablespace: string;
    AllTablespaces: TArray<string>;
  end;

  TOracleConnectionInfo = record
    Host: string;
    Port: Integer;
    PDB: string;
    SysUser: string;
    SysPassword: string;
    Schema: string;
    SchemaPassword: string;
    Tablespace: string;
  end;

  TTablespaceMapItem = record
    SourceTablespace: string;
    TargetTablespace: string;
  end;

  TMigrationRequest = record
    JobId: string;
    Source: TOracleConnectionInfo;
    Target: TOracleConnectionInfo;
    CleanBeforeImport: Boolean;
    AgentDpumpRoot: string;
    ServerCacheRoot: string;
  end;

function ModeToString(const Mode: TMigratorMode): string;
function StageToString(const Stage: TMigrationStage): string;
function ResultToString(const AResult: TMigrationResult): string;
function ConnectionStatusToString(const Status: TConnectionStatus): string;
function ParseMode(const Value: string): TMigratorMode;

implementation

function ModeToString(const Mode: TMigratorMode): string;
begin
  case Mode of
    mmServer: Result := 'Server';
    mmSource: Result := 'Source';
    mmTarget: Result := 'Target';
  else
    Result := 'None';
  end;
end;

function StageToString(const Stage: TMigrationStage): string;
begin
  case Stage of
    msIdle: Result := 'Idle';
    msPrecheck: Result := 'Precheck';
    msPrepareFolders: Result := 'PrepareFolders';
    msPrepareDirectory: Result := 'PrepareDirectory';
    msExport: Result := 'Export';
    msTransport: Result := 'Transport';
    msClean: Result := 'Clean';
    msImport: Result := 'Import';
    msPostCheck: Result := 'PostCheck';
    msCompleted: Result := 'Completed';
    msFailed: Result := 'Failed';
  else
    Result := 'Unknown';
  end;
end;

function ResultToString(const AResult: TMigrationResult): string;
begin
  case AResult of
    mrSuccess: Result := 'Success';
    mrSuccessWithWarnings: Result := 'Success with warnings';
    mrFailed: Result := 'Failed';
  else
    Result := 'Unknown';
  end;
end;

function ConnectionStatusToString(const Status: TConnectionStatus): string;
begin
  case Status of
    csDisconnected: Result := 'Disconnected';
    csConnected: Result := 'Connected';
    csAuthFailed: Result := 'Auth failed';
    csConnectionFailed: Result := 'Connection failed';
  else
    Result := 'Unknown';
  end;
end;

function ParseMode(const Value: string): TMigratorMode;
var
  LValue: string;
begin
  LValue := Trim(LowerCase(Value));
  if LValue = 'server' then
    Exit(mmServer);
  if LValue = 'source' then
    Exit(mmSource);
  if LValue = 'target' then
    Exit(mmTarget);
  Result := mmNone;
end;

end.
