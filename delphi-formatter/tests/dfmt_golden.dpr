program dfmt_golden;

{
  Console golden-test runner without DUnitX. Runs every case from
  tests/golden and exits with code 1 on failure. Compiles with Delphi and
  Free Pascal (-Mdelphi), which is what makes the suite runnable in
  environments without a Delphi compiler.
}

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  DelphiAST.Formatter.Engine,
  Tests.Formatter.Golden;

var
  CaseName: string;
  CaseResult: TGoldenResult;
  Failed, Total: Integer;
  Formatter: TDelphiCodeFormatter;
  Coverage: TFormatterCoverage;
begin
  Failed := 0;
  Total := 0;
  try
    for CaseName in ListGoldenCases do
    begin
      Inc(Total);
      CaseResult := RunGoldenCase(CaseName);
      if CaseResult.Passed then
        Writeln('PASS  ', CaseName)
      else
      begin
        Inc(Failed);
        Writeln('FAIL  ', CaseName);
        Writeln(CaseResult.Report);
      end;
    end;
    Writeln(Format('%d cases, %d failed', [Total, Failed]));

    if (ParamCount > 0) and (ParamStr(1) = '--coverage') then
    begin
      // AST coverage over all inputs: which node types got a layout rule
      Coverage.Handled := [];
      Coverage.Unhandled := [];
      Formatter := TDelphiCodeFormatter.Create;
      try
        for CaseName in ListGoldenCases do
        begin
          Formatter.FormatSource(LoadTextFile(GoldenDirectory + CaseName + '.in.pas'));
          Coverage.Handled := Coverage.Handled + Formatter.Coverage.Handled;
          Coverage.Unhandled := Coverage.Unhandled + Formatter.Coverage.Unhandled;
        end;
        Coverage.Unhandled := Coverage.Unhandled - Coverage.Handled;
        Writeln('Handled:   ', Coverage.HandledNames);
        Writeln('Unhandled: ', Coverage.UnhandledNames);
      finally
        Formatter.Free;
      end;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      Failed := 1;
    end;
  end;
  if Failed > 0 then
    ExitCode := 1;
end.
