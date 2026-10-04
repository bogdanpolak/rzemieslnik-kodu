program demo3_idempotent;

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  DelphiAST.Formatter.Engine;

type 
  TResult = record
    Passed: Boolean;
    Report: string;
    Actual: string;
    Again: string;
  end;

function NormalizeLineEndings(const AText: string): string;
begin
  Result := StringReplace(AText, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

function FirstDifference(const A, B: string): string;
var
  I, Line, Col: Integer;
begin
  Line := 1;
  Col := 1;
  I := 1;
  while (I <= Length(A)) and (I <= Length(B)) and (A[I] = B[I]) do
  begin
    if A[I] = #10 then
    begin
      Inc(Line);
      Col := 1;
    end
    else
      Inc(Col);
    Inc(I);
  end;
  Result := Format('pierwsza roznica w linii %d, kolumnie %d', [Line, Col]);
end;

function LoadTextFile(const AFileName: string): string;
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create('', TEncoding.UTF8);
  try
    Stream.LoadFromFile(AFileName);
    Result := Stream.DataString;
  finally
    Stream.Free;
  end;
end;

function Test_Idempotent(AInput: string): TResult;
var
  Formatter: TDelphiCodeFormatter;
begin
  Result.Passed := False;
  Result.Report := '';
  Result.Actual := '';
  Result.Again := '';

  Formatter := TDelphiCodeFormatter.Create;
  try
    Result.Actual := NormalizeLineEndings(Formatter.FormatSource(AInput));
    Result.Again := NormalizeLineEndings(Formatter.FormatSource(Result.Actual));

    if Result.Again <> Result.Actual then
    begin
      Result.Passed := False;
      Result.Report := 'Formatowanie NIE JEST idempotentne! (' +
        FirstDifference(Result.Again, Result.Actual) + ')';
    end 
    else
    begin
      Result.Passed := True;
      Result.Report := 'Formatowanie JEST idempotentne: Format(Format(S)) = Format(S)';
    end;
  finally
    Formatter.Free;
  end;
end;

const
  DefaultSampleCode =
    'unit demo1_minimal;' + sLineBreak +
    'interface procedure Test;' + sLineBreak +
    'implementation' + sLineBreak +
    'procedure Test; begin var A:=1; writeln(A); end;' + sLineBreak +
    'end.' + sLineBreak;

var
  SourceCode: string;
  SourceDesc: string;
  LResult: TResult;
  ShouldPause: Boolean;
  I: Integer;
begin
  ShouldPause := False;
  for I := 1 to ParamCount do
  begin
    if (ParamStr(I) = '--pause') or (ParamStr(I) = '-p') then
      ShouldPause := True;
  end;

  try
    Writeln('==============================================');
    Writeln('   Demo 3: Test Idempotentnosci Formattera    ');
    Writeln('==============================================');
    Writeln;

    if (ParamCount >= 1) and (Copy(ParamStr(1), 1, 1) <> '-') and FileExists(ParamStr(1)) then
    begin
      SourceDesc := 'Plik: ' + ParamStr(1);
      SourceCode := LoadTextFile(ParamStr(1));
    end
    else if FileExists('demo1_minimal.pas') then
    begin
      SourceDesc := 'Plik: demo1_minimal.pas';
      SourceCode := LoadTextFile('demo1_minimal.pas');
    end
    else if FileExists('docs' + PathDelim + 'demo1_minimal.pas') then
    begin
      SourceDesc := 'Plik: docs' + PathDelim + 'demo1_minimal.pas';
      SourceCode := LoadTextFile('docs' + PathDelim + 'demo1_minimal.pas');
    end
    else
    begin
      SourceDesc := 'Wbudowany przyklad (demo1_minimal)';
      SourceCode := DefaultSampleCode;
    end;

    Writeln('Kod wejsciowy [', SourceDesc, ']:');
    Writeln('----------------------------------------------');
    Writeln(TrimRight(SourceCode));
    Writeln('----------------------------------------------');
    Writeln;

    Writeln('Uruchamianie testu idempotentnosci...');
    LResult := Test_Idempotent(SourceCode);
    Writeln;

    Writeln('Wynik formatowania (1. przebieg):');
    Writeln('----------------------------------------------');
    Writeln(TrimRight(LResult.Actual));
    Writeln('----------------------------------------------');
    Writeln;

    if LResult.Passed then
    begin
      Writeln('[PASS] ', LResult.Report);
      ExitCode := 0;
    end
    else
    begin
      Writeln('[FAIL] ', LResult.Report);
      Writeln;
      Writeln('Wynik ponownego formatowania (2. przebieg):');
      Writeln('----------------------------------------------');
      Writeln(TrimRight(LResult.Again));
      Writeln('----------------------------------------------');
      ExitCode := 1;
    end;
  except
    on E: Exception do
    begin
      Writeln;
      Writeln('[ERROR] Blad wykonania: ', E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;

  if ShouldPause then
  begin
    Writeln;
    Write('Nacisnij Enter, aby zakonczyc...');
    Readln;
  end;
end.