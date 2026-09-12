unit TestUnit; // trailing comment

interface

{ block comment }
uses
  System.SysUtils; (* ansi comment *)

{$IFDEF DEBUG}
const
  Mode = 'Debug';
{$ELSE}
const
  Mode = 'Release';
{$ENDIF}

{$DEFINE SOMETHING}
{$R+}

type
  TFoo<T: class> = class(TObject)
  strict private
    FList: TList<T>;
  public
    class function Make(const A: T; var B: Integer; out C: string): TFoo<T>; static; overload; inline;
    procedure Run; virtual; abstract;
    property Count: Integer read GetCount write SetCount default 0;
  end;

implementation

procedure Loop; stdcall;
var
  I: Integer;
  L: TList<Integer>;
begin
  for I := 0 to 10 do
    Writeln(I);
  try
    L := TList<Integer>.Create;
    try
      L.Add(1);
    finally
      L.Free;
    end;
  except
    on E: Exception do
      raise;
  end;
  case I of
    1: Exit;
    2, 3: Break;
  else
    Continue;
  end;
  while I > 0 do
    Dec(I);
  repeat
    Inc(I);
  until I = 5;
end;

end.
