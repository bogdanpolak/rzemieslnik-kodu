# AstDump – narzędzie inspekcji AST (faza 3)

Konsolowy program wypisujący pełne drzewo DelphiAST dla pliku źródłowego:
typ węzła, pozycję `Line:Col` (dla compound nodes także `EndLine:EndCol`), `Value`,
atrybuty oraz listę komentarzy zebranych przez `TPasSyntaxTreeBuilder.Comments`.

Kompilacja z katalogu głównego repo (Delphi):

```bat
dcc32 -NSSystem -E".\bin" -NU".\bin\units" -U".\delphi-ast" -Q .\delphi-formatter\tools\astdump\AstDump.dpr
.\bin\AstDump.exe .\delphi-formatter\tools\astdump\samples\s8.pas
```

Free Pascal 3.2.2 (`fpc -Mdelphi -Sh -Fu<delphi-ast> -Fi<delphi-ast> AstDump.dpr`) również działa,
ale wymaga poprawki w kopii `SimpleParser.pas` (gałąź `{$IFDEF FPC}` helpera `GetDataString`
rekurencyjnie wywołuje sama siebie); poprawka nie została wprowadzona do `delphi-ast/`.

`samples/*.pas` to wejścia użyte w analizie, `samples/*.ast.txt` to odpowiadające im zrzuty.
Omówienie wyników: `delphi-formatter/docs/01-analiza-delphiast.md`.
