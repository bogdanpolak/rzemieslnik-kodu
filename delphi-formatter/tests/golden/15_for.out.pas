unit Test;

interface

implementation

procedure Test;
var
  I: Integer;
  S: string;
begin
  for I := 0 to 10 do
    Writeln(I);
  for I := 10 downto 0 do
  begin
    Writeln(I);
  end;
  for S in List do
    Writeln(S);
  while I > 0 do
    Dec(I);
  repeat
    Inc(I);
  until I = 5;
  with Obj do
    Name := 'x';
end;

end.
