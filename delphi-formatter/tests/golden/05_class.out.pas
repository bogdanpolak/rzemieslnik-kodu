unit Test;

interface

type
  TPerson = class(TObject)
  private
    FName: string;
    FAge: Integer;
  strict private
    FSecret, FOther: Boolean;
  public
    constructor Create(const AName: string);
    destructor Destroy; override;
    procedure SayHello; virtual; abstract;
    class function Make: TPerson; static;
    class var Count: Integer;
    property Name: string read FName write FName;
  end;

implementation

end.
