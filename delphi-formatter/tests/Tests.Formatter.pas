unit Tests.Formatter;

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DelphiAST.Consts,
  DelphiAST.Formatter.Engine,
  Tests.Formatter.Golden;

type
  { Golden tests: tests/golden/<case>.in.pas -> <case>.out.pas.
    Every case also verifies the token invariant and idempotency. }
  [TestFixture]
  TFormatterGoldenTests = class
  private
    procedure CheckGolden(const ACaseName: string);
  public
    [Test] procedure Test01_Empty;
    [Test] procedure Test02_MinimalUnit;
    [Test] procedure Test03_UnitUses;
    [Test] procedure Test04_InterfaceType;
    [Test] procedure Test05_Class;
    [Test] procedure Test06_Record;
    [Test] procedure Test07_Procedure;
    [Test] procedure Test08_Function;
    [Test] procedure Test09_Parameters;
    [Test] procedure Test10_LocalVariables;
    [Test] procedure Test11_NestedBeginEnd;
    [Test] procedure Test12_IfElse;
    [Test] procedure Test13_TryExcept;
    [Test] procedure Test14_TryFinally;
    [Test] procedure Test15_For;
    [Test] procedure Test16_Case;
    [Test] procedure Test17_Comments;
    [Test] procedure Test18_CompilerDirectives;
    [Test] procedure Test19_Generics;
    [Test] procedure Test20_Idempotency;
    [Test] procedure AllGoldenCasesHaveATest;
  end;

  [TestFixture]
  TFormatterBehaviourTests = class
  private
    FFormatter: TDelphiCodeFormatter;
  public
    [Setup] procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure EmptySourceGivesEmptyResult;
    [Test] procedure WhitespaceOnlySourceGivesEmptyResult;
    [Test] procedure InvalidSourceRaisesFormatterException;
    [Test] procedure FragmentWithoutUnitHeaderIsFormatted;
    [Test] procedure StringLiteralsAreKeptVerbatim;
    [Test] procedure InactiveDirectiveBranchIsPreserved;
    [Test] procedure CoverageReportsHandledNodeTypes;
  end;

implementation

{ TFormatterGoldenTests }

procedure TFormatterGoldenTests.CheckGolden(const ACaseName: string);
var
  GoldenResult: TGoldenResult;
begin
  GoldenResult := RunGoldenCase(ACaseName);
  Assert.IsTrue(GoldenResult.Passed, ACaseName + sLineBreak + GoldenResult.Report);
end;

procedure TFormatterGoldenTests.Test01_Empty;
begin
  CheckGolden('01_empty');
end;

procedure TFormatterGoldenTests.Test02_MinimalUnit;
begin
  CheckGolden('02_minimal_unit');
end;

procedure TFormatterGoldenTests.Test03_UnitUses;
begin
  CheckGolden('03_unit_uses');
end;

procedure TFormatterGoldenTests.Test04_InterfaceType;
begin
  CheckGolden('04_interface_type');
end;

procedure TFormatterGoldenTests.Test05_Class;
begin
  CheckGolden('05_class');
end;

procedure TFormatterGoldenTests.Test06_Record;
begin
  CheckGolden('06_record');
end;

procedure TFormatterGoldenTests.Test07_Procedure;
begin
  CheckGolden('07_procedure');
end;

procedure TFormatterGoldenTests.Test08_Function;
begin
  CheckGolden('08_function');
end;

procedure TFormatterGoldenTests.Test09_Parameters;
begin
  CheckGolden('09_parameters');
end;

procedure TFormatterGoldenTests.Test10_LocalVariables;
begin
  CheckGolden('10_local_variables');
end;

procedure TFormatterGoldenTests.Test11_NestedBeginEnd;
begin
  CheckGolden('11_nested_begin_end');
end;

procedure TFormatterGoldenTests.Test12_IfElse;
begin
  CheckGolden('12_if_else');
end;

procedure TFormatterGoldenTests.Test13_TryExcept;
begin
  CheckGolden('13_try_except');
end;

procedure TFormatterGoldenTests.Test14_TryFinally;
begin
  CheckGolden('14_try_finally');
end;

