unit demo2_compiler_dir;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}
{$DEFINE SOMETHING}

interface

implementation

procedure Test;
begin
  {$IFDEF SOMETHING}
    Writeln('x1'); Writeln('x2'); 
  {$ELSE}
    Writeln('y1');      Writeln('y2'); 
  {$ENDIF}
end;

end.
