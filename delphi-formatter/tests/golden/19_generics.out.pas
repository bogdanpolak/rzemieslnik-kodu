unit Test;

interface

uses
  System.Generics.Collections;

type
  TFoo<T: class> = class(TObject)
  strict private
    FList: TList<T>;
    FMap: TDictionary<string, TList<T>>;
  public
    function Make<U>(const A: T; B: U): TFoo<T>;
    property List: TList<T> read FList;
  end;

implementation

function TFoo<T>.Make<U>(const A: T; B: U): TFoo<T>;
var
  X: TPair<string, Integer>;
begin
  FList := TList<T>.Create;
  Result := TFoo<T>.Create;
  if A < B then
    Exit;
end;

end.
