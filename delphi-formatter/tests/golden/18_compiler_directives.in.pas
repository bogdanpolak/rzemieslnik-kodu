unit Test;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$DEFINE SOMETHING}

interface

{$IFDEF DEBUG}
const
  Mode = 'Debug';
{$ELSE}
const
  Mode = 'Release';
{$ENDIF}

{$R *.res}
{$I inc.inc}

implementation

procedure Test;
begin
  {$IFDEF SOMETHING}
  Writeln('x');
  {$ELSE}
  Writeln('y');
  {$ENDIF}
  {$REGION 'r'}
  Writeln('z');
  {$ENDREGION}
end;

end.
