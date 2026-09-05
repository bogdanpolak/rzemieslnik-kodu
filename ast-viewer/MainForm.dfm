object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'FormMain'
  ClientHeight = 581
  ClientWidth = 1099
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  TextHeight = 15
  object PanelTop: TPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 1093
    Height = 41
    Align = alTop
    BevelOuter = bvLowered
    TabOrder = 0
    ExplicitLeft = 464
    ExplicitTop = 288
    ExplicitWidth = 185
    object btnLoadPasFile: TButton
      AlignWithMargins = True
      Left = 4
      Top = 4
      Width = 165
      Height = 33
      Align = alLeft
      Caption = 'Load Pas File'
      TabOrder = 0
      OnClick = btnLoadPasFileClick
    end
  end
  object TreeView1: TTreeView
    AlignWithMargins = True
    Left = 3
    Top = 50
    Width = 406
    Height = 528
    Align = alLeft
    Indent = 19
    TabOrder = 1
  end
end
