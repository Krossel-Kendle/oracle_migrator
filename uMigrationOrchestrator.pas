unit uMigrationOrchestrator;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.SyncObjs,
  System.Threading,
  uTypes,
  uLogger,
  uOracleParfile;

type
  TMigrationProgressEvent = reference to procedure(const Stage: TMigrationStage;
    const Percent: Integer; const MessageText: string);
  TMigrationCompletedEvent = reference to procedure(const AResult: TMigrationResult;
    const Summary: string);

  EMigrationFatal = class(Exception);

  TMigrationOrchestrator = class
  private
    FLogger: TMigratorLogger;
    FOnProgress: TMigrationProgressEvent;
    FOnCompleted: TMigrationCompletedEvent;
    FRunningFlag: Integer;
    FWarningCount: Integer;
    procedure NotifyProgress(const Stage: TMigrationStage; const Percent: Integer;
      const MessageText: string);
    procedure RaiseFatal(const MessageText: string);
    procedure Precheck(const Request: TMigrationRequest);
    procedure PrepareFolders(const Request: TMigrationRequest; out JobWorkDir: string);
    procedure PrepareOracleDirectory(const Request: TMigrationRequest);
    procedure GenerateParfiles(const Request: TMigrationRequest; const JobWorkDir: string);
    procedure RunTransport(const Request: TMigrationRequest; const JobWorkDir: string);
    procedure RunOptionalClean(const Request: TMigrationRequest);
    procedure RunImport(const Request: TMigrationRequest; const JobWorkDir: string);
    procedure RunPostCheck(const Request: TMigrationRequest);
    function BuildRemapItems(const Request: TMigrationRequest): TArray<TTablespaceMapItem>;
    class function SplitTablespaces(const Value: string): TArray<string>; static;
    procedure RunInternal(const Request: TMigrationRequest);
  public
    constructor Create(const ALogger: TMigratorLogger);
    function IsRunning: Boolean;
    procedure Start(const Request: TMigrationRequest);
    property OnProgress: TMigrationProgressEvent read FOnProgress write FOnProgress;
    property OnCompleted: TMigrationCompletedEvent read FOnCompleted write FOnCompleted;
  end;

implementation

constructor TMigrationOrchestrator.Create(const ALogger: TMigratorLogger);
begin
  inherited Create;
  FLogger := ALogger;
end;

function TMigrationOrchestrator.IsRunning: Boolean;
begin
  Result := TInterlocked.CompareExchange(FRunningFlag, 1, 1) = 1;
end;

procedure TMigrationOrchestrator.Start(const Request: TMigrationRequest);
var
  LocalRequest: TMigrationRequest;
begin
  if TInterlocked.CompareExchange(FRunningFlag, 1, 0) <> 0 then
    raise Exception.Create('Migration job is already running');

  LocalRequest := Request;
  TTask.Run(
    procedure
    begin
      try
        RunInternal(LocalRequest);
      finally
        TInterlocked.Exchange(FRunningFlag, 0);
      end;
    end);
end;

procedure TMigrationOrchestrator.NotifyProgress(const Stage: TMigrationStage;
  const Percent: Integer; const MessageText: string);
begin
  if Assigned(FOnProgress) then
    FOnProgress(Stage, Percent, MessageText);
end;

procedure TMigrationOrchestrator.RaiseFatal(const MessageText: string);
begin
  FLogger.AddError(msFailed, MessageText);
  raise EMigrationFatal.Create(MessageText);
end;

procedure TMigrationOrchestrator.Precheck(const Request: TMigrationRequest);
begin
  NotifyProgress(msPrecheck, 5, 'Validating user input and required fields');
  FLogger.AddInfo(msPrecheck, 'Precheck started');

  if Trim(Request.Source.Schema) = '' then
    RaiseFatal('Source schema is empty');
  if Trim(Request.Target.Schema) = '' then
    RaiseFatal('Target schema is empty');
  if Trim(Request.Source.PDB) = '' then
    RaiseFatal('Source PDB is empty');
  if Trim(Request.Target.PDB) = '' then
    RaiseFatal('Target PDB is empty');
  if Trim(Request.Source.Tablespace) = '' then
    RaiseFatal('Source tablespace is empty');
  if Trim(Request.Target.Tablespace) = '' then
    RaiseFatal('Target tablespace is empty');
  if Request.Source.Port <= 0 then
    RaiseFatal('Source port is invalid');
  if Request.Target.Port <= 0 then
    RaiseFatal('Target port is invalid');

  FLogger.AddInfo(msPrecheck, 'Precheck passed');
  NotifyProgress(msPrecheck, 12, 'Precheck passed');
