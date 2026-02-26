unit uOracleParfile;

interface

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.StrUtils,
  uTypes;

type
  TParfileBuilder = class
  private
    class function ConnectionString(const Conn: TOracleConnectionInfo): string; static;
    class function JoinSchemaUser(const Conn: TOracleConnectionInfo): string; static;
    class function QuoteParfileValue(const Value: string): string; static;
  public
    class function BuildExportParfile(const Request: TMigrationRequest; const DumpPattern: string;
      const LogFileName: string): TStringList; static;
    class function BuildImportParfile(const Request: TMigrationRequest; const DumpPattern: string;
      const LogFileName: string; const RemapItems: TArray<TTablespaceMapItem>): TStringList; static;
    class procedure SaveParfile(const FileName: string; const Content: TStrings); static;
  end;

implementation

class function TParfileBuilder.ConnectionString(const Conn: TOracleConnectionInfo): string;
begin
  Result := Format('//%s:%d/%s', [Trim(Conn.Host), Conn.Port, Trim(Conn.PDB)]);
end;

class function TParfileBuilder.JoinSchemaUser(const Conn: TOracleConnectionInfo): string;
begin
  Result := Format('%s/%s@%s',
    [Trim(Conn.Schema), Conn.SchemaPassword, ConnectionString(Conn)]);
end;

class function TParfileBuilder.QuoteParfileValue(const Value: string): string;
begin
  Result := '"' + StringReplace(Value, '"', '""', [rfReplaceAll]) + '"';
end;

class function TParfileBuilder.BuildExportParfile(const Request: TMigrationRequest;
  const DumpPattern: string; const LogFileName: string): TStringList;
begin
  Result := TStringList.Create;
  Result.Add('userid=' + QuoteParfileValue(JoinSchemaUser(Request.Source)));
  Result.Add('schemas=' + Trim(Request.Source.Schema));
  Result.Add('directory=DP_DIR');
  Result.Add('dumpfile=' + DumpPattern);
  Result.Add('logfile=' + LogFileName);
  Result.Add('parallel=4');
  Result.Add('compression=all');
  Result.Add('exclude=statistics');
end;

class function TParfileBuilder.BuildImportParfile(const Request: TMigrationRequest;
  const DumpPattern: string; const LogFileName: string;
  const RemapItems: TArray<TTablespaceMapItem>): TStringList;
var
  MapItem: TTablespaceMapItem;
  SourceSchemaUpper: string;
  TargetSchemaUpper: string;
begin
  Result := TStringList.Create;
  Result.Add('userid=' + QuoteParfileValue(JoinSchemaUser(Request.Target)));
  Result.Add('schemas=' + Trim(Request.Source.Schema));
  SourceSchemaUpper := UpperCase(Trim(Request.Source.Schema));
  TargetSchemaUpper := UpperCase(Trim(Request.Target.Schema));
  if (SourceSchemaUpper <> '') and (TargetSchemaUpper <> '') and
     (not SameText(SourceSchemaUpper, TargetSchemaUpper)) then
    Result.Add(Format('remap_schema=%s:%s', [SourceSchemaUpper, TargetSchemaUpper]));
  Result.Add('directory=DP_DIR');
  Result.Add('dumpfile=' + DumpPattern);
  Result.Add('logfile=' + LogFileName);
  Result.Add('parallel=4');
  Result.Add('transform=segment_attributes:n');
  for MapItem in RemapItems do
    Result.Add(Format('remap_tablespace=%s:%s', [MapItem.SourceTablespace, MapItem.TargetTablespace]));
end;

class procedure TParfileBuilder.SaveParfile(const FileName: string; const Content: TStrings);
var
  Utf8NoBom: TUTF8Encoding;
begin
  TDirectory.CreateDirectory(ExtractFilePath(FileName));
  Utf8NoBom := TUTF8Encoding.Create(False);
  try
    Content.SaveToFile(FileName, Utf8NoBom);
  finally
    Utf8NoBom.Free;
  end;
end;

end.
