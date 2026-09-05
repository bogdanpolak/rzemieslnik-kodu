unit SemanticTools.DelphiAstParser;

interface

uses
  System.Classes,
  System.SysUtils,
  System.IOUtils,
  DelphiAST,
  DelphiAST.Classes,
  SimpleParser.Lexer.Types;

type
  IFileRepository = interface
    ['{A41FF9F3-3FE0-4B59-BE61-C88B7F2A8466}']
    function OpenRead(const AFileName: string): TStream;
  end;

  IAstParser = interface
    ['{3E3B1656-C363-4F15-BBCE-07723EAC1E6C}']
    function TryParse(
      const AFileName: string;
      out ASyntaxTree: TSyntaxNode
      ): boolean;
    function GetFailureMessage: string;
  end;

function CreateAstParser(const AFileRepository: IFileRepository = nil): IAstParser;

implementation

{ TFileSourceFileProvider }

type
  TFileRepository = class(TInterfacedObject, IFileRepository)
  public
    function OpenRead(const AFileName: string): TStream;
  end;

function TFileRepository.OpenRead(const AFileName: string): TStream;
begin
  Result := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
end;

{ TDelphiAstIncludeHandler }

type
  TDelphiAstIncludeHandler = class(TInterfacedObject, IIncludeHandler)
  private
    FSourceFileProvider: IFileRepository;
    function LoadContent(const AFileName: string): string;
    function ResolveIncludeFileName(
      const AParentFileName: string;
      const AIncludeName: string
      ): string;
  public
    constructor Create(const AFileRepository: IFileRepository);
    function GetIncludeFileContent(
      const ParentFileName: string;
      const IncludeName: string;
      out Content: string;
      out FileName: string
      ): Boolean;
  end;

constructor TDelphiAstIncludeHandler.Create(
  const AFileRepository: IFileRepository);
begin
  inherited Create;
  FSourceFileProvider := AFileRepository;
end;

function TDelphiAstIncludeHandler.GetIncludeFileContent(
  const ParentFileName: string;
  const IncludeName: string;
  out Content: string;
  out FileName: string
  ): Boolean;
begin
  FileName := ResolveIncludeFileName(ParentFileName, IncludeName);
  Content := LoadContent(FileName);
  Result := True;
end;

function TDelphiAstIncludeHandler.LoadContent(const AFileName: string): string;
var
  Stream: TStream;
  StringStream: TStringStream;
begin
  Stream := FSourceFileProvider.OpenRead(AFileName);
  try
    Stream.Position := 0;
    StringStream := TStringStream.Create;
    try
      StringStream.LoadFromStream(Stream);
      Result := StringStream.DataString;
    finally
      StringStream.Free;
    end;
  finally
    Stream.Free;
  end;
end;

function TDelphiAstIncludeHandler.ResolveIncludeFileName(
  const AParentFileName: string;
  const AIncludeName: string
  ): string;
var
  ParentFolder: string;
begin
  if TPath.IsPathRooted(AIncludeName) then
    Exit(TPath.GetFullPath(AIncludeName));

  ParentFolder := TPath.GetDirectoryName(AParentFileName);
  if ParentFolder = '' then
    Exit(TPath.GetFullPath(AIncludeName));

  Result := TPath.GetFullPath(TPath.Combine(ParentFolder, AIncludeName));
end;

{ TAstParser }

type
  TAstParser = class(TInterfacedObject, IAstParser)
  private
    FFileRepository: IFileRepository;
    FFailureMessage: string;
  public
    constructor Create(const AFileRepository: IFileRepository);
    function TryParse(
      const AFileName: string;
      out ASyntaxTree: TSyntaxNode
      ): boolean;
    function GetFailureMessage: string;
  end;

function CreateAstParser(const AFileRepository: IFileRepository = nil): IAstParser;
begin
  if AFileRepository = nil then
    Exit(TAstParser.Create(TFileRepository.Create()));

  Result := TAstParser.Create(AFileRepository);
end;

constructor TAstParser.Create(const AFileRepository: IFileRepository);
begin
  FFileRepository := AFileRepository;
end;

function TAstParser.GetFailureMessage: string;
begin
  Result := FFailureMessage;
end;

function TAstParser.TryParse(
  const AFileName: string;
  out ASyntaxTree: TSyntaxNode
  ): boolean;
var
  Builder: TPasSyntaxTreeBuilder;
  Stream: TStream;
begin
  FFailureMessage := '';
  try
    Stream := FFileRepository.OpenRead(AFileName);
    try
      Stream.Position := 0;

      Builder := TPasSyntaxTreeBuilder.Create;
      try
        Builder.InitDefinesDefinedByCompiler;
        Builder.IncludeHandler := TDelphiAstIncludeHandler.Create(FFileRepository);
        Builder.Lexer.Lexer.Buffer.FileName := TPath.GetFullPath(AFileName);
        ASyntaxTree := Builder.Run(Stream);
        Result := True;
      finally
        Builder.Free;
      end;
    finally
      Stream.Free;
    end;
  except
    on E: Exception do
    begin
      Result := False;
      FFailureMessage := E.Message;
    end;
  end;
end;


end.