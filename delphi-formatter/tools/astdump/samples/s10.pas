unit U10;
interface
type
  [Weak]
  TNotify = procedure(Sender: TObject) of object;
  TFn = function(X: Integer): Boolean;
  TRef = reference to function: Integer;
  TSealed = class sealed(TObject)
  end;
  TAbs = class abstract
  end;
  TPacked = packed record
    A: Byte;
    case Kind: Integer of
      0: (I: Integer);
      1: (S: Single);
  end;
  TCV = class
  public
    class var Count: Integer;
    const Max = 10;
    class procedure Init; static;
    procedure Old; deprecated 'use New';
    property Items[Index: Integer]: string read GetItem write SetItem; default;
    property Name: string index 1 read GetName stored False;
  end;
resourcestring
  SMsg = 'Hello';
implementation
procedure Outer;
label
  Done;
  procedure Inner;
  begin
  end;
var
  X: string;
begin
  {$IFDEF DEBUG}
  Writeln('debug');
  {$ENDIF}
  X := '#13';
  X := #13;
  X := 'a'#13'b';
  X := '';
  {$REGION 'Loop'}
  var Y := 5;
  var Z: Integer;
  {$ENDREGION}
  if Y = 5 then goto Done;
  Done:
  Exit(X);
end;
exports
  Outer name 'Outer2';
end.
