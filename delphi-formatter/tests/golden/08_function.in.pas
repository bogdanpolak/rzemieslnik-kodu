unit Test;
interface
implementation
function Add(A, B: Integer): Integer;
begin
  Result:=A+B;
end;
function Neg(A: Integer): Integer; inline;
begin
  Result := -A * (A - -1);
end;
end.
