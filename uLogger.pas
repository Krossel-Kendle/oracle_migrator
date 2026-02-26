unit uLogger;

interface

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.SyncObjs,
  uTypes;

type
  TLogEvent = reference to procedure(const Line: string);

  TMigratorLogger = class
  private
    FCriticalSection: TCriticalSection;
    FLines: TStringList;
    FOnLog: TLogEvent;
    function BuildLine(const Level: TLogLevel; const Stage: TMigrationStage; const MessageText: string): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure Add(const Level: TLogLevel; const Stage: TMigrationStage; const MessageText: string);
    procedure AddInfo(const Stage: TMigrationStage; const MessageText: string);
    procedure AddWarning(const Stage: TMigrationStage; const MessageText: string);
    procedure AddError(const Stage: TMigrationStage; const MessageText: string);
    procedure AddRaw(const MessageText: string);
    function Snapshot: TArray<string>;
    procedure SaveToFile(const FileName: string);
    class function MaskSecrets(const Value: string; const Secrets: TArray<string>): string; static;
    property OnLog: TLogEvent read FOnLog write FOnLog;
  end;

implementation

constructor TMigratorLogger.Create;
begin
  inherited Create;
  FCriticalSection := TCriticalSection.Create;
  FLines := TStringList.Create;
end;

destructor TMigratorLogger.Destroy;
begin
  FLines.Free;
  FCriticalSection.Free;
  inherited;
end;

function TMigratorLogger.BuildLine(const Level: TLogLevel; const Stage: TMigrationStage; const MessageText: string): string;
const
  LEVEL_NAMES: array[TLogLevel] of string = ('INFO', 'WARN', 'ERROR');
begin
  Result := Format('[%s] [%s] [%s] %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), StageToString(Stage), LEVEL_NAMES[Level], MessageText]);
end;

procedure TMigratorLogger.Clear;
begin
  FCriticalSection.Acquire;
  try
    FLines.Clear;
  finally
    FCriticalSection.Release;
  end;
end;

procedure TMigratorLogger.Add(const Level: TLogLevel; const Stage: TMigrationStage; const MessageText: string);
var
  Line: string;
  Handler: TLogEvent;
begin
  Line := BuildLine(Level, Stage, MessageText);
  FCriticalSection.Acquire;
  try
    FLines.Add(Line);
    Handler := FOnLog;
  finally
    FCriticalSection.Release;
  end;

  if Assigned(Handler) then
    Handler(Line);
end;

procedure TMigratorLogger.AddInfo(const Stage: TMigrationStage; const MessageText: string);
begin
  Add(llInfo, Stage, MessageText);
end;

procedure TMigratorLogger.AddWarning(const Stage: TMigrationStage; const MessageText: string);
begin
  Add(llWarning, Stage, MessageText);
end;

procedure TMigratorLogger.AddError(const Stage: TMigrationStage; const MessageText: string);
begin
  Add(llError, Stage, MessageText);
end;

procedure TMigratorLogger.AddRaw(const MessageText: string);
var
  Handler: TLogEvent;
begin
  FCriticalSection.Acquire;
  try
    FLines.Add(MessageText);
    Handler := FOnLog;
  finally
    FCriticalSection.Release;
  end;

  if Assigned(Handler) then
    Handler(MessageText);
end;

function TMigratorLogger.Snapshot: TArray<string>;
var
  I: Integer;
begin
  FCriticalSection.Acquire;
  try
    SetLength(Result, FLines.Count);
    for I := 0 to FLines.Count - 1 do
      Result[I] := FLines[I];
  finally
    FCriticalSection.Release;
  end;
end;

procedure TMigratorLogger.SaveToFile(const FileName: string);
begin
  FCriticalSection.Acquire;
  try
    FLines.SaveToFile(FileName, TEncoding.UTF8);
  finally
    FCriticalSection.Release;
  end;
end;

class function TMigratorLogger.MaskSecrets(const Value: string; const Secrets: TArray<string>): string;
var
  Secret: string;
begin
  Result := Value;
  for Secret in Secrets do
  begin
    if Secret = '' then
      Continue;
    Result := AnsiReplaceStr(Result, Secret, '********');
  end;
end;

end.
