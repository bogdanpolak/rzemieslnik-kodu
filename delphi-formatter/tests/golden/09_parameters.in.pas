unit Test;
interface
implementation
procedure Params(const A: string; var B: Integer; out C: Boolean; D: Double = 1.5; const E: array of Integer);
begin
  B := Length( E );
  C := A<>'' ;
end;
end.