end;

procedure TMigrationOrchestrator.PrepareFolders(const Request: TMigrationRequest; out JobWorkDir: string);
var
  TmpDir: string;
begin
  NotifyProgress(msPrepareFolders, 15, 'Preparing server cache folders');
  JobWorkDir := TPath.Combine(Request.ServerCacheRoot, Request.JobId);
  TmpDir := TPath.Combine(JobWorkDir, 'tmp');

  try
    TDirectory.CreateDirectory(JobWorkDir);
    TDirectory.CreateDirectory(TmpDir);
  except
    on E: Exception do
      RaiseFatal('Cannot prepare server cache folders: ' + E.Message);
  end;

  FLogger.AddInfo(msPrepareFolders, 'Server cache prepared: ' + JobWorkDir);
  FLogger.AddInfo(msPrepareFolders,
    'Agent folder preparation must be executed remotely (next iteration of protocol layer)');
  NotifyProgress(msPrepareFolders, 25, 'Server folders ready');
end;

procedure TMigrationOrchestrator.PrepareOracleDirectory(const Request: TMigrationRequest);
begin
  NotifyProgress(msPrepareDirectory, 28, 'Preparing Oracle DIRECTORY scripts');
  FLogger.AddInfo(msPrepareDirectory, 'DP_DIR root on agents: ' + Request.AgentDpumpRoot);
  FLogger.AddInfo(msPrepareDirectory,
    'Remote execution of sqlplus for CREATE OR REPLACE DIRECTORY is planned in the next iteration');
  NotifyProgress(msPrepareDirectory, 35, 'DIRECTORY scripts prepared');
end;

function TMigrationOrchestrator.BuildRemapItems(
  const Request: TMigrationRequest): TArray<TTablespaceMapItem>;
var
  SourceTablespaces: TArray<string>;
  I: Integer;
begin
  SourceTablespaces := SplitTablespaces(Request.Source.Tablespace);
  if Length(SourceTablespaces) = 0 then
    SourceTablespaces := TArray<string>.Create(Request.Source.Tablespace);

  SetLength(Result, Length(SourceTablespaces));
  for I := 0 to High(SourceTablespaces) do
  begin
    Result[I].SourceTablespace := SourceTablespaces[I];
    Result[I].TargetTablespace := Request.Target.Tablespace;
  end;

  if Length(SourceTablespaces) > 1 then
  begin
    Inc(FWarningCount);
    FLogger.AddWarning(msImport,
      Format('Multiple source tablespaces detected. Auto-mapping all to target tablespace "%s".',
      [Request.Target.Tablespace]));
  end;
end;

class function TMigrationOrchestrator.SplitTablespaces(const Value: string): TArray<string>;
var
  Parts: TStringList;
  I: Integer;
  NormalizedPart: string;
  Count: Integer;
begin
  SetLength(Result, 0);
  Parts := TStringList.Create;
  Count := 0;
  try
    Parts.StrictDelimiter := True;
    Parts.Delimiter := ',';
    Parts.DelimitedText := Value;
    SetLength(Result, Parts.Count);
    for I := 0 to Parts.Count - 1 do
    begin
      NormalizedPart := Trim(Parts[I]);
      if NormalizedPart = '' then
        Continue;
      Result[Count] := NormalizedPart;
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Parts.Free;
  end;
end;

procedure TMigrationOrchestrator.GenerateParfiles(const Request: TMigrationRequest;
  const JobWorkDir: string);
var
  ExpPar: TStringList;
  ImpPar: TStringList;
  RemapItems: TArray<TTablespaceMapItem>;
  TmpDir: string;
