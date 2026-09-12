unit Test;
interface
type
  TPoint = record
  X: Integer;
  Y: Integer;
  end;
  TPacked = packed record
    A, B: Byte;
    function Sum: Integer;
  end;
implementation
function TPacked.Sum: Integer;
begin
  Result := A + B;
end;
end.
