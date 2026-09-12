unit Test; // unit comment

interface

{ block comment
  spanning lines }
uses
  System.SysUtils; (* ansi comment *)

implementation

// standalone before method
procedure Test; // trailing on header
var
  A: Integer; // trailing on var
begin
  // inside body
  A := 1; { after statement }
  A := { inline } 2;

  // before end
end;

end.
