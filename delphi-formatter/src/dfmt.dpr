program dfmt;

{
  dfmt - Delphi code formatter CLI.

  Usage:
    dfmt <input.pas>                 formatted source to stdout
    dfmt <input.pas> <output.pas>    formatted source to file
    dfmt -w <input.pas> [...]        rewrite files in place
    dfmt --coverage <input.pas>      print handled / unhandled AST node types
}

{$IFDEF FPC}{$MODE DELPHI}{$H+}{$ENDIF}
{$APPTYPE CONSOLE}

uses
  SysUtils,
  Classes,
  DelphiAST.Formatter.Engine;

function ReadFile(const AFileName: string): string;
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

procedure WriteFile(const AFileName, AContent: string);
var
  Stream: TStringStream;
begin
  Stream := TStringStream.Create(AContent);
  try
    Stream.SaveToFile(AFileName);
  finally
    Stream.Free;
  end;
end;

procedure PrintUsage;
begin
  Writeln('dfmt - Delphi code formatter');
  Writeln('  dfmt <input.pas>               format to stdout');
  Writeln('  dfmt <input.pas> <output.pas>  format to file');
  Writeln('  dfmt -w <file.pas> [...]       rewrite files in place');
  Writeln('  dfmt --coverage <input.pas>    report AST node coverage');
end;

var
  Formatter: TDelphiCodeFormatter;
  I: Integer;
  Formatted: string;
begin
  if ParamCount = 0 then
  begin
    PrintUsage;
    ExitCode := 2;
    Exit;
  end;
  Formatter := TDelphiCodeFormatter.Create;
  try
    try
      if ParamStr(1) = '-w' then
      begin
        for I := 2 to ParamCount do
          WriteFile(ParamStr(I), Formatter.FormatSource(ReadFile(ParamStr(I))));
      end
      else if ParamStr(1) = '--coverage' then
      begin
        Formatter.FormatSource(ReadFile(ParamStr(2)));
        Writeln('Handled:   ', Formatter.Coverage.HandledNames);
        Writeln('Unhandled: ', Formatter.Coverage.UnhandledNames);
      end
      else
      begin
        Formatted := Formatter.FormatSource(ReadFile(ParamStr(1)));
        if ParamCount >= 2 then
          WriteFile(ParamStr(2), Formatted)
        else
          Write(Formatted);
      end;
    except
      on E: Exception do
      begin
        Writeln(ErrOutput, E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    Formatter.Free;
  end;
end.
