unit MainForm;

interface

uses
  System.SysUtils, System.Classes, System.Variants,
  Winapi.Windows, Winapi.Messages,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.StdCtrls,
  Vcl.ExtCtrls,
  DelphiAST,
  DelphiAST.Classes,
  DelphiAST.Consts,
  SemanticTools.DelphiAstParser;

type
  TForm1 = class(TForm)
    PanelTop: TPanel;
    btnLoadPasFile: TButton;
    TreeView1: TTreeView;
    procedure FormCreate(Sender: TObject);
    procedure btnLoadPasFileClick(Sender: TObject);
  private
    FAstParser: IAstParser;
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

function NodeTypeToStr(ASyntexNode: TSyntaxNode): string;
begin
  case ASyntexNode.Typ of
    ntUnknown: ;
    ntAbsolute: ;
    ntAdd: ;
    ntAddr: ;
    ntAlignmentParam: ;
    ntAnd: ;
    ntAnonymousMethod: ;
    ntArguments: ;
    ntAs: ;
    ntAssign: ;
    ntAt: ;
    ntAttribute: ;
    ntAttributes: ;
    ntBounds: ;
    ntCall: ;
    ntCase: ;
    ntCaseElse: ;
    ntCaseLabel: ;
    ntCaseLabels: ;
    ntCaseSelector: ;
    ntClassConstraint: ;
    ntConstant: ;
    ntConstants: ;
    ntConstraints: ;
    ntConstructorConstraint: ;
    ntContains: ;
    ntDefault: ;
    ntDeref: ;
    ntDimension: ;
    ntDiv: ;
    ntDot: ;
    ntDownTo: ;
    ntElement: ;
    ntElse: ;
    ntEmptyStatement: ;
    ntEnum: ;
    ntEqual: ;
    ntExcept: ;
    ntExceptionHandler: ;
    ntExports: ;
    ntExpression: ;
    ntExpressions: ;
    ntExternal: ;
    ntFDiv: ;
    ntField: ;
    ntFields: ;
    ntFinalization: ;
    ntFinally: ;
    ntFor: ;
    ntFrom: ;
    ntGeneric: ;
    ntGoto: ;
    ntGreater: ;
    ntGreaterEqual: ;
    ntGuid: ;
    ntHelper: ;
    ntIdentifier: ;
    ntIf: ;
    ntImplementation: Exit('Implementation');
    ntImplements: ;
    ntIn: ;
    ntIndex: ;
    ntIndexed: ;
    ntInherited: ;
    ntInitialization: Exit('Initialization');
    ntInterface: Exit('Interface');
    ntIs: ;
    ntIsNot: ;
    ntLabel: ;
    ntLHS: ;
    ntLiteral: ;
    ntLower: ;
    ntLowerEqual: ;
    ntMessage: ;
    ntMethod: ;
    ntMod: ;
    ntMul: ;
    ntName: ;
    ntNamedArgument: ;
    ntNotEqual: ;
    ntNot: ;
    ntNotIn: ;
    ntOr: ;
    ntPackage: ;
    ntParameter: ;
    ntParameters: ;
    ntPath: ;
    ntPositionalArgument: ;
    ntProtected: ;
    ntPrivate: ;
    ntProperty: ;
    ntPublic: ;
    ntPublished: ;
    ntRaise: ;
    ntRead: ;
    ntRecordConstraint: ;
    ntRepeat: ;
    ntRequires: ;
    ntResolutionClause: ;
    ntResourceString: ;
    ntReturnType: ;
    ntRHS: ;
    ntRoundClose: ;
    ntRoundOpen: ;
    ntSet: ;
    ntShl: ;
    ntShr: ;
    ntStatement: ;
    ntStatements: ;
    ntStrictPrivate: ;
    ntStrictProtected: ;
    ntSub: ;
    ntSubrange: ;
    ntTernaryOp: ;
    ntThen: ;
    ntTo: ;
    ntTry: ;
    ntType: ;
    ntTypeArgs: ;
    ntTypeDecl: ;
    ntTypeParam: ;
    ntTypeParams: ;
    ntTypeSection: ;
    ntValue: ;
    ntVariable: ;
    ntVariables: ;
    ntXor: ;
    ntUnaryMinus: ;
    ntUnit: ;
    ntUses: ;
    ntWhile: ;
    ntWith: ;
    ntWrite: ;
    ntAnsiComment: ;
    ntBorComment: ;
    ntSlashesComment: ;
  end;
  Result := '<unknown>';
end;

procedure TForm1.btnLoadPasFileClick(Sender: TObject);
var
  syntaxTree: TSyntaxNode;
  node, childNode: TSyntaxNode;
  compoundNode: TCompoundSyntaxNode;
begin
  var fileName := '../ast-viewer/SemanticTools.DelphiAstParser.pas';
  var ok := FAstParser.TryParse(fileName, syntaxTree);
  if not(ok) then
  begin
    btnLoadPasFile.Caption := 'Load failed';
    exit;
  end;
  node := syntaxTree;
  var rootNode := TreeView1.Items.Add(nil, node.ClassName);
  for childNode in node.ChildNodes do
  begin
    if childNode is TCompoundSyntaxNode then
    begin
      compoundNode := childNode as TCompoundSyntaxNode;
      //  TAttributeName = (
      //    anType,
      //    anClass,
      //    anForwarded,
      //    anKind,
      //    anName,
      //    anVisibility,
      //    anCallingConvention,
      //    anPath,
      //    anMethodBinding,
      //    anReintroduce,
      //    anOverload,
      //    anAbstract,
      //    anInline,
      //    anAlign
      //  );
      var text := '[C] ' + NodeTypeToStr(compoundNode);
      TreeView1.Items.AddChildFirst(rootNode, text);
    end
    else 
      TreeView1.Items.AddChild(rootNode, childNode.ClassName + ' ' + NodeTypeToStr(childNode));
  end;
  TreeView1.FullExpand;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  FAstParser := CreateAstParser();
  TreeView1.Align := alClient;
end;

end.
