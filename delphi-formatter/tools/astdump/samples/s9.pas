unit TestUnit;
interface
uses A.B, C;
const
  Pi2 = 3.14 * 2;
  Hex = $FF;
  S = 'It''s' + #13#10;
type
  TProc = reference to procedure(A: Integer);
  TArr = array[0..9] of Integer;
  TDyn = array of string;
  TEnum = (eOne, eTwo = 5);
  TSet = set of TEnum;
  PInt = ^Integer;
  TAlias = type Integer;
  TCls = class of TObject;
  IFoo = interface(IInterface)
    ['{A41FF9F3-3FE0-4B59-BE61-C88B7F2A8466}']
    function Get: Integer;
  end;
  TRec = record
    class operator Add(A, B: TRec): TRec;
  end;
  TStrHelper = record helper for string
    function Len: Integer;
  end;
implementation
function Calc(const X, Y: Integer; Z: Double = 1.5): Double;
var
  R: Integer;
begin
  R := (X + Y) * Z - -X;
  R := X + (Y * Z);
  R := Foo(1, Bar(2, 'a'), [1, 2..3]);
  R := Obj.Items[2].Name;
  R := not (X = Y) and (Y <> Z);
  R := Integer(X) as TObject;
  R := @X;
  R := P^;
  R := TList<Integer>.Create;
  with Obj do Name := 'x';
  inherited Create(nil);
  inherited;
  Result := R;
end;
initialization
  Calc(1, 2);
finalization
end.
