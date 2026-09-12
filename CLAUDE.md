## Projects

- Delphi Applications: 
    - `delphi-formatter/src/dfmt.dpr` - CLI Delphi code Formatter.
    - `delphi-formatter/tests/dfmt_dunitx.dpr` - DUnitX test suite for Delphi Formatter.
    - `ast-viewer/AstViewer.dpr` - VCL Demo App - AST Viewer

## AST Viewer

- VCL App - Load PAS file and build AST using DephiAST. Display nodes in TTreeView control.
- Idea: TMemo after paste or edit TreeView is rebuilt.
- Use TPasSyntaxTreeBuilder.

Compile it from the repo root folder with:

```bat
del .\bin\AstViewer.exe; dcc32 -NSSystem -E".\bin" -NU".\bin" -U".\delphi-ast" -Q .\ast-viewer\AstViewer.dpr
```

Run the demo app the: 
```
cd bin; ./AstViewer.exe; cd ..
```

## Delphi Code Formatter - dfmt

Run it from the repo root folder

```bat
del .\bin\dfmt.exe; dcc32 -NSSystem  -E".\bin" -NU".\bin\units" -U".\delphi-ast" -Q .\delphi-formatter\src\dfmt.dpr
```

Run:

```bat
.\bin\dfmt.exe
```

## Delphi Code Formatter Unit Tests - dfmt_dunitx

Run it from the repo root folder

```bat
del .\bin\dfmt_dunitx.exe; dcc32 -E".\bin" -NU".\bin" -NS"System;Data;Winapi;System.Win;Data.Win" -U".\delphi-formatter\src;.\delphi-ast" -Q .\delphi-formatter\tests\dfmt_dunitx.dpr
```

Run the unit tests with:

```bat
.\bin\dfmt_dunitx.exe
```

To validate tests analyze dfmt_dunitx.exe stdout output.

Golden test cases live in `delphi-formatter/tests/golden/<case>.in.pas` / `<case>.out.pas`
(loaded at runtime relative to the executable, searching upwards for the folder).

## Golden runner without DUnitX - dfmt_golden

Runs the same golden cases from a plain console program (Delphi or Free Pascal):

```bat
dcc32 -NSSystem -E".\bin" -NU".\bin" -U".\delphi-formatter\src;.\delphi-formatter\tests;.\delphi-ast" -Q .\delphi-formatter\tests\dfmt_golden.dpr
.\bin\dfmt_golden.exe --coverage
```

## Formatter documentation

- `delphi-formatter/docs/01-analiza-delphiast.md` - real DelphiAST API/AST structure analysis.
- `delphi-formatter/docs/02-architektura-formattera.md` - formatter architecture, limitations.
- `delphi-formatter/tools/astdump/` - AST dump tool with sample inputs and their dumps.
