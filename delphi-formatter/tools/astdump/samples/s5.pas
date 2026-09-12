unit TestUnit;
interface
type
  TPerson = class
  private
    FName: string;
  public
    constructor Create(const AName: string);
    procedure SayHello;
  end;
implementation
end.
