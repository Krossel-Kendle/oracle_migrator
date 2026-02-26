unit uLogForm;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ExtCtrls;

type
  TLogForm = class(TForm)
    pnlBottom: TPanel;
    btnSaveOutput: TButton;
    dlgSaveLog: TSaveDialog;
    memLog: TMemo;
    procedure btnSaveOutputClick(Sender: TObject);
  private
  public
    procedure AppendLine(const Line: string);
    procedure SetLines(const Lines: TArray<string>);
    procedure ClearLog;
  end;

implementation

{$R *.dfm}

procedure TLogForm.btnSaveOutputClick(Sender: TObject);
begin
  if not dlgSaveLog.Execute(Handle) then
    Exit;
  memLog.Lines.SaveToFile(dlgSaveLog.FileName, TEncoding.UTF8);
end;

procedure TLogForm.AppendLine(const Line: string);
begin
  memLog.Lines.Add(Line);
  memLog.SelStart := Length(memLog.Text);
  memLog.Perform(EM_SCROLLCARET, 0, 0);
end;

procedure TLogForm.ClearLog;
begin
  memLog.Clear;
end;

procedure TLogForm.SetLines(const Lines: TArray<string>);
var
  Line: string;
begin
  memLog.Lines.BeginUpdate;
  try
    memLog.Clear;
    for Line in Lines do
      memLog.Lines.Add(Line);
  finally
    memLog.Lines.EndUpdate;
  end;
end;

end.
