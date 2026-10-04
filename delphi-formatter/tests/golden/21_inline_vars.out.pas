unit Test;

interface

uses
  System.SysUtils;

procedure Run;

implementation

procedure Run;
var
  List: TArray<string>;
begin
  var X: Integer := 10;
  var Y := 20;
  var Z: string := 'hello';
  var A, B: Double;
  A := 1.5;
  B := 2.5;
  for var I := 0 to 9 do
    Writeln(I);
  for var S in List do
    Writeln(S);
end;

end.
