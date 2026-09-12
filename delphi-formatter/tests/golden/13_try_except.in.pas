unit Test;
interface
implementation
procedure Test;
begin
  try
    Risky;
  except
    on E: EAbort do ;
    on E: Exception do
    begin
      Log(E.Message);
      raise;
    end;
  else
    HandleUnknown;
  end;
  try Foo; except end;
end;
end.
