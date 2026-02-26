unit uProcessRunner;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils;

type
  TProcessOutputEvent = reference to procedure(const Line: string);

  TProcessRunResult = record
    ExitCode: Cardinal;
    TimedOut: Boolean;
    Output: TArray<string>;
  end;

  TProcessRunner = class
  private
    class function ResolveExecutable(const ExePath: string): string; static;
    class procedure DrainPipe(const ReadHandle: THandle; OutputLines: TStrings;
      var PendingLine: string; const OnOutput: TProcessOutputEvent); static;
    class procedure FlushPending(OutputLines: TStrings; var PendingLine: string;
      const OnOutput: TProcessOutputEvent); static;
  public
    class function Run(const ExePath: string; const Arguments: string; const WorkDir: string;
      const TimeoutMs: Cardinal; const OnOutput: TProcessOutputEvent = nil): TProcessRunResult; static;
  end;

implementation

function ExpandEnvironmentVars(const Value: string): string;
var
  RequiredLen: DWORD;
begin
  Result := Value;
  if Value = '' then
    Exit;
  RequiredLen := ExpandEnvironmentStrings(PChar(Value), nil, 0);
  if RequiredLen = 0 then
    Exit;
  SetLength(Result, RequiredLen - 1);
  if ExpandEnvironmentStrings(PChar(Value), PChar(Result), RequiredLen) = 0 then
    Result := Value;
end;

function NormalizePathToken(const Value: string): string;
begin
  Result := Trim(StringReplace(Value, '"', '', [rfReplaceAll]));
  Result := ExpandEnvironmentVars(Result);
  Result := Trim(Result);
end;

class function TProcessRunner.ResolveExecutable(const ExePath: string): string;
var
  InputPath: string;
  SearchPathValue: string;
  SearchDirs: TStringList;
  PathParts: TStringList;
  Part: string;
  NormalizedPart: string;
  OracleHome: string;
  Candidate: string;
  BaseName: string;
  HasPathSeparator: Boolean;
