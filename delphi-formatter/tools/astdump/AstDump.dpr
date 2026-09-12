program AstDump;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils, Classes, TypInfo,
  DelphiAST, DelphiAST.Classes, DelphiAST.Consts;

procedure Dump(Node: TSyntaxNode; Indent: Integer);
var
  S: string;
  Attr: TAttributeEntry;
  Child: TSyntaxNode;
begin
  S := StringOfChar(' ', Indent * 2) + GetEnumName(TypeInfo(TSyntaxNodeType), Ord(Node.Typ));
  S := S + Format(' [%d:%d', [Node.Line, Node.Col]);
  if Node is TCompoundSyntaxNode then
    S := S + Format('..%d:%d', [TCompoundSyntaxNode(Node).EndLine, TCompoundSyntaxNode(Node).EndCol]);
  S := S + ']';
  if Node is TValuedSyntaxNode then
    S := S + ' value="' + TValuedSyntaxNode(Node).Value + '"';
  for Attr in Node.Attributes do
    S := S + ' ' + GetEnumName(TypeInfo(TAttributeName), Ord(Attr.Key)) + '=' + Attr.Value;
  Writeln(S);
  for Child in Node.ChildNodes do
    Dump(Child, Indent + 1);
end;

var
  Builder: TPasSyntaxTreeBuilder;
  Stream: TStringStream;
  Root: TSyntaxNode;
  C: TCommentNode;
  Src: TStringList;
begin
  Src := TStringList.Create;
  try
    Src.LoadFromFile(ParamStr(1));
    Stream := TStringStream.Create(Src.Text);
  finally
    Src.Free;
  end;
  try
    Builder := TPasSyntaxTreeBuilder.Create;
    try
      Builder.InitDefinesDefinedByCompiler;
      Root := nil;
      try
        Root := Builder.Run(Stream);
      except
        on E: ESyntaxTreeException do
        begin
          Writeln('PARSE ERROR ', E.Line, ':', E.Col, ' ', E.Message);
          Writeln('--- partial tree ---');
          if E.SyntaxTree <> nil then Dump(E.SyntaxTree, 0);
          Halt(1);
        end;
      end;
      try
        Dump(Root, 0);
        Writeln('--- comments (', Builder.Comments.Count, ') ---');
        for C in Builder.Comments do
          Writeln(Format('%s [%d:%d] "%s"', [GetEnumName(TypeInfo(TSyntaxNodeType), Ord(C.Typ)), C.Line, C.Col, C.Text]));
      finally
        Root.Free;
      end;
    finally
      Builder.Free;
    end;
  finally
    Stream.Free;
  end;
end.
