object LogForm: TLogForm
  Left = 0
  Top = 0
  Caption = 'Migration Log'
  ClientHeight = 520
  ClientWidth = 900
  Color = clBtnFace
  Constraints.MinHeight = 360
  Constraints.MinWidth = 620
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 15
  object memLog: TMemo
    Left = 0
    Top = 0
    Width = 900
    Height = 481
    Align = alClient
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
    WantReturns = False
    WordWrap = False
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 481
    Width = 900
    Height = 39
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnSaveOutput: TButton
      Left = 12
      Top = 7
      Width = 120
      Height = 25
      Caption = 'Save output'
      TabOrder = 0
      OnClick = btnSaveOutputClick
    end
  end
  object dlgSaveLog: TSaveDialog
    DefaultExt = 'txt'
    Filter = 'Text files (*.txt)|*.txt|All files (*.*)|*.*'
    Left = 176
    Top = 488
  end
end