begin
  InputPath := NormalizePathToken(ExePath);
  if InputPath = '' then
    raise Exception.Create('Executable path is empty');

  if FileExists(InputPath) then
    Exit(InputPath);

  HasPathSeparator := (Pos('\', InputPath) > 0) or (Pos('/', InputPath) > 0);
  if HasPathSeparator then
  begin
    if TPath.GetExtension(InputPath) = '' then
    begin
      Candidate := InputPath + '.exe';
      if FileExists(Candidate) then
        Exit(Candidate);
    end;
    raise Exception.CreateFmt('Executable not found: %s', [InputPath]);
  end;

  BaseName := InputPath;
  if TPath.GetExtension(BaseName) = '' then
    BaseName := BaseName + '.exe';

  SearchPathValue := GetEnvironmentVariable('PATH');
  SearchDirs := TStringList.Create;
  PathParts := TStringList.Create;
  try
    OracleHome := NormalizePathToken(GetEnvironmentVariable('ORACLE_HOME'));
    if OracleHome <> '' then
    begin
      Candidate := TPath.Combine(OracleHome, 'bin');
      if TDirectory.Exists(Candidate) and (SearchDirs.IndexOf(Candidate) < 0) then
        SearchDirs.Add(Candidate);
    end;

    PathParts.StrictDelimiter := True;
    PathParts.Delimiter := ';';
    PathParts.DelimitedText := SearchPathValue;
    for Part in PathParts do
    begin
      NormalizedPart := NormalizePathToken(Part);
      if NormalizedPart = '' then
        Continue;
      if SearchDirs.IndexOf(NormalizedPart) < 0 then
        SearchDirs.Add(NormalizedPart);
    end;

    for NormalizedPart in SearchDirs do
    begin
      Candidate := TPath.Combine(NormalizedPart, BaseName);
      if FileExists(Candidate) then
        Exit(Candidate);
    end;
  finally
    SearchDirs.Free;
    PathParts.Free;
  end;

  raise Exception.CreateFmt('Executable not found: %s', [InputPath]);
end;

class procedure TProcessRunner.DrainPipe(const ReadHandle: THandle; OutputLines: TStrings;
  var PendingLine: string; const OnOutput: TProcessOutputEvent);
var
  Available: DWORD;
  ReadBytes: DWORD;
  Buffer: array[0..4095] of Byte;
  Chunk: TBytes;
  TextChunk: string;
  NewLinePos: Integer;
  LineText: string;
begin
  while True do
  begin
    if not PeekNamedPipe(ReadHandle, nil, 0, nil, @Available, nil) then
      Break;
    if Available = 0 then
      Break;

    if not ReadFile(ReadHandle, Buffer[0], SizeOf(Buffer), ReadBytes, nil) then
      Break;
    if ReadBytes = 0 then
      Break;

    SetLength(Chunk, ReadBytes);
    Move(Buffer[0], Chunk[0], ReadBytes);
    TextChunk := TEncoding.ANSI.GetString(Chunk);
    PendingLine := PendingLine + TextChunk;

    while True do
    begin
      NewLinePos := Pos(#10, PendingLine);
      if NewLinePos = 0 then
        Break;

      LineText := Copy(PendingLine, 1, NewLinePos - 1);
      if (LineText <> '') and (LineText[Length(LineText)] = #13) then
        Delete(LineText, Length(LineText), 1);
      OutputLines.Add(LineText);
      if Assigned(OnOutput) then
        OnOutput(LineText);
      Delete(PendingLine, 1, NewLinePos);
    end;
  end;
end;

class procedure TProcessRunner.FlushPending(OutputLines: TStrings; var PendingLine: string;
  const OnOutput: TProcessOutputEvent);
begin
  if PendingLine = '' then
    Exit;

  OutputLines.Add(PendingLine);
  if Assigned(OnOutput) then
    OnOutput(PendingLine);
  PendingLine := '';
end;

class function TProcessRunner.Run(const ExePath: string; const Arguments: string;
  const WorkDir: string; const TimeoutMs: Cardinal; const OnOutput: TProcessOutputEvent): TProcessRunResult;
var
  Security: TSecurityAttributes;
  StdOutRead: THandle;
  StdOutWrite: THandle;
  StartInfo: TStartupInfoW;
  ProcessInfo: TProcessInformation;
  CommandLine: string;
  WaitResult: DWORD;
  OutputLines: TStringList;
  PendingLine: string;
  ExitCode: DWORD;
  Index: Integer;
  StartTick: UInt64;
  TimedOut: Boolean;
  WorkDirPtr: PWideChar;
  ResolvedExePath: string;
begin
  Result := Default(TProcessRunResult);
  ResolvedExePath := ResolveExecutable(ExePath);

  StdOutRead := 0;
  StdOutWrite := 0;
  FillChar(Security, SizeOf(Security), 0);
  Security.nLength := SizeOf(Security);
  Security.bInheritHandle := True;

  if not CreatePipe(StdOutRead, StdOutWrite, @Security, 0) then
    RaiseLastOSError;
  try
    if not SetHandleInformation(StdOutRead, HANDLE_FLAG_INHERIT, 0) then
      RaiseLastOSError;

    FillChar(StartInfo, SizeOf(StartInfo), 0);
    FillChar(ProcessInfo, SizeOf(ProcessInfo), 0);
    StartInfo.cb := SizeOf(StartInfo);
    StartInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartInfo.wShowWindow := SW_HIDE;
    StartInfo.hStdInput := GetStdHandle(STD_INPUT_HANDLE);
    StartInfo.hStdOutput := StdOutWrite;
    StartInfo.hStdError := StdOutWrite;

    CommandLine := '"' + ResolvedExePath + '"';
    if Trim(Arguments) <> '' then
      CommandLine := CommandLine + ' ' + Arguments;
    UniqueString(CommandLine);

    if Trim(WorkDir) = '' then
      WorkDirPtr := nil
    else
      WorkDirPtr := PWideChar(WorkDir);

    if not CreateProcessW(nil, PWideChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW,
      nil, WorkDirPtr, StartInfo, ProcessInfo) then
      RaiseLastOSError;
    try
      CloseHandle(StdOutWrite);
      StdOutWrite := 0;

      OutputLines := TStringList.Create;
      try
        PendingLine := '';
        TimedOut := False;
        StartTick := GetTickCount64;
        repeat
          WaitResult := WaitForSingleObject(ProcessInfo.hProcess, 50);
          DrainPipe(StdOutRead, OutputLines, PendingLine, OnOutput);
          if (WaitResult = WAIT_TIMEOUT) and (TimeoutMs > 0) and
             ((GetTickCount64 - StartTick) >= UInt64(TimeoutMs)) then
          begin
            TimedOut := True;
            TerminateProcess(ProcessInfo.hProcess, 1);
            WaitForSingleObject(ProcessInfo.hProcess, 5000);
            Break;
          end;
        until WaitResult <> WAIT_TIMEOUT;

        if WaitResult = WAIT_FAILED then
          RaiseLastOSError;

        DrainPipe(StdOutRead, OutputLines, PendingLine, OnOutput);
        FlushPending(OutputLines, PendingLine, OnOutput);

        if TimedOut then
        begin
          Result.TimedOut := True;
          Result.ExitCode := 1;
        end
        else
        begin
          if not GetExitCodeProcess(ProcessInfo.hProcess, ExitCode) then
            RaiseLastOSError;
          Result.ExitCode := ExitCode;
          Result.TimedOut := False;
        end;

        SetLength(Result.Output, OutputLines.Count);
        for Index := 0 to OutputLines.Count - 1 do
          Result.Output[Index] := OutputLines[Index];
      finally
        OutputLines.Free;
      end;
    finally
      CloseHandle(ProcessInfo.hProcess);
      CloseHandle(ProcessInfo.hThread);
    end;
  finally
    if StdOutRead <> 0 then
      CloseHandle(StdOutRead);
    if StdOutWrite <> 0 then
      CloseHandle(StdOutWrite);
  end;
end;

end.
