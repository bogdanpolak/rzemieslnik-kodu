unit DelphiAST.Formatter.Engine;

{
  Delphi source formatter built on DelphiAST (variant C - hybrid).

  Pipeline:
    Source --> TPasSyntaxTreeBuilder --> AST (structure + positions)
    Source --> TmwPasLex (UseDefines = False) --> every token, incl. whitespace,
               comments and compiler directives
    AST + tokens --> TLayoutPlanner marks tokens with "break before / indent"
    tokens + marks --> TTokenEmitter writes the result

  Why hybrid: the DelphiAST tree is semantic and lossy (no directives, no
  comments, dequoted string literals, dropped modifiers such as "packed" or
  "static"). Emitting text from tokens guarantees that every token of the
  input appears in the output exactly once; the AST is used only to decide
  where lines break and how deep they are indented.
}

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  // TypInfo first: its ptXxx constants must be shadowed by the lexer's enum
  TypInfo,
  SysUtils,
  Classes,
  Generics.Collections,
  SimpleParser.Lexer,
  SimpleParser.Lexer.Types,
  DelphiAST,
  DelphiAST.Classes,
  DelphiAST.Consts;

type
  EDelphiFormatterException = class(Exception);

  TSyntaxNodeTypeSet = set of TSyntaxNodeType;

  { One lexical token of the input, including whitespace and comments. }
  TFormatterToken = record
    Kind: TptTokenKind;
    { Kind with context keywords resolved (private, strict, static, on, ...)
      which the lexer reports as ptIdentifier + ExID. }
    GenKind: TptTokenKind;
    Text: string;
    Line: Integer;
    Col: Integer;
  end;

  { Full token stream of a source text with a (Line, Col) -> index map. }
  TSourceTokens = class
  private
    FItems: TList<TFormatterToken>;
    FPositionIndex: TDictionary<Int64, Integer>;
    function GetCount: Integer;
    function GetItem(AIndex: Integer): TFormatterToken;
    procedure AddToken(AKind, AGenKind: TptTokenKind; const AText: string; ALine, ACol: Integer);
    class function PositionKey(ALine, ACol: Integer): Int64; static;
  public
    constructor Create(const ASource: string);
    destructor Destroy; override;
    function IndexOfPosition(ALine, ACol: Integer): Integer;
    function IsSignificant(AIndex: Integer): Boolean;
    function PrevSignificant(AIndex: Integer): Integer;
    function NextSignificant(AIndex: Integer): Integer;
    function KindAt(AIndex: Integer): TptTokenKind;
    function GenKindAt(AIndex: Integer): TptTokenKind;
    class function IsComment(AKind: TptTokenKind): Boolean; static;
    class function IsDirective(AKind: TptTokenKind): Boolean; static;
    class function IsWhitespace(AKind: TptTokenKind): Boolean; static;
    property Count: Integer read GetCount;
    property Items[AIndex: Integer]: TFormatterToken read GetItem; default;
  end;

  { Layout decision attached to a token by the planner. }
  TLayoutMark = record
    BreakBefore: Boolean;
    BlankBefore: Boolean;
    JoinPrevious: Boolean;
    GenericBracket: Boolean;
    Indent: Integer;
  end;

  { Which node types were given a dedicated layout rule and which only
    passed through as plain tokens. Informational - nothing is ever lost. }
  TFormatterCoverage = record
    Handled: TSyntaxNodeTypeSet;
    Unhandled: TSyntaxNodeTypeSet;
    function HandledNames: string;
    function UnhandledNames: string;
  end;

  TDelphiCodeFormatter = class
  private
    FCoverage: TFormatterCoverage;
    function ParseSource(const ASourceCode: string): TSyntaxNode;
  public
    function FormatSource(const ASourceCode: string): string;
    { Concatenation of all non-whitespace tokens; equal for input and output
      of FormatSource - the formatter's structure-preservation invariant. }
    class function TokenFingerprint(const ASourceCode: string): string;
    property Coverage: TFormatterCoverage read FCoverage;
  end;

implementation

const
  IndentWidth = 2;
  LineBreak = #13#10;

type
  TPtTokenKindSet = set of TptTokenKind;

const
  VisibilityNodeTypes: TSyntaxNodeTypeSet =
    [ntPrivate, ntProtected, ntPublic, ntPublished, ntStrictPrivate, ntStrictProtected];
  SectionNodeTypes: TSyntaxNodeTypeSet =
    [ntInterface, ntImplementation, ntInitialization, ntFinalization];
  DeclarationSectionTypes: TSyntaxNodeTypeSet =
    [ntUses, ntTypeSection, ntConstants, ntVariables, ntExports];
  DirectiveTokens: TPtTokenKindSet =
    [ptCompDirect, ptDefineDirect, ptElseDirect, ptEndIfDirect, ptIfDefDirect,
     ptIfNDefDirect, ptIfOptDirect, ptIncludeDirect, ptResourceDirect,
     ptScopedEnumsDirect, ptUndefDirect, ptIfDirect, ptIfEndDirect, ptElseIfDirect];
  CommentTokens: TPtTokenKindSet = [ptAnsiComment, ptBorComment, ptSlashesComment];
  WhitespaceTokens: TPtTokenKindSet = [ptSpace, ptCRLF, ptCRLFCo];
  { Keywords after which a blank line carries no information. }
  OpenerTokens: TPtTokenKindSet =
    [ptBegin, ptThen, ptElse, ptDo, ptOf, ptTry, ptRepeat, ptFinally, ptExcept,
     ptRoundOpen, ptUses, ptVar, ptConst, ptType, ptLabel, ptThreadvar,
     ptResourcestring, ptPrivate, ptProtected, ptPublic, ptPublished, ptRecord,
     ptClass, ptColon, ptAsm, ptExports];
  { Tokens that close a block; a blank line directly before them is dropped. }
  CloserTokens: TPtTokenKindSet = [ptEnd, ptUntil, ptFinally, ptExcept, ptElse];
  { Tokens directly followed by "(" or "[" without a space. }
  CallableTokens: TPtTokenKindSet =
    [ptIdentifier, ptRoundClose, ptSquareClose, ptPointerSymbol, ptProcedure,
     ptFunction, ptArray, ptString, ptAnsiString, ptWideString, ptShortString,
     ptInteger, ptCardinal, ptBoolean, ptByte, ptWord, ptLongint, ptLongword,
     ptInt64, ptShortint, ptSmallint, ptDWORD, ptChar, ptWideChar, ptPChar,
     ptDouble, ptSingle, ptExtended, ptReal, ptReal48, ptComp, ptCurrency,
     ptVariant, ptOleVariant, ptByteBool, ptWordBool, ptLongBool, ptStringConst,
     ptInherited, ptClass, ptInterface, ptDispinterface, ptObject];
  { Tokens after which "+" / "-" is a unary sign. }
  SignPrefixTokens: TPtTokenKindSet =
    [ptRoundOpen, ptSquareOpen, ptComma, ptAssign, ptEqual, ptNotEqual, ptLower,
     ptLowerEqual, ptGreater, ptGreaterEqual, ptPlus, ptMinus, ptStar, ptSlash,
     ptDiv, ptMod, ptAnd, ptOr, ptXor, ptShl, ptShr, ptNot, ptColon, ptSemiColon,
     ptThen, ptElse, ptOf, ptDo, ptTo, ptDownto, ptUntil, ptWhile, ptIf, ptIn,
     ptCase, ptDotDot];
  MemberPrefixTokens: TPtTokenKindSet = [ptClass, ptVar, ptConst, ptThreadvar, ptStrict];
  LiteralTokens: TPtTokenKindSet = [ptStringConst, ptAsciiChar];

function NodeTypeName(AType: TSyntaxNodeType): string;
begin
  Result := GetEnumName(TypeInfo(TSyntaxNodeType), Ord(AType));
end;

{ TFormatterCoverage }

function SetNames(const ASet: TSyntaxNodeTypeSet): string;
var
  NodeType: TSyntaxNodeType;
begin
  Result := '';
  for NodeType := Low(TSyntaxNodeType) to High(TSyntaxNodeType) do
    if NodeType in ASet then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + NodeTypeName(NodeType);
    end;
end;

function TFormatterCoverage.HandledNames: string;
begin
  Result := SetNames(Handled);
end;

function TFormatterCoverage.UnhandledNames: string;
begin
  Result := SetNames(Unhandled);
end;

{ TSourceTokens }

constructor TSourceTokens.Create(const ASource: string);
var
  Lexer: TmwPasLex;
  ExpectedPos: Integer;
  Gap: string;
begin
  inherited Create;
  FItems := TList<TFormatterToken>.Create;
  FPositionIndex := TDictionary<Int64, Integer>.Create;
  if ASource = '' then
    Exit;

  Lexer := TmwPasLex.Create;
  try
    // Every {$IFDEF} branch must stay visible: the lexer evaluates nothing.
    Lexer.UseDefines := False;
    Lexer.Origin := ASource;
    ExpectedPos := 0;
    while Lexer.TokenID <> ptNull do
    begin
      // The lexer swallows {$I file} directives internally when no include
      // handler is set. Any gap between consecutive tokens is text the lexer
      // skipped; re-inject it verbatim so nothing is lost.
      if Lexer.TokenPos > ExpectedPos then
      begin
        Gap := Copy(ASource, ExpectedPos + 1, Lexer.TokenPos - ExpectedPos);
        if Trim(Gap) <> '' then
          AddToken(ptIncludeDirect, ptIncludeDirect, Trim(Gap), Lexer.PosXY.Y, Lexer.PosXY.X);
      end;
      AddToken(Lexer.TokenID, Lexer.GenID, Lexer.Token, Lexer.PosXY.Y, Lexer.PosXY.X);
      ExpectedPos := Lexer.TokenPos + Lexer.TokenLen;
      Lexer.Next;
    end;
  finally
    Lexer.Free;
  end;
end;

destructor TSourceTokens.Destroy;
begin
  FPositionIndex.Free;
  FItems.Free;
  inherited;
end;

procedure TSourceTokens.AddToken(AKind, AGenKind: TptTokenKind; const AText: string;
  ALine, ACol: Integer);
var
  Token: TFormatterToken;
begin
  Token.Kind := AKind;
  Token.GenKind := AGenKind;
  Token.Text := AText;
  Token.Line := ALine;
  Token.Col := ACol;
  FItems.Add(Token);
  FPositionIndex.AddOrSetValue(PositionKey(ALine, ACol), FItems.Count - 1);
end;

class function TSourceTokens.PositionKey(ALine, ACol: Integer): Int64;
begin
  Result := (Int64(ALine) shl 32) or Int64(Cardinal(ACol));
end;

function TSourceTokens.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TSourceTokens.GetItem(AIndex: Integer): TFormatterToken;
begin
  Result := FItems[AIndex];
end;

function TSourceTokens.KindAt(AIndex: Integer): TptTokenKind;
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then
    Result := ptNull
  else
    Result := FItems[AIndex].Kind;
end;

function TSourceTokens.GenKindAt(AIndex: Integer): TptTokenKind;
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then
    Result := ptNull
  else
    Result := FItems[AIndex].GenKind;
end;

function TSourceTokens.IndexOfPosition(ALine, ACol: Integer): Integer;
begin
  if not FPositionIndex.TryGetValue(PositionKey(ALine, ACol), Result) then
    Result := -1;
end;

class function TSourceTokens.IsComment(AKind: TptTokenKind): Boolean;
begin
  Result := AKind in CommentTokens;
end;

class function TSourceTokens.IsDirective(AKind: TptTokenKind): Boolean;
begin
  Result := AKind in DirectiveTokens;
end;

class function TSourceTokens.IsWhitespace(AKind: TptTokenKind): Boolean;
begin
  Result := AKind in WhitespaceTokens;
end;

function TSourceTokens.IsSignificant(AIndex: Integer): Boolean;
var
  Kind: TptTokenKind;
begin
  Kind := KindAt(AIndex);
  Result := (Kind <> ptNull) and not IsWhitespace(Kind) and not IsComment(Kind)
    and not IsDirective(Kind);
end;

function TSourceTokens.PrevSignificant(AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and not IsSignificant(Result) do
    Dec(Result);
end;

function TSourceTokens.NextSignificant(AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  while (Result < Count) and not IsSignificant(Result) do
    Inc(Result);
  if Result >= Count then
    Result := -1;
end;

{ TLayoutPlanner - walks the AST and marks tokens. }

type
  TLayoutPlanner = class
  private
    FTokens: TSourceTokens;
    FMarks: TArray<TLayoutMark>;
    FCoverage: TFormatterCoverage;
    procedure Handled(ANode: TSyntaxNode);
    procedure Unhandled(ANode: TSyntaxNode);
    function HasPosition(ANode: TSyntaxNode): Boolean;
    function StartIndex(ANode: TSyntaxNode): Integer;
    function EndIndex(ANode: TSyntaxNode): Integer;
    function ClosingTokenIndex(ANode: TSyntaxNode): Integer;
    function LastSignificantBefore(AIndex: Integer; ASkipSemicolon: Boolean): Integer;
    function IsBeginBlock(ANode: TSyntaxNode): Boolean;
    function IsGroupedWithPrevious(ANode, APrevious: TSyntaxNode): Boolean;
    function AdoptPrefixKeywords(AIndex: Integer): Integer;
    function LastChild(ANode: TSyntaxNode): TSyntaxNode;
    procedure MarkBreak(AIndex, AIndent: Integer; ABlankBefore: Boolean = False);
    procedure MarkBreakIfKind(AIndex, AIndent: Integer; AKind: TptTokenKind);
    procedure MarkJoin(AIndex: Integer);
    procedure MarkGenericBrackets(ANode: TSyntaxNode);
    procedure MarkGenericBracketsByTokens;
    procedure MarkFinalEnd;
    procedure VisitRoot(ARoot: TSyntaxNode);
    procedure VisitSection(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitDeclaration(ANode: TSyntaxNode; AIndent: Integer; ABlank: Boolean);
    procedure VisitDeclarationList(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitTypeDecl(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitTypeBody(ATypeNode, ADeclNode: TSyntaxNode; AIndent: Integer);
    procedure VisitMember(ANode, APrevious: TSyntaxNode; AIndent: Integer);
    procedure VisitMethod(ANode: TSyntaxNode; AIndent: Integer; ABlank: Boolean);
    procedure VisitBlock(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitStatementsAt(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitBody(ANode: TSyntaxNode; AOwnerIndent: Integer);
    procedure VisitStatement(ANode: TSyntaxNode; AIndent: Integer; ABreak: Boolean = True);
    procedure VisitIf(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitLoop(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitRepeat(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitCase(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitTry(ANode: TSyntaxNode; AIndent: Integer);
    procedure VisitExpressionTree(ANode: TSyntaxNode; AIndent: Integer);
  public
    constructor Create(ATokens: TSourceTokens);
    function Plan(ARoot: TSyntaxNode): TArray<TLayoutMark>;
    property Coverage: TFormatterCoverage read FCoverage;
  end;

constructor TLayoutPlanner.Create(ATokens: TSourceTokens);
begin
  inherited Create;
  FTokens := ATokens;
  SetLength(FMarks, ATokens.Count);
end;

function TLayoutPlanner.Plan(ARoot: TSyntaxNode): TArray<TLayoutMark>;
begin
  FCoverage.Handled := [];
  FCoverage.Unhandled := [];
  MarkGenericBrackets(ARoot);
  MarkGenericBracketsByTokens;
  VisitRoot(ARoot);
  MarkFinalEnd;
  FCoverage.Unhandled := FCoverage.Unhandled - FCoverage.Handled;
  Result := FMarks;
end;

procedure TLayoutPlanner.Handled(ANode: TSyntaxNode);
begin
  Include(FCoverage.Handled, ANode.Typ);
end;

procedure TLayoutPlanner.Unhandled(ANode: TSyntaxNode);
begin
  Include(FCoverage.Unhandled, ANode.Typ);
end;

function TLayoutPlanner.HasPosition(ANode: TSyntaxNode): Boolean;
begin
  // Line 0 marks synthetic nodes; a non-empty FileName marks include files.
  Result := Assigned(ANode) and (ANode.Line > 0) and (ANode.FileName = '');
end;

function TLayoutPlanner.StartIndex(ANode: TSyntaxNode): Integer;
begin
  if HasPosition(ANode) then
    Result := FTokens.IndexOfPosition(ANode.Line, ANode.Col)
  else
    Result := -1;
end;

{ Exclusive end of a node's token range. Compound nodes carry the position of
  the token that follows them; other nodes end where the next sibling starts,
  or at the closing token of the enclosing construct. }
function TLayoutPlanner.EndIndex(ANode: TSyntaxNode): Integer;
var
  Parent, Sibling: TSyntaxNode;
  I, Idx: Integer;
  Found: Boolean;
begin
  if (ANode is TCompoundSyntaxNode) and (TCompoundSyntaxNode(ANode).EndLine > 0) then
  begin
    Idx := FTokens.IndexOfPosition(TCompoundSyntaxNode(ANode).EndLine,
      TCompoundSyntaxNode(ANode).EndCol);
    if Idx >= 0 then
      Exit(Idx);
  end;

  Parent := ANode.ParentNode;
  if Parent = nil then
    Exit(FTokens.Count);

  Found := False;
  for I := 0 to High(Parent.ChildNodes) do
  begin
    Sibling := Parent.ChildNodes[I];
    if Found then
    begin
      Idx := StartIndex(Sibling);
      if Idx >= 0 then
        Exit(Idx);
    end
    else
      Found := Sibling = ANode;
  end;

  Result := ClosingTokenIndex(Parent);
end;

{ Index of the token that terminates the body of ANode ("end", "until", ...),
  or the node's own end when it has no closing keyword of its own. }
function TLayoutPlanner.ClosingTokenIndex(ANode: TSyntaxNode): Integer;
var
  Idx: Integer;
begin
  case ANode.Typ of
    ntStatements:
      if IsBeginBlock(ANode) then
      begin
        Idx := LastSignificantBefore(EndIndex(ANode), False);
        if FTokens.KindAt(Idx) = ptEnd then
          Exit(Idx);
      end;
    ntRepeat:
      begin
        Idx := EndIndex(ANode.FindNode(ntStatements));
        if FTokens.KindAt(Idx) = ptUntil then
          Exit(Idx);
      end;
    ntCase, ntTry:
      begin
        Idx := LastSignificantBefore(EndIndex(ANode), True);
        if FTokens.KindAt(Idx) = ptEnd then
          Exit(Idx);
      end;
  end;
  Result := EndIndex(ANode);
end;

function TLayoutPlanner.LastSignificantBefore(AIndex: Integer;
  ASkipSemicolon: Boolean): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and (not FTokens.IsSignificant(Result)
    or (ASkipSemicolon and (FTokens.KindAt(Result) = ptSemiColon))) do
    Dec(Result);
end;

function TLayoutPlanner.IsBeginBlock(ANode: TSyntaxNode): Boolean;
begin
  Result := Assigned(ANode) and (ANode.Typ = ntStatements)
    and (FTokens.KindAt(StartIndex(ANode)) in [ptBegin, ptAsm]);
end;

{ "A, B: Integer" yields one node per name, each with a cloned type node at
  the same source position - that shared position identifies the group. }
function TLayoutPlanner.IsGroupedWithPrevious(ANode, APrevious: TSyntaxNode): Boolean;
var
  TypeA, TypeB: TSyntaxNode;
begin
  Result := False;
  if (APrevious = nil) or (APrevious.Typ <> ANode.Typ) then
    Exit;
  if not (ANode.Typ in [ntVariable, ntField, ntParameter]) then
    Exit;
  TypeA := ANode.FindNode(ntType);
  TypeB := APrevious.FindNode(ntType);
  Result := Assigned(TypeA) and Assigned(TypeB) and (TypeA.Line > 0)
    and (TypeA.Line = TypeB.Line) and (TypeA.Col = TypeB.Col);
end;

{ Class members such as "class var X" or "strict private" are positioned by
  DelphiAST on the name, not on the leading keyword; move the break back. }
function TLayoutPlanner.AdoptPrefixKeywords(AIndex: Integer): Integer;
var
  Prev: Integer;
begin
  Result := AIndex;
  Prev := FTokens.PrevSignificant(Result);
  while (Prev >= 0) and (FTokens.GenKindAt(Prev) in MemberPrefixTokens) do
  begin
    // "TFoo = class" followed by a visibility keyword: that "class" opens the
    // type, it is not a "class var" prefix
    if (FTokens.KindAt(Prev) = ptClass)
      and (FTokens.KindAt(FTokens.PrevSignificant(Prev)) in [ptEqual, ptPacked]) then
      Break;
    Result := Prev;
    Prev := FTokens.PrevSignificant(Result);
  end;
end;

function TLayoutPlanner.LastChild(ANode: TSyntaxNode): TSyntaxNode;
begin
  if ANode.HasChildren then
    Result := ANode.ChildNodes[High(ANode.ChildNodes)]
  else
    Result := nil;
end;

procedure TLayoutPlanner.MarkBreak(AIndex, AIndent: Integer; ABlankBefore: Boolean);
begin
  if (AIndex < 0) or (AIndex >= Length(FMarks)) then
    Exit;
  FMarks[AIndex].BreakBefore := True;
  FMarks[AIndex].JoinPrevious := False;
  FMarks[AIndex].BlankBefore := FMarks[AIndex].BlankBefore or ABlankBefore;
  FMarks[AIndex].Indent := AIndent;
end;

procedure TLayoutPlanner.MarkBreakIfKind(AIndex, AIndent: Integer; AKind: TptTokenKind);
begin
  if FTokens.KindAt(AIndex) = AKind then
    MarkBreak(AIndex, AIndent);
end;

procedure TLayoutPlanner.MarkJoin(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex >= Length(FMarks)) then
    Exit;
  FMarks[AIndex].BreakBefore := False;
  FMarks[AIndex].JoinPrevious := True;
end;

{ "<" and ">" of generics must not be spaced like comparison operators. The
  token before a ntTypeArgs node is "<"; ntTypeParams starts on "<". }
procedure TLayoutPlanner.MarkGenericBrackets(ANode: TSyntaxNode);
var
  Child: TSyntaxNode;
  Open, Idx, Depth: Integer;
begin
  if ANode.Typ in [ntTypeArgs, ntTypeParams] then
  begin
    Open := StartIndex(ANode);
    if (Open >= 0) and (FTokens.KindAt(Open) <> ptLower) then
      Open := FTokens.PrevSignificant(Open);
    if FTokens.KindAt(Open) = ptLower then
    begin
      FMarks[Open].GenericBracket := True;
      Depth := 0;
      Idx := Open;
      while Idx < FTokens.Count do
      begin
        case FTokens.KindAt(Idx) of
          ptLower: Inc(Depth);
          ptGreater:
            begin
              Dec(Depth);
              if Depth = 0 then
              begin
                FMarks[Idx].GenericBracket := True;
                Break;
              end;
            end;
          ptSemiColon, ptAssign, ptBegin, ptEnd: Break;
        end;
        Inc(Idx);
      end;
    end;
    Handled(ANode);
  end;
  for Child in ANode.ChildNodes do
    MarkGenericBrackets(Child);
end;

{ Method headers such as "function TFoo<T>.Make<U>(...)" have no ntTypeArgs
  node. A "<" right after an identifier whose matching ">" is followed by a
  token that cannot follow a comparison is a generic bracket. }
procedure TLayoutPlanner.MarkGenericBracketsByTokens;
const
  InsideGeneric: TPtTokenKindSet =
    [ptIdentifier, ptComma, ptPoint, ptColon, ptLower, ptGreater, ptClass, ptRecord,
     ptConstructor, ptString, ptInteger, ptBoolean, ptByte, ptWord, ptCardinal,
     ptInt64, ptDouble, ptSingle, ptChar, ptPChar, ptVariant, ptExtended, ptArray,
     ptOf, ptConst];
  AfterGeneric: TPtTokenKindSet =
    [ptRoundOpen, ptPoint, ptSemiColon, ptRoundClose, ptComma, ptEqual, ptGreater,
     ptColon, ptSquareClose, ptOf, ptAssign, ptEnd, ptDo, ptThen, ptElse, ptTo];
var
  Open, Idx, Depth, Prev, Next: Integer;
begin
  for Open := 1 to FTokens.Count - 1 do
  begin
    if (FTokens.KindAt(Open) <> ptLower) or FMarks[Open].GenericBracket then
      Continue;
    Prev := FTokens.PrevSignificant(Open);
    if FTokens.KindAt(Prev) <> ptIdentifier then
      Continue;
    Depth := 0;
    Idx := Open;
    while (Idx < FTokens.Count) and (FTokens.IsSignificant(Idx)
      or TSourceTokens.IsWhitespace(FTokens.KindAt(Idx))) do
    begin
      if FTokens.IsSignificant(Idx) then
      begin
        if not (FTokens.KindAt(Idx) in InsideGeneric) then
          Break;
        if FTokens.KindAt(Idx) = ptLower then
          Inc(Depth)
        else if FTokens.KindAt(Idx) = ptGreater then
        begin
          Dec(Depth);
          if Depth = 0 then
          begin
            Next := FTokens.NextSignificant(Idx);
            if (Next < 0) or (FTokens.KindAt(Next) in AfterGeneric) then
            begin
              FMarks[Open].GenericBracket := True;
              FMarks[Idx].GenericBracket := True;
            end;
            Break;
          end;
        end;
      end;
      Inc(Idx);
    end;
  end;
end;

procedure TLayoutPlanner.MarkFinalEnd;
var
  Dot, EndTok: Integer;
begin
  Dot := LastSignificantBefore(FTokens.Count, False);
  if FTokens.KindAt(Dot) <> ptPoint then
    Exit;
  EndTok := FTokens.PrevSignificant(Dot);
  if FTokens.KindAt(EndTok) = ptEnd then
    MarkBreak(EndTok, 0, True);
end;

procedure TLayoutPlanner.VisitRoot(ARoot: TSyntaxNode);
var
  Child: TSyntaxNode;
begin
  Handled(ARoot);
  for Child in ARoot.ChildNodes do
    if Child.Typ in SectionNodeTypes then
    begin
      Handled(Child);
      MarkBreak(StartIndex(Child), 0, True);
      VisitSection(Child, 0);
    end
    else if Child.Typ = ntStatements then
      // main block of a program / library
      VisitBlock(Child, 0)
    else
      VisitDeclaration(Child, 0, Child.Typ in [ntMethod, ntUses]);
end;

procedure TLayoutPlanner.VisitSection(ANode: TSyntaxNode; AIndent: Integer);
var
  Child: TSyntaxNode;
  First: Boolean;
begin
  First := True;
  for Child in ANode.ChildNodes do
  begin
    if Child.Typ = ntStatements then
      // initialization / finalization bodies have no begin keyword
      VisitStatementsAt(Child, AIndent + 1)
    else
      VisitDeclaration(Child, AIndent, First or (Child.Typ in DeclarationSectionTypes)
        or ((Child.Typ = ntMethod) and (ANode.Typ = ntImplementation)));
    First := False;
  end;
end;

procedure TLayoutPlanner.VisitDeclaration(ANode: TSyntaxNode; AIndent: Integer;
  ABlank: Boolean);
var
  Start: Integer;
begin
  Start := StartIndex(ANode);
  case ANode.Typ of
    ntMethod:
      VisitMethod(ANode, AIndent, ABlank);
    ntUses, ntTypeSection, ntConstants, ntVariables, ntExports:
      begin
        Handled(ANode);
        MarkBreak(Start, AIndent, ABlank);
        VisitDeclarationList(ANode, AIndent + 1);
      end;
    ntLabel:
      begin
        Handled(ANode);
        // The "label" keyword is not part of the node; break on it too.
        if FTokens.KindAt(FTokens.PrevSignificant(Start)) = ptLabel then
        begin
          MarkBreak(FTokens.PrevSignificant(Start), AIndent);
          MarkBreak(Start, AIndent + 1);
        end;
      end;
    ntAttributes:
      begin
        Handled(ANode);
        MarkBreak(Start, AIndent, ABlank);
      end;
  else
    Unhandled(ANode);
    MarkBreak(Start, AIndent, ABlank);
  end;
end;

procedure TLayoutPlanner.VisitDeclarationList(ANode: TSyntaxNode; AIndent: Integer);
var
  Child, Previous: TSyntaxNode;
begin
  Previous := nil;
  for Child in ANode.ChildNodes do
  begin
    case Child.Typ of
      ntTypeDecl:
        VisitTypeDecl(Child, AIndent);
      ntUnit, ntConstant, ntResourceString, ntElement, ntAttributes:
        begin
          Handled(Child);
          MarkBreak(StartIndex(Child), AIndent);
        end;
      ntVariable:
        begin
          Handled(Child);
          if not IsGroupedWithPrevious(Child, Previous) then
            MarkBreak(StartIndex(Child), AIndent);
        end;
    else
      Unhandled(Child);
      MarkBreak(StartIndex(Child), AIndent);
    end;
    VisitExpressionTree(Child, AIndent);
    Previous := Child;
  end;
end;

procedure TLayoutPlanner.VisitTypeDecl(ANode: TSyntaxNode; AIndent: Integer);
var
  TypeNode: TSyntaxNode;
  Kind: string;
begin
  Handled(ANode);
  MarkBreak(StartIndex(ANode), AIndent);
  TypeNode := ANode.FindNode(ntType);
  if TypeNode = nil then
    Exit;
  Kind := TypeNode.GetAttribute(anType);
  if TypeNode.HasAttribute(anForwarded) then
    Exit;
  if (Kind = 'class') or (Kind = 'record') or (Kind = 'interface')
    or (Kind = 'dispinterface') or (Kind = 'object') then
    VisitTypeBody(TypeNode, ANode, AIndent)
  else
    Unhandled(TypeNode);
end;

procedure TLayoutPlanner.VisitTypeBody(ATypeNode, ADeclNode: TSyntaxNode; AIndent: Integer);
var
  Child, Previous, Member, PreviousMember: TSyntaxNode;
  EndTok, VisibilityTok: Integer;
begin
  Handled(ATypeNode);
  // The declaration ends after "end;" - the "end" is the last keyword before it.
  EndTok := LastSignificantBefore(EndIndex(ADeclNode), True);
  if FTokens.KindAt(EndTok) <> ptEnd then
    // "TFoo = class(TBar);" and similar bodies without an end keyword
    Exit;
  MarkBreak(EndTok, AIndent);

  Previous := nil;
  for Child in ATypeNode.ChildNodes do
  begin
    if Child.Typ in VisibilityNodeTypes then
    begin
      Handled(Child);
      VisibilityTok := AdoptPrefixKeywords(StartIndex(Child));
      MarkBreak(VisibilityTok, AIndent);
      PreviousMember := nil;
      for Member in Child.ChildNodes do
      begin
        VisitMember(Member, PreviousMember, AIndent + 1);
        PreviousMember := Member;
      end;
    end
    else if Child.Typ in [ntField, ntMethod, ntProperty, ntConstant, ntTypeSection,
      ntVariables, ntConstants, ntAttributes, ntGuid] then
      VisitMember(Child, Previous, AIndent + 1)
    else
      // ancestor list, guid-less markers, helper target: flow inline
      VisitExpressionTree(Child, AIndent);
    Previous := Child;
  end;
end;

procedure TLayoutPlanner.VisitMember(ANode, APrevious: TSyntaxNode; AIndent: Integer);
var
  Start: Integer;
begin
  Start := StartIndex(ANode);
  case ANode.Typ of
    ntField, ntConstant:
      begin
        Handled(ANode);
        if not IsGroupedWithPrevious(ANode, APrevious) then
          MarkBreak(AdoptPrefixKeywords(Start), AIndent);
      end;
    ntMethod, ntProperty, ntAttributes, ntGuid:
      begin
        Handled(ANode);
        MarkBreak(AdoptPrefixKeywords(Start), AIndent);
      end;
    ntTypeSection, ntConstants, ntVariables:
      VisitDeclaration(ANode, AIndent, False);
  else
    Unhandled(ANode);
    MarkBreak(Start, AIndent);
  end;
  VisitExpressionTree(ANode, AIndent);
end;

procedure TLayoutPlanner.VisitMethod(ANode: TSyntaxNode; AIndent: Integer; ABlank: Boolean);
var
  Child: TSyntaxNode;
begin
  Handled(ANode);
  MarkBreak(StartIndex(ANode), AIndent, ABlank);
  for Child in ANode.ChildNodes do
    case Child.Typ of
      ntStatements:
        VisitBlock(Child, AIndent);
      ntMethod:
        VisitMethod(Child, AIndent + 1, False);
      ntVariables, ntConstants, ntTypeSection, ntLabel:
        VisitDeclaration(Child, AIndent, False);
      ntParameters, ntReturnType, ntAttributes, ntTypeParams, ntExternal, ntMessage:
        VisitExpressionTree(Child, AIndent);
    else
      Unhandled(Child);
      VisitExpressionTree(Child, AIndent);
    end;
end;

{ begin/asm ... end block: keywords at AIndent, statements one level deeper. }
procedure TLayoutPlanner.VisitBlock(ANode: TSyntaxNode; AIndent: Integer);
var
  Start, EndTok: Integer;
  Child: TSyntaxNode;
begin
  Handled(ANode);
  Start := StartIndex(ANode);
  if not IsBeginBlock(ANode) then
  begin
    VisitStatementsAt(ANode, AIndent + 1);
    Exit;
  end;
  MarkBreak(Start, AIndent);
  EndTok := LastSignificantBefore(EndIndex(ANode), False);
  MarkBreakIfKind(EndTok, AIndent, ptEnd);
  for Child in ANode.ChildNodes do
    VisitStatement(Child, AIndent + 1);
end;

{ A statement list without its own begin/end (repeat body, try body, case
  else branch, ...): statements directly at AIndent. }
procedure TLayoutPlanner.VisitStatementsAt(ANode: TSyntaxNode; AIndent: Integer);
var
  Child: TSyntaxNode;
begin
  if ANode = nil then
    Exit;
  if ANode.Typ <> ntStatements then
  begin
    VisitStatement(ANode, AIndent);
    Exit;
  end;
  Handled(ANode);
  if IsBeginBlock(ANode) then
    VisitBlock(ANode, AIndent)
  else
    for Child in ANode.ChildNodes do
      VisitStatement(Child, AIndent);
end;

{ Body of then/else/do/on: a begin block sits at the owner's indent, a single
  statement goes one level deeper. }
procedure TLayoutPlanner.VisitBody(ANode: TSyntaxNode; AOwnerIndent: Integer);
begin
  if ANode = nil then
    Exit;
  if IsBeginBlock(ANode) then
    VisitBlock(ANode, AOwnerIndent)
  else
    VisitStatementsAt(ANode, AOwnerIndent + 1);
end;

procedure TLayoutPlanner.VisitStatement(ANode: TSyntaxNode; AIndent: Integer; ABreak: Boolean);
var
  Start: Integer;
begin
  if not HasPosition(ANode) then
    Exit;
  Start := StartIndex(ANode);
  if ANode.Typ = ntStatements then
  begin
    VisitStatementsAt(ANode, AIndent);
    Exit;
  end;
  if ABreak then
    MarkBreak(Start, AIndent);
  case ANode.Typ of
    ntIf: VisitIf(ANode, AIndent);
    ntFor, ntWhile, ntWith: VisitLoop(ANode, AIndent);
    ntRepeat: VisitRepeat(ANode, AIndent);
    ntCase: VisitCase(ANode, AIndent);
    ntTry: VisitTry(ANode, AIndent);
    ntEmptyStatement:
      begin
        Handled(ANode);
        MarkJoin(Start);
      end;
    ntAssign, ntCall, ntInherited, ntRaise, ntGoto, ntVariables:
      begin
        Handled(ANode);
        VisitExpressionTree(ANode, AIndent);
      end;
  else
    Unhandled(ANode);
    VisitExpressionTree(ANode, AIndent);
  end;
end;

procedure TLayoutPlanner.VisitIf(ANode: TSyntaxNode; AIndent: Integer);
var
  ThenNode, ElseNode, Body: TSyntaxNode;
begin
  Handled(ANode);
  VisitExpressionTree(ANode.FindNode(ntExpression), AIndent);
  ThenNode := ANode.FindNode(ntThen);
  if Assigned(ThenNode) then
  begin
    Handled(ThenNode);
    VisitBody(LastChild(ThenNode), AIndent);
  end;
  ElseNode := ANode.FindNode(ntElse);
  if Assigned(ElseNode) then
  begin
    Handled(ElseNode);
    MarkBreak(StartIndex(ElseNode), AIndent);
    Body := LastChild(ElseNode);
    if Assigned(Body) and (Body.Typ = ntIf) then
    begin
      // keep "else if" on one line
      MarkJoin(StartIndex(Body));
      VisitStatement(Body, AIndent, False);
    end
    else
      VisitBody(Body, AIndent);
  end;
end;

procedure TLayoutPlanner.VisitLoop(ANode: TSyntaxNode; AIndent: Integer);
var
  I: Integer;
begin
  Handled(ANode);
  // header children (control variable, bounds, expressions) flow inline;
  // the last child is the loop body
  for I := 0 to High(ANode.ChildNodes) - 1 do
    VisitExpressionTree(ANode.ChildNodes[I], AIndent);
  if Length(ANode.ChildNodes) >= 2 then
    VisitBody(LastChild(ANode), AIndent);
end;

procedure TLayoutPlanner.VisitRepeat(ANode: TSyntaxNode; AIndent: Integer);
var
  Body: TSyntaxNode;
  UntilTok: Integer;
begin
  Handled(ANode);
  Body := ANode.FindNode(ntStatements);
  if Body = nil then
    Exit;
  VisitStatementsAt(Body, AIndent + 1);
  UntilTok := EndIndex(Body);
  MarkBreakIfKind(UntilTok, AIndent, ptUntil);
  VisitExpressionTree(ANode.FindNode(ntExpression), AIndent);
end;

procedure TLayoutPlanner.VisitCase(ANode: TSyntaxNode; AIndent: Integer);
var
  Child, Body: TSyntaxNode;
  EndTok: Integer;
begin
  Handled(ANode);
  for Child in ANode.ChildNodes do
    case Child.Typ of
      ntCaseSelector:
        begin
          Handled(Child);
          MarkBreak(StartIndex(Child), AIndent + 1);
          Body := LastChild(Child);
          if Assigned(Body) and (Body.Typ <> ntCaseLabels) then
          begin
            if IsBeginBlock(Body) then
              VisitBlock(Body, AIndent + 2)
            else
            begin
              // "1: DoSomething;" stays on the label's line
              MarkJoin(StartIndex(Body));
              VisitStatement(Body, AIndent + 2, False);
            end;
          end;
        end;
      ntCaseElse:
        begin
          Handled(Child);
          MarkBreak(StartIndex(Child), AIndent);
          Body := LastChild(Child);
          if Assigned(Body) then
            VisitBody(Body, AIndent);
        end;
    else
      VisitExpressionTree(Child, AIndent);
    end;
  EndTok := ClosingTokenIndex(ANode);
  MarkBreakIfKind(EndTok, AIndent, ptEnd);
end;

procedure TLayoutPlanner.VisitTry(ANode: TSyntaxNode; AIndent: Integer);
var
  Child, Handler, Guarded: TSyntaxNode;
  KeywordTok, EndTok: Integer;
begin
  Handled(ANode);
  Guarded := ANode.FindNode(ntStatements);
  if Assigned(Guarded) then
  begin
    VisitStatementsAt(Guarded, AIndent + 1);
    KeywordTok := EndIndex(Guarded);
    if FTokens.KindAt(KeywordTok) in [ptFinally, ptExcept] then
      MarkBreak(KeywordTok, AIndent);
  end;
  for Child in ANode.ChildNodes do
    case Child.Typ of
      ntFinally:
        begin
          Handled(Child);
          VisitStatementsAt(LastChild(Child), AIndent + 1);
        end;
      ntExcept:
        begin
          Handled(Child);
          for Handler in Child.ChildNodes do
            case Handler.Typ of
              ntExceptionHandler:
                begin
                  Handled(Handler);
                  MarkBreak(StartIndex(Handler), AIndent + 1);
                  VisitBody(LastChild(Handler), AIndent + 1);
                end;
              ntElse:
                begin
                  Handled(Handler);
                  MarkBreak(StartIndex(Handler), AIndent);
                  VisitStatementsAt(LastChild(Handler), AIndent + 1);
                end;
            else
              VisitStatementsAt(Handler, AIndent + 1);
            end;
        end;
    end;
  EndTok := ClosingTokenIndex(ANode);
  MarkBreakIfKind(EndTok, AIndent, ptEnd);
end;

{ Expression-level nodes flow as tokens. Only anonymous method bodies inside
  them need block layout. }
procedure TLayoutPlanner.VisitExpressionTree(ANode: TSyntaxNode; AIndent: Integer);
var
  Child: TSyntaxNode;
begin
  if ANode = nil then
    Exit;
  for Child in ANode.ChildNodes do
    if Child.Typ = ntAnonymousMethod then
    begin
      Handled(Child);
      VisitMethod(Child, AIndent + 1, False);
    end
    else
      VisitExpressionTree(Child, AIndent);
end;

{ TTokenEmitter - turns tokens + marks into text. }

type
  TTokenEmitter = class
  private
    FTokens: TSourceTokens;
    FMarks: TArray<TLayoutMark>;
    FOutput: TStringBuilder;
    FBaseIndent: Integer;          // indent of the last planned line break
    FLineHasContent: Boolean;
    FStarted: Boolean;
    FPendingLineBreaks: Integer;   // source line breaks seen since last token
    FPrevKind: TptTokenKind;       // last emitted code token
    FPrevGenKind: TptTokenKind;
    FPrevGeneric: Boolean;         // last token was a generic "<"
    FPrevGenericClose: Boolean;    // last token was a generic ">"
    FPrevUnarySign: Boolean;
    FPrevPrefixCaret: Boolean;
    FAfterOwnLineComment: Boolean;
    FAfterOwnLineDirective: Boolean;
    FAfterSlashComment: Boolean;   // "//" comment: a line break is mandatory
    procedure NewLine(AIndent: Integer; ABlank: Boolean);
    function NeedSpaceBefore(AIndex: Integer): Boolean;
    function UpcomingIndent(AIndex: Integer): Integer;
    function NextPlannedBreak(AIndex: Integer): Integer;
    function IsUnarySignAt(AIndex: Integer): Boolean;
    function BlankAllowedHere(AKind: TptTokenKind): Boolean;
    procedure EmitSignificant(AIndex: Integer);
    procedure EmitCommentOrDirective(AIndex: Integer);
    procedure RememberToken(AIndex: Integer);
  public
    constructor Create(ATokens: TSourceTokens; const AMarks: TArray<TLayoutMark>);
    destructor Destroy; override;
    function Emit: string;
  end;

constructor TTokenEmitter.Create(ATokens: TSourceTokens; const AMarks: TArray<TLayoutMark>);
begin
  inherited Create;
  FTokens := ATokens;
  FMarks := AMarks;
  FOutput := TStringBuilder.Create;
  FPrevKind := ptNull;
  FPrevGenKind := ptNull;
end;

destructor TTokenEmitter.Destroy;
begin
  FOutput.Free;
  inherited;
end;

function TTokenEmitter.Emit: string;
var
  I: Integer;
  Kind: TptTokenKind;
begin
  for I := 0 to FTokens.Count - 1 do
  begin
    Kind := FTokens.KindAt(I);
    if Kind = ptSpace then
      Continue;
    if Kind in [ptCRLF, ptCRLFCo] then
    begin
      Inc(FPendingLineBreaks);
      Continue;
    end;
    if TSourceTokens.IsComment(Kind) or TSourceTokens.IsDirective(Kind) then
      EmitCommentOrDirective(I)
    else
      EmitSignificant(I);
  end;
  Result := FOutput.ToString;
  if Result <> '' then
    Result := Result + LineBreak;
end;

procedure TTokenEmitter.NewLine(AIndent: Integer; ABlank: Boolean);
begin
  if FStarted then
  begin
    FOutput.Append(LineBreak);
    if ABlank then
      FOutput.Append(LineBreak);
  end;
  FLineHasContent := False;
  FOutput.Append(StringOfChar(' ', AIndent * IndentWidth));
end;

{ Index of the next code token that starts a planned line, or -1. }
function TTokenEmitter.NextPlannedBreak(AIndex: Integer): Integer;
begin
  Result := FTokens.NextSignificant(AIndex);
  while (Result >= 0) and not FMarks[Result].BreakBefore do
    Result := FTokens.NextSignificant(Result);
end;

{ Indent for an own-line comment or directive: align with the next planned
  code line; a comment right before a closing keyword belongs to the block. }
function TTokenEmitter.UpcomingIndent(AIndex: Integer): Integer;
var
  Next: Integer;
begin
  Next := NextPlannedBreak(AIndex);
  if Next >= 0 then
  begin
    Result := FMarks[Next].Indent;
    if FTokens.KindAt(Next) in CloserTokens then
      Inc(Result);
  end
  else if FStarted then
    Result := FBaseIndent
  else
    Result := 0;
end;

function TTokenEmitter.IsUnarySignAt(AIndex: Integer): Boolean;
begin
  Result := (FTokens.KindAt(AIndex) in [ptMinus, ptPlus])
    and ((not FLineHasContent) or (FPrevKind in SignPrefixTokens));
end;

{ A blank line carries no information right after an opener or before a
  closer, and the beginning of the output never starts with one. }
function TTokenEmitter.BlankAllowedHere(AKind: TptTokenKind): Boolean;
begin
  Result := FStarted and not (FPrevGenKind in OpenerTokens) and not (AKind in CloserTokens);
end;

function TTokenEmitter.NeedSpaceBefore(AIndex: Integer): Boolean;
var
  Kind: TptTokenKind;
begin
  Kind := FTokens.KindAt(AIndex);
  if not FLineHasContent then
    Exit(False);
  if FAfterOwnLineComment or FAfterOwnLineDirective then
    // never happens on the same line, kept for safety
    Exit(True);
  if FPrevKind in [ptRoundOpen, ptSquareOpen, ptPoint, ptDotDot, ptAddressOp,
    ptDoubleAddressOp] then
    Exit(False);
  if FPrevUnarySign or FPrevPrefixCaret then
    Exit(False);
  if Kind = ptSemiColon then
    // empty statement: "do ;", "else ;", "1: ;"
    Exit(FPrevKind in [ptDo, ptThen, ptElse, ptColon]);
  if Kind in [ptRoundClose, ptSquareClose, ptComma, ptPoint, ptDotDot, ptColon] then
    Exit(False);
  if Kind in [ptRoundOpen, ptSquareOpen] then
    Exit(not ((FPrevKind in CallableTokens) or FPrevGenericClose) or FPrevGeneric);
  if Kind = ptPointerSymbol then
    // postfix dereference "P^" vs. prefix pointer type "^Integer"
    Exit(not (FPrevKind in [ptIdentifier, ptRoundClose, ptSquareClose, ptPointerSymbol]));
  if FMarks[AIndex].GenericBracket or FPrevGeneric then
    Exit(False);
  if (FPrevKind in LiteralTokens) and (Kind in LiteralTokens) then
    Exit(False);
  Result := True;
end;

procedure TTokenEmitter.RememberToken(AIndex: Integer);
var
  Kind: TptTokenKind;
begin
  Kind := FTokens.KindAt(AIndex);
  FPrevUnarySign := IsUnarySignAt(AIndex);
  FPrevPrefixCaret := (Kind = ptPointerSymbol)
    and not (FPrevKind in [ptIdentifier, ptRoundClose, ptSquareClose, ptPointerSymbol]);
  FPrevGeneric := FMarks[AIndex].GenericBracket and (Kind = ptLower);
  FPrevGenericClose := FMarks[AIndex].GenericBracket and (Kind = ptGreater);
  FPrevKind := Kind;
  FPrevGenKind := FTokens.GenKindAt(AIndex);
  FLineHasContent := True;
  FStarted := True;
  FPendingLineBreaks := 0;
  FAfterOwnLineComment := False;
  FAfterOwnLineDirective := False;
  FAfterSlashComment := False;
end;

procedure TTokenEmitter.EmitSignificant(AIndex: Integer);
var
  Mark: TLayoutMark;
  Blank: Boolean;
  Kind: TptTokenKind;
begin
  Mark := FMarks[AIndex];
  Kind := FTokens.KindAt(AIndex);
  if Mark.BreakBefore then
  begin
    // A required blank line was already written before the comment block
    // that documents this declaration; an author's blank line is kept once.
    Blank := (Mark.BlankBefore and not FAfterOwnLineComment and not FAfterOwnLineDirective)
      or ((FPendingLineBreaks >= 2) and BlankAllowedHere(Kind));
    NewLine(Mark.Indent, Blank);
    FBaseIndent := Mark.Indent;
  end
  else if Mark.JoinPrevious and not FAfterSlashComment then
    // stay on the current line even if the source broke here
  else if (FPendingLineBreaks > 0) or FAfterSlashComment then
  begin
    if FAfterOwnLineDirective then
      // code inside an inactive {$IFDEF} branch has no AST: keep it flat,
      // aligned with the directive that guards it
      NewLine(FBaseIndent, False)
    else if FLineHasContent or FAfterOwnLineComment then
      // author's line break inside a statement: continuation line
      NewLine(FBaseIndent + 1, False);
  end;

  if NeedSpaceBefore(AIndex) then
    FOutput.Append(' ');
  FOutput.Append(FTokens[AIndex].Text);
  RememberToken(AIndex);
end;

procedure TTokenEmitter.EmitCommentOrDirective(AIndex: Integer);
var
  OwnLine, Blank, IsDirective: Boolean;
  Next: Integer;
begin
  IsDirective := TSourceTokens.IsDirective(FTokens.KindAt(AIndex));
  OwnLine := (FPendingLineBreaks > 0) or not FStarted;
  if OwnLine then
  begin
    Blank := (FPendingLineBreaks >= 2) and BlankAllowedHere(ptUnknown);
    if not IsDirective and not FAfterOwnLineComment then
    begin
      // a comment glued to a declaration that requires a blank line above
      // it: put the blank above the comment instead
      Next := NextPlannedBreak(AIndex);
      if (Next >= 0) and FMarks[Next].BlankBefore and (FTokens.NextSignificant(AIndex) = Next) then
        Blank := BlankAllowedHere(ptUnknown);
    end;
    NewLine(UpcomingIndent(AIndex), Blank);
    FBaseIndent := UpcomingIndent(AIndex);
  end
  else if FLineHasContent then
    FOutput.Append(' ');
  FOutput.Append(FTokens[AIndex].Text);
  // Comments never influence the spacing rules between code tokens
  // (FPrevKind is left untouched), but they do occupy the current line.
  FStarted := True;
  FLineHasContent := True;
  FPendingLineBreaks := 0;
  FAfterOwnLineComment := OwnLine and not IsDirective;
  FAfterOwnLineDirective := OwnLine and IsDirective;
  FAfterSlashComment := FTokens.KindAt(AIndex) = ptSlashesComment;
end;

{ TDelphiCodeFormatter }

function TDelphiCodeFormatter.ParseSource(const ASourceCode: string): TSyntaxNode;
var
  Builder: TPasSyntaxTreeBuilder;
  Stream: TStringStream;
begin
  Stream := TStringStream.Create(ASourceCode);
  try
    Builder := TPasSyntaxTreeBuilder.Create;
    try
      Builder.InitDefinesDefinedByCompiler;
      try
        Result := Builder.Run(Stream);
      except
        on E: ESyntaxTreeException do
          // E owns and frees the partial tree; only the message is kept
          raise EDelphiFormatterException.CreateFmt('Parse error at %d:%d: %s',
            [E.Line, E.Col, E.Message]);
      end;
    finally
      Builder.Free;
    end;
  finally
    Stream.Free;
  end;
end;

function TDelphiCodeFormatter.FormatSource(const ASourceCode: string): string;
var
  Root: TSyntaxNode;
  Tokens: TSourceTokens;
  Planner: TLayoutPlanner;
  Emitter: TTokenEmitter;
  Marks: TArray<TLayoutMark>;
begin
  if Trim(ASourceCode) = '' then
    Exit('');
  Root := ParseSource(ASourceCode);
  try
    Tokens := TSourceTokens.Create(ASourceCode);
    try
      Planner := TLayoutPlanner.Create(Tokens);
      try
        Marks := Planner.Plan(Root);
        FCoverage := Planner.Coverage;
      finally
        Planner.Free;
      end;
      Emitter := TTokenEmitter.Create(Tokens, Marks);
      try
        Result := Emitter.Emit;
      finally
        Emitter.Free;
      end;
    finally
      Tokens.Free;
    end;
  finally
    Root.Free;
  end;
end;

class function TDelphiCodeFormatter.TokenFingerprint(const ASourceCode: string): string;
var
  Tokens: TSourceTokens;
  Builder: TStringBuilder;
  I: Integer;
begin
  Tokens := TSourceTokens.Create(ASourceCode);
  try
    Builder := TStringBuilder.Create;
    try
      for I := 0 to Tokens.Count - 1 do
        if not TSourceTokens.IsWhitespace(Tokens.KindAt(I)) then
          Builder.Append(Tokens[I].Text).Append(#1);
      Result := Builder.ToString;
    finally
      Builder.Free;
    end;
  finally
    Tokens.Free;
  end;
end;

end.
