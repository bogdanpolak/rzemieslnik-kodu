unit Test;

interface

implementation

procedure Test;
begin
  case I of
    1: Exit;
    2, 3:
      begin
        Break;
      end;
    4..9: Continue;
  else
    Writeln('other');
  end;
  case S of
    'a': ;
  end;
end;

end.
