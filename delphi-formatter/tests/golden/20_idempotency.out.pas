unit Test;

interface

uses
  System.SysUtils;

type
  TWorker = class
  private
    FName: string;
  public
    procedure Run(const AArgs: array of string);
  end;

implementation

procedure TWorker.Run(const AArgs: array of string);
var
  I: Integer;
begin
  for I := Low(AArgs) to High(AArgs) do
  begin
    if AArgs[I] = '' then
      Continue
    else
      Writeln(AArgs[I]);
  end;
end;

end.
