unit Test;
interface
implementation
procedure Test;
begin
  if A > 10 then
  begin
    DoSomething;

    if B then DoOtherThing;
  end
  else
    DoFallback;
  if X then Y else if Z then W else begin V; end;
end;
end.
