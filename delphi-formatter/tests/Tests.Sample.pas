unit Tests.Sample;

interface

uses
  System.Classes,
  System.IOUtils,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  DUnitX.TestFramework;

type
  [TestFixture]
  TSampleTests = class
  private
  public
    [Setup]
    procedure Setup;

    [Test]
    procedure SampleTest01;
  end;

implementation

{ TSampleTests }

procedure TSampleTests.SampleTest01;
begin
  Assert.AreEqual(2, 2);
end;

procedure TSampleTests.Setup;
begin

end;

initialization
  TDUnitX.RegisterTestFixture(TSampleTests);

end.
