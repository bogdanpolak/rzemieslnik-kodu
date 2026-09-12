unit Test;
interface
implementation
procedure Test;
var
  L: TList<Integer>;
begin
  L := TList<Integer>.Create;
  try
    L.Add(1);
    try
      L.Add(2);
    finally
      L.Clear;
    end;
  finally
    L.Free;
  end;
end;
end.
