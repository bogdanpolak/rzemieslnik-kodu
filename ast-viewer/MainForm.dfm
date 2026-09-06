object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Ast Viewer'
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
  object StatusBar1: TStatusBar
    Left = 0
    Top = 562
    Width = 1099
    Height = 19
    Panels = <>
    SimplePanel = True
    SimpleText = 'Line 1, Column 1'
    Align = alBottom
  end
  object PanelTop: TPanel
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 1093
    Height = 41
    Align = alTop
    BevelOuter = bvLowered
    TabOrder = 0
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
    object btnParseText: TButton
      AlignWithMargins = True
      Left = 175
      Top = 4
      Width = 120
      Height = 33
      Align = alLeft
      Caption = 'Parse Text'
      TabOrder = 1
      OnClick = btnParseTextClick
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
    PopupMenu = PopupMenu1
    TabOrder = 1
    OnContextPopup = TreeView1ContextPopup
  end
  object Splitter1: TSplitter
    Left = 412
    Top = 50
    Width = 6
    Height = 512
    Align = alLeft
    MinSize = 180
    ExplicitLeft = 409
    ExplicitTop = 48
    ExplicitHeight = 528
  end
  object Memo1: TMemo
    AlignWithMargins = True
    Left = 418
    Top = 50
    Width = 681
    Height = 528
    Align = alClient
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -12
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    ScrollBars = ssBoth
    TabOrder = 2
    WordWrap = False
    OnClick = Memo1Click
    OnChange = Memo1Change
    OnKeyUp = Memo1KeyUp
  end
  object PopupMenu1: TPopupMenu
    Left = 128
    Top = 96
    object GoToSource1: TMenuItem
      Caption = 'Go to source'
      OnClick = GoToSource1Click
    end
  end
  object FileOpenDialog1: TFileOpenDialog
    DefaultExtension = 'pas'
    FileTypes = <
      item
        DisplayName = 'Delphi source files'
        FileMask = '*.pas;*.dpr;*.dpk;*.inc'
      end
      item
        DisplayName = 'All files'
        FileMask = '*.*'
      end>
    Options = [fdoFileMustExist, fdoPathMustExist]
    Left = 224
    Top = 96
  end
end