begin
  NotifyProgress(msExport, 40, 'Generating expdp parfile');

  TmpDir := TPath.Combine(JobWorkDir, 'tmp');
  RemapItems := BuildRemapItems(Request);

  ExpPar := nil;
  ImpPar := nil;
  try
    ExpPar := TParfileBuilder.BuildExportParfile(
      Request,
      LowerCase(Request.Source.Schema) + '_%U.dmp',
      'exp_' + LowerCase(Request.Source.Schema) + '.log');
    ImpPar := TParfileBuilder.BuildImportParfile(
      Request,
      LowerCase(Request.Source.Schema) + '_%U.dmp',
      'imp_' + LowerCase(Request.Target.Schema) + '.log',
      RemapItems);

    TDirectory.CreateDirectory(TmpDir);
    TParfileBuilder.SaveParfile(TPath.Combine(TmpDir, 'exp_' + Request.JobId + '.par'), ExpPar);
    TParfileBuilder.SaveParfile(TPath.Combine(TmpDir, 'imp_' + Request.JobId + '.par'), ImpPar);
  finally
    ExpPar.Free;
    ImpPar.Free;
  end;

  FLogger.AddInfo(msExport, 'Parfiles generated in ' + TmpDir);
  NotifyProgress(msExport, 50, 'Parfiles generated');
end;

procedure TMigrationOrchestrator.RunTransport(const Request: TMigrationRequest;
  const JobWorkDir: string);
begin
  NotifyProgress(msTransport, 60, 'Transport initialization');
  Inc(FWarningCount);
  FLogger.AddWarning(msTransport,
    'Source->Server->Target transport is not implemented yet. Running in preparation-only mode.');
  FLogger.AddInfo(msTransport, 'Prepared files folder: ' + TPath.Combine(JobWorkDir, 'tmp'));
end;

procedure TMigrationOrchestrator.RunOptionalClean(const Request: TMigrationRequest);
begin
  if not Request.CleanBeforeImport then
  begin
    NotifyProgress(msClean, 70, 'Clean before import is disabled');
    Exit;
  end;

  NotifyProgress(msClean, 70, 'Clean before import requested');
  Inc(FWarningCount);
  FLogger.AddWarning(msClean,
    'Clean before import is requested, but remote clean execution is not implemented yet.');
end;

procedure TMigrationOrchestrator.RunImport(const Request: TMigrationRequest;
  const JobWorkDir: string);
begin
  NotifyProgress(msImport, 80, 'Import initialization');
  Inc(FWarningCount);
  FLogger.AddWarning(msImport,
    'Remote import execution is not implemented yet. Generated impdp parfile only.');
  FLogger.AddInfo(msImport, 'Import parfile: ' +
    TPath.Combine(TPath.Combine(JobWorkDir, 'tmp'), 'imp_' + Request.JobId + '.par'));
end;

procedure TMigrationOrchestrator.RunPostCheck(const Request: TMigrationRequest);
begin
  NotifyProgress(msPostCheck, 90, 'Post-check initialization');
  Inc(FWarningCount);
  FLogger.AddWarning(msPostCheck,
    'Post-check stage is not implemented yet. No compile_schema/invalid report was executed.');
end;

procedure TMigrationOrchestrator.RunInternal(const Request: TMigrationRequest);
var
  JobWorkDir: string;
  ResultState: TMigrationResult;
  Summary: string;
begin
  ResultState := mrFailed;
  Summary := 'Migration failed';
  FWarningCount := 0;

  FLogger.AddInfo(msIdle, 'Job started: ' + Request.JobId);
  try
    Precheck(Request);
    PrepareFolders(Request, JobWorkDir);
    PrepareOracleDirectory(Request);
    GenerateParfiles(Request, JobWorkDir);
    RunTransport(Request, JobWorkDir);
    RunOptionalClean(Request);
    RunImport(Request, JobWorkDir);
    RunPostCheck(Request);

    NotifyProgress(msCompleted, 100, 'Completed');
    if FWarningCount = 0 then
      ResultState := mrSuccess
    else
      ResultState := mrSuccessWithWarnings;
    if ResultState = mrSuccessWithWarnings then
      Summary := Format(
        'Preparation-only run completed with %d warning(s); transport/import were not executed',
        [FWarningCount])
    else
      Summary := ResultToString(ResultState);
  except
    on E: EMigrationFatal do
    begin
      ResultState := mrFailed;
      Summary := E.Message;
    end;
    on E: Exception do
    begin
      ResultState := mrFailed;
      Summary := 'Unexpected error: ' + E.Message;
      FLogger.AddError(msFailed, Summary);
    end;
  end;

  if ResultState = mrFailed then
    NotifyProgress(msFailed, 100, Summary)
  else
    NotifyProgress(msCompleted, 100, Summary);

  if Assigned(FOnCompleted) then
    FOnCompleted(ResultState, Summary);
end;

end.
