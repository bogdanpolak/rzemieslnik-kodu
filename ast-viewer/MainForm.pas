unit MainForm;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.TypInfo, System.IOUtils, System.Variants,
  Winapi.Windows, Winapi.Messages,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Menus,
  DelphiAST,
  DelphiAST.Classes,
  DelphiAST.Consts,
  SemanticTools.DelphiAstParser;

type
  TForm1 = class(TForm)
    PanelTop: TPanel;
    btnLoadPasFile: TButton;
    btnParseText: TButton;
    TreeView1: TTreeView;
    Splitter1: TSplitter;
    Memo1: TMemo;
    StatusBar1: TStatusBar;
    PopupMenu1: TPopupMenu;
    GoToSource1: TMenuItem;
    FileOpenDialog1: TFileOpenDialog;
    procedure FormCreate(Sender: TObject);
    procedure btnLoadPasFileClick(Sender: TObject);
    procedure btnParseTextClick(Sender: TObject);
    procedure Memo1Change(Sender: TObject);
    procedure Memo1KeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure Memo1Click(Sender: TObject);
    procedure TreeView1ContextPopup(Sender: TObject; MousePos: TPoint;
      var Handled: Boolean);
    procedure GoToSource1Click(Sender: TObject);
  private
    FAstParser: IAstParser;
    FCurrentFileName: string;
    procedure RebuildTree(const AFileName: string; const ASourceText: string);
    procedure AddTreeNode(const AParentNode: TTreeNode; const ASyntaxNode: TSyntaxNode);
    function FormatNodeText(const ASyntaxNode: TSyntaxNode): string;
    procedure UpdateCaretStatus;
    function SelectedSyntaxNode: TSyntaxNode;
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

function NodeTypeToStr(ASyntaxNode: TSyntaxNode): string;
begin
  if ASyntaxNode = nil then
    Exit('<nil>');

  Result := GetEnumName(TypeInfo(TSyntaxNodeType), Ord(ASyntaxNode.Typ));
  if Result = '' then
    Exit('<unknown>');

  if SameText(Result, 'ntInterface') then
    Exit('Interface');

  Result := StringReplace(Result, 'nt', '', []);
end;

procedure TForm1.AddTreeNode(const AParentNode: TTreeNode; const ASyntaxNode: TSyntaxNode);
var
  TreeNode: TTreeNode;
  ChildNode: TSyntaxNode;
begin
  if ASyntaxNode = nil then
    Exit;

  if AParentNode = nil then
    TreeNode := TreeView1.Items.Add(nil, FormatNodeText(ASyntaxNode))
  else
    TreeNode := TreeView1.Items.AddChild(AParentNode, FormatNodeText(ASyntaxNode));
  TreeNode.Data := ASyntaxNode;

  for ChildNode in ASyntaxNode.ChildNodes do
    AddTreeNode(TreeNode, ChildNode);
end;

function TForm1.FormatNodeText(const ASyntaxNode: TSyntaxNode): string;
var
  DisplayName: string;
  SourceLine: string;
  EqualsPosition: Integer;
begin
  Result := NodeTypeToStr(ASyntaxNode);

  if ASyntaxNode is TValuedSyntaxNode then
    Result := Result + ' = ' + (ASyntaxNode as TValuedSyntaxNode).Value;

  DisplayName := ASyntaxNode.GetAttribute(anName);
  if DisplayName = '' then
    DisplayName := ASyntaxNode.GetAttribute(anPath);
  if (DisplayName <> '') and not (ASyntaxNode is TValuedSyntaxNode) then
    Result := Result + ': ' + DisplayName;

  if (ASyntaxNode.Line > 0) and (ASyntaxNode.Line <= Memo1.Lines.Count) then
  begin
    SourceLine := Trim(Memo1.Lines[ASyntaxNode.Line - 1]);
    if ASyntaxNode.Typ = ntTypeDecl then
    begin
      EqualsPosition := Pos('=', SourceLine);
      if EqualsPosition > 1 then
        Result := 'Type: ' + Trim(Copy(SourceLine, 1, EqualsPosition - 1));
    end
    else if ASyntaxNode.Typ = ntUses then
      Result := 'Uses: ' + Trim(StringReplace(SourceLine, 'uses', '', [rfIgnoreCase]));
  end;

  if ASyntaxNode.Line > 0 then
    Result := Result + ' (line ' + IntToStr(ASyntaxNode.Line) + ')';
end;

procedure TForm1.RebuildTree(const AFileName: string; const ASourceText: string);
var
  SyntaxTree: TSyntaxNode;
  SourceStream: TStringStream;
  RootNode: TTreeNode;
  FileName: string;
