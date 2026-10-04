unit Example.FormatterArchitecture;
interface 

function Run(const ASourceCode: string): string;

implementation

uses
  DelphiAST.Classes,
  DelphiAST.Lexer,
  DelphiAST.Formatter.Engine;

function Run(const ASourceCode: string): string;
var
  Root: TSyntaxNode;
  Tokens: TSourceTokens;
  Planner: TLayoutPlanner;
  Marks: TTokenMarks;
  Emitter: TTokenEmitter;
begin
  Root := ParseSource(ASourceCode);
  try
    Tokens := TSourceTokens.Create(ASourceCode);
    try
      Planner := TLayoutPlanner.Create(Tokens);
      try
        Marks := Planner.Plan(Root);
      finally
        Planner.Free;
      end;
      Emitter := TTokenEmitter.Create(Tokens, Marks);
      try
        Result := Emitter.Emit;
      finally
        Emitter.Free;
      end;
    finally
      Tokens.Free;
    end;
  finally
    Root.Free;
  end;
end;

end.