procedure TFormatterGoldenTests.Test15_For;
begin
  CheckGolden('15_for');
end;

procedure TFormatterGoldenTests.Test16_Case;
begin
  CheckGolden('16_case');
end;

procedure TFormatterGoldenTests.Test17_Comments;
begin
  CheckGolden('17_comments');
end;

procedure TFormatterGoldenTests.Test18_CompilerDirectives;
begin
  CheckGolden('18_compiler_directives');
end;

procedure TFormatterGoldenTests.Test19_Generics;
begin
  CheckGolden('19_generics');
end;

procedure TFormatterGoldenTests.Test20_Idempotency;
begin
  CheckGolden('20_idempotency');
end;

{ Guards against adding a golden pair without wiring a test method for it. }
procedure TFormatterGoldenTests.AllGoldenCasesHaveATest;
begin
  Assert.AreEqual(20, Length(ListGoldenCases), 'number of golden cases');
end;

{ TFormatterBehaviourTests }

procedure TFormatterBehaviourTests.Setup;
begin
  FFormatter := TDelphiCodeFormatter.Create;
end;

procedure TFormatterBehaviourTests.TearDown;
begin
  FFormatter.Free;
end;

procedure TFormatterBehaviourTests.EmptySourceGivesEmptyResult;
begin
  Assert.AreEqual('', FFormatter.FormatSource(''));
end;

procedure TFormatterBehaviourTests.WhitespaceOnlySourceGivesEmptyResult;
begin
  Assert.AreEqual('', FFormatter.FormatSource('  ' + sLineBreak + sLineBreak));
end;

procedure TFormatterBehaviourTests.InvalidSourceRaisesFormatterException;
begin
  Assert.WillRaise(
    procedure
    begin
      // note: the parser is lenient about "if then"; an empty right-hand
      // side is reported as "Illegal expression"
      FFormatter.FormatSource('procedure Broken; begin A := ; end;');
    end,
    EDelphiFormatterException);
end;

procedure TFormatterBehaviourTests.FragmentWithoutUnitHeaderIsFormatted;
begin
  Assert.AreEqual(
    'procedure Test;' + sLineBreak +
    'begin' + sLineBreak +
    '  A := 1;' + sLineBreak +
    'end;' + sLineBreak,
    FFormatter.FormatSource('procedure Test; begin A:=1; end;'));
end;

{ DelphiAST dequotes literals ('#13' and #13 become the same node); the
  token-based writer must never touch them. }
procedure TFormatterBehaviourTests.StringLiteralsAreKeptVerbatim;
const
  Source = 'procedure T; begin X := ''#13'' + #13 + ''It''''s'' + ''a''#10''b''; end;';
var
  Formatted: string;
begin
  Formatted := FFormatter.FormatSource(Source);
  Assert.IsTrue(Pos('X := ''#13'' + #13 + ''It''''s'' + ''a''#10''b'';', Formatted) > 0, Formatted);
end;

procedure TFormatterBehaviourTests.InactiveDirectiveBranchIsPreserved;
const
  Source =
    'unit U; interface {$IFDEF NEVER_DEFINED_XYZ}' + sLineBreak +
    'const Hidden = 1;' + sLineBreak +
    '{$ENDIF} implementation end.';
var
  Formatted: string;
begin
  Formatted := FFormatter.FormatSource(Source);
  Assert.IsTrue(Pos('Hidden = 1;', Formatted) > 0, 'inactive branch dropped: ' + Formatted);
  Assert.AreEqual(TDelphiCodeFormatter.TokenFingerprint(Source),
    TDelphiCodeFormatter.TokenFingerprint(Formatted));
end;

procedure TFormatterBehaviourTests.CoverageReportsHandledNodeTypes;
begin
  FFormatter.FormatSource('unit U; interface uses A; implementation end.');
  Assert.IsTrue(ntUses in FFormatter.Coverage.Handled, FFormatter.Coverage.HandledNames);
  Assert.IsTrue(ntInterface in FFormatter.Coverage.Handled);
end;

initialization
  TDUnitX.RegisterTestFixture(TFormatterGoldenTests);
  TDUnitX.RegisterTestFixture(TFormatterBehaviourTests);

end.
