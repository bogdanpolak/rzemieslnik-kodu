unit TestUnit;
interface
implementation
procedure Test;
begin
  if A > 10 then
  begin
    DoSomething;

    if B then
      DoOtherThing;
  end
  else
    DoFallback;
end;
end.
