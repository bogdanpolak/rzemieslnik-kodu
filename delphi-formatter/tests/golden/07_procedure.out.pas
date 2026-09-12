unit Test;

interface

procedure Foo;

implementation

procedure Foo;
begin
  Writeln('foo');
end;

procedure Bar; stdcall;
begin
end;

end.
