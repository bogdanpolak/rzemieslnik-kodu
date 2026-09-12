unit Tests.Formatter.Golden;

{
  Framework-independent golden test support shared by the DUnitX suite
  (dfmt_dunitx) and the plain console runner (dfmt_golden), so the same
  checks can be run both from Delphi and from Free Pascal.

  Each case is a pair of files in tests/golden:
    <name>.in.pas   - input
    <name>.out.pas  - expected FormatSource(input)

  For every case three properties are verified:
    1. output equals the expected file (line endings normalised),
    2. token invariant: non-whitespace tokens of input and output are identical,
    3. idempotency: FormatSource(output) = output.
}

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}

interface

uses
  SysUtils,
  Classes;

type
  TGoldenResult = record
    Passed: Boolean;
    Report: string;
  end;

function GoldenDirectory: string;
function ListGoldenCases: TArray<string>;
function RunGoldenCase(const ACaseName: string): TGoldenResult;
function NormalizeLineEndings(const AText: string): string;
function LoadTextFile(const AFileName: string): string;

implementation

uses
  DelphiAST.Formatter.Engine;

const
  GoldenRelativePath = 'delphi-formatter' + PathDelim + 'tests' + PathDelim + 'golden';
  InputSuffix = '.in.pas';
  ExpectedSuffix = '.out.pas';

function LoadTextFile(const AFileName: string): string;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create('');
  try
    Stream.LoadFromFile(AFileName);
    Result := Stream.DataString;
  finally
    Stream.Free;
  end;
end;

function NormalizeLineEndings(const AText: string): string;
begin
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

{ Walk up from the executable until the golden folder is found, so the tests
  work no matter which build folder the binary lands in. }
function GoldenDirectory: string;
var
  Dir, Candidate: string;
  I: Integer;
begin
  Dir := ExtractFilePath(ParamStr(0));
  for I := 1 to 6 do
  begin
    Candidate := IncludeTrailingPathDelimiter(Dir) + GoldenRelativePath;
    if DirectoryExists(Candidate) then
      Exit(IncludeTrailingPathDelimiter(Candidate));
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then
      Break;
  end;
  raise Exception.Create('Golden test folder not found: ' + GoldenRelativePath);
end;

function ListGoldenCases: TArray<string>;
var
  SearchRec: TSearchRec;
  Names: TStringList;
  I: Integer;
begin
  Result := nil;
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    if FindFirst(GoldenDirectory + '*' + InputSuffix, faAnyFile, SearchRec) = 0 then
    try
      repeat
        Names.Add(Copy(SearchRec.Name, 1, Length(SearchRec.Name) - Length(InputSuffix)));
      until FindNext(SearchRec) <> 0;
    finally
      FindClose(SearchRec);
    end;
    SetLength(Result, Names.Count);
    for I := 0 to Names.Count - 1 do
      Result[I] := Names[I];
  finally
    Names.Free;
  end;
end;

function FirstDifference(const A, B: string): string;
var
  I, Line: Integer;
begin
  Line := 1;
  I := 1;
  while (I <= Length(A)) and (I <= Length(B)) and (A[I] = B[I]) do
  begin
    if A[I] = #10 then
      Inc(Line);
    Inc(I);
  end;
  Result := Format('first difference at line %d, char %d', [Line, I]);
end;

function RunGoldenCase(const ACaseName: string): TGoldenResult;
var
  Formatter: TDelphiCodeFormatter;
  Input, Expected, Actual, Again: string;
begin
  Result.Passed := True;
  Result.Report := '';
  Input := LoadTextFile(GoldenDirectory + ACaseName + InputSuffix);
  Expected := NormalizeLineEndings(LoadTextFile(GoldenDirectory + ACaseName + ExpectedSuffix));
  Formatter := TDelphiCodeFormatter.Create;
  try
    Actual := NormalizeLineEndings(Formatter.FormatSource(Input));
    if Actual <> Expected then
    begin
      Result.Passed := False;
      Result.Report := Result.Report + 'output differs from expected (' +
        FirstDifference(Actual, Expected) + ')' + sLineBreak +
        '--- actual ---' + sLineBreak + Actual + '--- end ---' + sLineBreak;
    end;
    if TDelphiCodeFormatter.TokenFingerprint(Input) <>
      TDelphiCodeFormatter.TokenFingerprint(Actual) then
    begin
      Result.Passed := False;
      Result.Report := Result.Report + 'token invariant violated: formatter changed, ' +
        'dropped or added a token' + sLineBreak;
    end;
    Again := NormalizeLineEndings(Formatter.FormatSource(Actual));
    if Again <> Actual then
    begin
      Result.Passed := False;
      Result.Report := Result.Report + 'not idempotent (' + FirstDifference(Again, Actual) +
        ')' + sLineBreak + '--- second pass ---' + sLineBreak + Again + '--- end ---' + sLineBreak;
    end;
  finally
    Formatter.Free;
  end;
end;

end.