begin
  TreeView1.Items.BeginUpdate;
  try
    TreeView1.Items.Clear;

    if Trim(ASourceText) = '' then
      Exit;

    FileName := AFileName;
    if FileName = '' then
      FileName := 'source.pas';

    SourceStream := TStringStream.Create(ASourceText, TEncoding.UTF8);
    try
      if not FAstParser.TryParseStream(SourceStream, FileName, SyntaxTree) then
      begin
        TreeView1.Items.Add(nil, 'Parse failed: ' + FAstParser.GetFailureMessage);
        Exit;
      end;

      RootNode := TreeView1.Items.Add(nil, FileName + ' [' + NodeTypeToStr(SyntaxTree) + ']');
      RootNode.Data := SyntaxTree;
      for var ChildNode in SyntaxTree.ChildNodes do
        AddTreeNode(RootNode, ChildNode);

      TreeView1.FullExpand;
    finally
      SourceStream.Free;
    end;
  finally
    TreeView1.Items.EndUpdate;
  end;
end;

procedure TForm1.btnLoadPasFileClick(Sender: TObject);
var
  SelectedFile: string;
  SourceText: string;
begin
  if not FileOpenDialog1.Execute then
    Exit;

  SelectedFile := FileOpenDialog1.FileName;
  FCurrentFileName := SelectedFile;
  SourceText := TFile.ReadAllText(SelectedFile, TEncoding.UTF8);
  Memo1.Text := SourceText;
  RebuildTree(SelectedFile, SourceText);
end;

procedure TForm1.btnParseTextClick(Sender: TObject);
begin
  RebuildTree(FCurrentFileName, Memo1.Text);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  FAstParser := CreateAstParser();
  Memo1.Font.Name := 'Consolas';
  Memo1.ScrollBars := ssBoth;
  Memo1.WordWrap := False;
  Memo1.Lines.Text := 'program Demo;' + sLineBreak +
    sLineBreak +
    'type' + sLineBreak +
    '  TDemo = class' + sLineBreak +
    '  private' + sLineBreak +
    '    FValue: Integer;' + sLineBreak +
    '  public' + sLineBreak +
    '    constructor Create;' + sLineBreak +
    '    function GetValue: Integer;' + sLineBreak +
    '  end;' + sLineBreak +
    sLineBreak +
    'constructor TDemo.Create;' + sLineBreak +
    'begin' + sLineBreak +
    '  FValue := 42;' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'function TDemo.GetValue: Integer;' + sLineBreak +
    'begin' + sLineBreak +
    '  Result := FValue;' + sLineBreak +
    'end;' + sLineBreak +
    sLineBreak +
    'begin' + sLineBreak +
    'end.';
  FCurrentFileName := 'source.pas';
  RebuildTree(FCurrentFileName, Memo1.Text);
  UpdateCaretStatus;
end;

procedure TForm1.Memo1Change(Sender: TObject);
begin
  RebuildTree(FCurrentFileName, Memo1.Text);
  UpdateCaretStatus;
end;

procedure TForm1.Memo1Click(Sender: TObject);
begin
  UpdateCaretStatus;
end;

procedure TForm1.Memo1KeyUp(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  UpdateCaretStatus;
end;

procedure TForm1.UpdateCaretStatus;
begin
  StatusBar1.SimpleText := Format('Line %d, Column %d',
    [Memo1.CaretPos.Y + 1, Memo1.CaretPos.X + 1]);
end;

function TForm1.SelectedSyntaxNode: TSyntaxNode;
begin
  Result := nil;
  if (TreeView1.Selected <> nil) and (TreeView1.Selected.Data <> nil) then
    Result := TSyntaxNode(TreeView1.Selected.Data);
end;

procedure TForm1.TreeView1ContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
var
  Node: TTreeNode;
begin
  Node := TreeView1.GetNodeAt(MousePos.X, MousePos.Y);
  if Node <> nil then
    TreeView1.Selected := Node;
  GoToSource1.Enabled := SelectedSyntaxNode <> nil;
end;

procedure TForm1.GoToSource1Click(Sender: TObject);
var
  Node: TSyntaxNode;
  LineIndex: Integer;
begin
  Node := SelectedSyntaxNode;
  if (Node = nil) or (Node.Line <= 0) then
    Exit;

  LineIndex := Node.Line - 1;
  if LineIndex >= Memo1.Lines.Count then
    LineIndex := Memo1.Lines.Count - 1;
  if LineIndex < 0 then
    Exit;

  Memo1.SetFocus;
  Memo1.CaretPos := Point(0, LineIndex);
  Memo1.Perform(EM_SCROLLCARET, 0, 0);
  UpdateCaretStatus;
end;

end.
