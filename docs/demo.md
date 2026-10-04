# Demo 1

```
.\bin\dfmt.exe .\docs\demo1_minimal.pas
```

# Demo 2

```
.\bin\dfmt.exe .\docs\demo2_compiler_dir.pas
```

# Demo 3

```
dcc32 -NSSystem -E".\bin" -NU".\bin\units" -U".\delphi-formatter\src;.\delphi-ast" -Q .\docs\demo3_idempotent.dpr
```
```
.\bin\demo3_idempotent.exe
```
