# Zintegrowany Plan Ulepszeń Projektu „Rzemieślnik Kodu” (plan_ulepszen_gemini)

Data utworzenia: 2026-10-04  
Status: Gotowy do wdrożenia  
Wersja: 1.1  

---

## 1. Wprowadzenie i architektura projektu

Projekt **Rzemieślnik Kodu** („Rzemieślnik kodu DelphiAST”) to zbiór profesjonalnych narzędzi inżynierii kodu dla języka Object Pascal / Delphi, oparty na parserze [DelphiAST](file:///c:/Sources/github/rzemieslnik-kodu/delphi-ast/). Projekt składa się z dwóch powiązanych komponentów:

1. **Silnik formatowania i narzędzie CLI (`delphi-formatter`)**:
   - Hybrydowy formater kodu (Wariant C), który rozwiązuje problem stratności drzewa semantycznego DelphiAST (brak komentarzy, dyrektyw preprocesora, utrata modyfikatorów `packed`, dequotowanie literałów).
   - Architektura opiera się na separacji ról: [TPasSyntaxTreeBuilder](file:///c:/Sources/github/rzemieslnik-kodu/delphi-ast/DelphiAST.pas) buduje strukturę semantyczną AST, [TSourceTokens](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L53) pobiera kompletny strumień leksykalny [TmwPasLex](file:///c:/Sources/github/rzemieslnik-kodu/delphi-ast/SimpleParser.Lexer.pas) (`UseDefines = False`), [TLayoutPlanner](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L328) oznacza tokeny znacznikami układu, a [TTokenEmitter](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L1138) generuje kod wynikowy.
   - Niezmienniki: *Token Fingerprint Preservation* (zero utraty tokenów) oraz *Idempotentność* (`Format(Format(S)) = Format(S)`).
2. **Wizualizator drzewa AST (`ast-viewer`)**:
   - Aplikacja okienkowa VCL ([AstViewer.dpr](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/AstViewer.dpr)), integrująca edytor `TMemo` z widokiem hierarchii `TTreeView` oraz obsługą dyrektyw `{$I}` przez [TDelphiAstIncludeHandler](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/SemanticTools.DelphiAstParser.pas#L52).
3. **Materiały warsztatowo-prezentacyjne**:
   - Prezentacja [Rzemieślnik kodu DelphiAST.pptx](file:///c:/Sources/github/rzemieslnik-kodu/docs/Rzemieślnik%20kodu%20DelphiAST.pptx) oraz skrypty demonstracyjne na żywo.

---

## 2. Diagnoza zidentyfikowanych problemów

### 2.1. Aplikacja `ast-viewer` (VCL)
1. **Krytyczny wyciek pamięci w edytorze**:
   - W [MainForm.pas:L121](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.pas#L121) procedura `RebuildTree` wywołuje `FAstParser.TryParseStream(..., SyntaxTree)`.
   - Podpięcie pod zdarzenie [Memo1Change](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.pas#L215) czyści kontrolkę `TreeView1.Items.Clear`, ale **nie zwalnia obiektów węzłów AST** ([TSyntaxNode](file:///c:/Sources/github/rzemieslnik-kodu/delphi-ast/DelphiAST.Classes.pas)).
   - Każde pojedyncze naciśnięcie klawisza generuje i bezpowrotnie porzuca w pamięci całe drzewo obiektów. Brak zwalniania występuje również przy zamykaniu okna (`FormDestroy`).
2. **Brak buforowania zmian (debounce)**:
   - Synchroniczne parsowanie przy każdym znaku blokuje pętlę komunikatów Windows, wywołując zacinanie UI i migotanie widoku drzewa przy większych plikach.
3. **Nieergonomiczna obsługa błędów składniowych**:
   - Podczas pisania (stan przejściowo nieskładniowy) dotychczasowe drzewo jest natychmiast usuwane i zastępowane węzłem `Parse failed`. Lepszą praktyką jest zachowanie ostatniego poprawnego widoku drzewa i sygnalizacja błędu w pasku stanu [StatusBar1](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.pas#L23).
4. **Brak integracji z silnikiem formatowania**:
   - `AstViewer` korzysta z parsera, ale nie pozwala sformatować wpisanego kodu za pomocą silnika [TDelphiCodeFormatter](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L95).
5. **Jednokierunkowa nawigacja**:
   - Istnieje skok z węzła drzewa do linii kodu („Go to source”), lecz brak synchronizacji odwrotnej: kursor w `Memo1` $\to$ podświetlenie węzła w `TreeView1`.

### 2.2. Silnik formatowania (`delphi-formatter`)
1. **Sztywno zakodowane parametry stylu**:
   - Stałe [IndentWidth = 2](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L110) oraz [LineBreak = #13#10](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L111) uniemożliwiają konfigurację wcięć (np. 4 spacje) oraz formatu końców linii (CRLF vs LF).
2. **Luki w regułach pustych linii (blank lines)**:
   - W sekcji `interface` po deklaracjach `type` kolejna deklaracja metody (`procedure`/`function`) nie otrzymuje wymaganej pustej linii rozdzielającej (widoczne m.in. w [demo3.pas](file:///c:/Sources/github/rzemieslnik-kodu/demo3.pas)).
3. **Brak zawijania długich linii (wrapping)**:
   - Długie listy parametrów metod (`ntParameters`) i argumentów wywołań nie są automatycznie łamane, jeśli autor nie przełamał ich w kodzie źródłowym.
4. **Formatowanie nieaktywnych gałęzi preprocesora**:
   - Kod w nieaktywnych gałęziach `{$IFDEF}` jest formatowany płasko; wymaga to uściślenia reguł wcięć względnych.

### 2.3. Narzędzie CLI (`dfmt`)
1. **Brak trybu weryfikacji (`--check`) dla CI/CD**:
   - Niezbędna w potokach automatycznych (GitHub Actions) flaga weryfikująca poprawność sformatowania bez modyfikacji plików (kod wyjścia `0` – sformatowany, `1` – wymaga formatowania).
2. **Brak podglądu różnic (`--diff`)**:
   - Brak możliwości wypisania zmian w formacie unified diff przed nadpisaniem plików.
3. **Brak formatowania wsadowego / rekurencyjnego (`-r`)**:
   - Narzędzie nie wspiera masek ani rekurencyjnego przeszukiwania katalogów (np. `dfmt -w -r .\src`).
4. **Brak obsługi standardowego wejścia/wyjścia (potoki)**:
   - Brak obsługi `dfmt -` uniemożliwia bezpośrednią współpracę z zewnętrznymi edytorami (VS Code, LSP, Git hooks).
5. **Nieatomowy zapis przy `-w`**:
   - Bezpośrednie nadpisywanie plików grozi utratą danych w razie nagłego przerwania procesu.

### 2.4. Integracja ze środowiskiem RAD Studio IDE
- Brak gotowej konfiguracji narzędzia zewnętrznego w menu `Tools -> Configure Tools` w RAD Studio IDE.

---

## 3. Zintegrowany harmonogram wdrożenia (5 Faz)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                   ZINTEGROWANY HARMONOGRAM WDROŻENIA                    │
├─────────────────┬──────────────────┬─────────────────┬──────────────────┤
│ Faza 1: Błędy   │ Faza 2: Narzę-   │ Faza 3: Silnik  │ Faza 4: IDE, GUI │
│ i stabilność    │ dzia CLI i CI/CD │ i konfiguracja  │                  │
├─────────────────┼──────────────────┼─────────────────┼──────────────────┤
│ • Naprawa leak  │ • dfmt --check   │ • TFormatter-   │ • Format w GUI   │
│   w AstViewer   │ • dfmt --diff    │   Config        │ • Kursor -> AST  │
│ • Debounce      │ • dfmt -r (drzewo│ • Odstępy w     │ • Tools w IDE    │
│ • Statusbar błąd│   katalogów)     │   interface     │                  │
│                 │ • dfmt - (stdin) │ • Wrapping linii│                  │
│                 │ • Zapis atomowy  │ • Nowe testy    │                  │
└─────────────────┴──────────────────┴─────────────────┴──────────────────┘
```

---

### Faza 1: Eliminacja krytycznych błędów pamięci i stabilizacja edycji (Quick Wins)

#### Zadanie 1.1: Likwidacja wycieku pamięci w `AstViewer`
- **Plik:** [ast-viewer/MainForm.pas](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.pas), [ast-viewer/AstViewer.dpr](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/AstViewer.dpr)
- **Kroki:**
  1. Dodać prywatne pole `FCurrentSyntaxTree: TSyntaxNode;` do klasy `TForm1`.
  2. W procedurze `RebuildTree`:
     - Przed wyczyszczeniem `TreeView1.Items.Clear` wywołać `FreeAndNil(FCurrentSyntaxTree);`.
     - Po poprawnym wywołaniu `FAstParser.TryParseStream` przypisać: `FCurrentSyntaxTree := SyntaxTree;`.
  3. W procedurze `FormDestroy`:
     - Dodać `FreeAndNil(FCurrentSyntaxTree);`.
  4. Włączyć automatyczne raportowanie wycieków pamięci w [AstViewer.dpr](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/AstViewer.dpr):
     ```pascal
     ReportMemoryLeaksOnShutdown := True;
     ```

#### Zadanie 1.2: Wdrożenie mechanizmu Debounce i ulepszenie obsługi błędów
- **Plik:** [ast-viewer/MainForm.pas](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.pas)
- **Kroki:**
  1. Dodać komponent `FParseTimer: TTimer` tworzony w `FormCreate` (`Interval = 300` ms, domyślnie `Enabled = False`).
  2. W zdarzeniu `Memo1Change` resetować timer:
     ```pascal
     FParseTimer.Enabled := False;
     FParseTimer.Enabled := True;
     ```
  3. Przenieść wywołanie `RebuildTree` do zdarzenia timera `FParseTimerTimer`.
  4. Zmiana zachowania przy błędzie składni:
     - Nie czyścić istniejącego drzewa `TreeView1`.
     - Wyświetlić szczegółowy komunikat błędu (z numerem linii i kolumny) na pasku [StatusBar1](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.pas#L23).

---

### Faza 2: Rozbudowa narzędzia CLI `dfmt` i integracja z CI/CD

#### Zadanie 2.1: Implementacja trybu sprawdzania (`--check`)
- **Plik:** [delphi-formatter/src/dfmt.dpr](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/dfmt.dpr)
- **Kroki:**
  - Obsługa parametru `dfmt --check <plik...>`.
  - Dla każdego pliku porównać kod źródłowy z wynikiem `Formatter.FormatSource(Content)`.
  - Jeśli plik wymaga zmian: wypisać na konsolę `Needs formatting: <ścieżka>` i ustawić kod wyjścia `ExitCode := 1`.
  - Jeśli wszystkie pliki są zgodne: zakończyć z `ExitCode := 0`.

#### Zadanie 2.2: Implementacja trybu podglądu różnic (`--diff`)
- **Plik:** [delphi-formatter/src/dfmt.dpr](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/dfmt.dpr)
- **Kroki:**
  - Obsługa parametru `dfmt --diff <plik>`.
  - Generowanie zwięzłego zestawienia linii zmienionych / dodanych / usuniętych.

#### Zadanie 2.3: Obsługa rekurencyjnego przeszukiwania katalogów (`-r` / `--recursive`)
- **Plik:** [delphi-formatter/src/dfmt.dpr](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/dfmt.dpr)
- **Kroki:**
  - Dodanie flagi `-r` umożliwiającej przekazanie ścieżki katalogu: `dfmt -w -r .\src` lub `dfmt --check -r .\src`.
  - Rekurencyjne filtrowanie plików o rozszerzeniach: `.pas`, `.dpr`, `.dpk`, `.inc`.

#### Zadanie 2.4: Obsługa strumienia standardowego wejścia (`stdin`)
- **Plik:** [delphi-formatter/src/dfmt.dpr](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/dfmt.dpr)
- **Kroki:**
  - Gdy parametrem jest `-`, odczytać kod ze strumienia `Input` i wypisać sformatowany wynik na `Output`.

#### Zadanie 2.5: Bezpieczny (atomowy) zapis plików przy opcji `-w`
- **Plik:** [delphi-formatter/src/dfmt.dpr](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/dfmt.dpr)
- **Kroki:**
  - W procedurze `WriteFile`: zapisać treść do pliku tymczasowego (`AFileName + '.tmp'`), a następnie wykonać atomową podmianę pliku docelowego (`TFile.Replace` lub `MoveFileEx` z flagą nadpisania).

---

### Faza 3: Elastyczność silnika formatowania i reguły stylu

#### Zadanie 3.1: Wprowadzenie konfiguracji stylu (`TFormatterConfig`)
- **Plik:** [delphi-formatter/src/DelphiAST.Formatter.Engine.pas](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas)
- **Kroki:**
  - Zdefiniować strukturę konfiguracyjną:
    ```pascal
    type
      TLineEndingStyle = (lesCRLF, lesLF, lesAuto);

      TFormatterConfig = record
        IndentWidth: Integer;             // Domyślnie 2 spacje
        LineEnding: TLineEndingStyle;     // Domyślnie lesCRLF
        BlankLineBetweenMethods: Boolean; // Domyślnie True
        SpacesAroundOperators: Boolean;   // Domyślnie True
        class function Default: TFormatterConfig; static;
      end;
    ```
  - Przekazać `TFormatterConfig` do konstruktorów `TLayoutPlanner` oraz `TTokenEmitter`.
  - Zastąpić stałe `IndentWidth` i `LineBreak` wartościami pobieranymi z konfiguracji.

#### Zadanie 3.2: Korekta pustych linii w sekcji `interface`
- **Plik:** [delphi-formatter/src/DelphiAST.Formatter.Engine.pas:L707-L708](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L707-L708)
- **Kroki:**
  - Zapewnić wymuszenie pustej linii (`BlankBefore := True`) przed pierwszą deklaracją metody w sekcji `interface`, jeśli poprzedza ją sekcja typów (`ntTypeSection`), stałych (`ntConstants`) lub zmiennych (`ntVariables`).

#### Zadanie 3.3: Opcjonalne zawijanie długich linii (wrapping)
- **Plik:** [delphi-formatter/src/DelphiAST.Formatter.Engine.pas](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L328)
- **Kroki:**
  - Rozbudowa [TLayoutPlanner](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L328) o opcjonalne łamanie parametrów procedur/funkcji (`ntParameters`) po przekroczeniu ustalonego limitu znaków w wierszu (np. 100 znaków).

#### Zadanie 3.4: Rozszerzenie zestawu testów golden o nowoczesną składnię
- **Katalog:** `delphi-formatter/tests/golden/`
- **Kroki:**
  - Dodanie przypadku testowego dla deklaracji inline: `var X: Integer := 10;`.
  - Dodanie przypadku testowego dla pętli inline: `for var I := 0 to Count - 1 do`.
  - Weryfikacja idempotencji oraz zgodności fingerprintu tokenów.

---

### Faza 4: Integracje ze środowiskiem (GUI & RAD Studio IDE)

#### Zadanie 4.1: Przycisk „Formatuj kod” w `AstViewer`
- **Pliki:** [ast-viewer/MainForm.pas](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.pas), [ast-viewer/MainForm.dfm](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.dfm)
- **Kroki:**
  - Dodać przycisk `btnFormatCode: TButton` do panelu górnego [PanelTop](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.pas#L17).
  - W obsłudze zdarzenia sformatować tekst z `Memo1` przy użyciu [TDelphiCodeFormatter](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/src/DelphiAST.Formatter.Engine.pas#L95) i automatycznie odświeżyć drzewo AST.

#### Zadanie 4.2: Dwukierunkowa synchronizacja: kursor w `Memo1` $\to$ węzeł w `TreeView1`
- **Plik:** [ast-viewer/MainForm.pas](file:///c:/Sources/github/rzemieslnik-kodu/ast-viewer/MainForm.pas)
- **Kroki:**
  - W zdarzeniu `Memo1Click` oraz `Memo1KeyUp`: na podstawie `Memo1.CaretPos` odnaleźć w `FCurrentSyntaxTree` najbardziej zagnieżdżony węzeł obejmujący daną pozycję `(Line, Col)` i zaznaczyć powiązany `TTreeNode` w `TreeView1`.

#### Zadanie 4.3: Konfiguracja narzędzia `dfmt` w RAD Studio IDE
- **Zakres:**
  - Przygotowanie instrukcji / wpisu w dokumentacji konfiguracji zewnętrznego narzędzia w menu `Tools -> Configure Tools`:
    - **Title**: `Format Delphi Source (dfmt)`
    - **Program**: `$(PROJECTDIR)\bin\dfmt.exe`
    - **Working Directory**: `$(FILEDIR)`
    - **Parameters**: `-w "$EDNAME"`

---

## 4. Zintegrowana matryca priorytetów i ryzyk

| Zadanie | Opis zadania | Priorytet | Szacowany czas | Poziom ryzyka |
|---|---|---|---|---|
| **1.1** | Likwidacja wycieku pamięci w `AstViewer` | **Krytyczny** | 20 min | Niskie |
| **1.2** | Debounce edytora (300 ms) i statusbar w `AstViewer` | **Wysoki** | 25 min | Niskie |
| **2.1** | Flaga weryfikacji `dfmt --check` (CI/CD) | **Wysoki** | 30 min | Niskie |
| **2.2** | Podgląd różnic `dfmt --diff` | **Średni** | 30 min | Niskie |
| **2.3** | Rekurencyjne formatowanie katalogów `dfmt -r` | **Średni** | 45 min | Niskie |
| **2.4** | Obsługa potoków standardowego wejścia `dfmt -` | **Średni** | 30 min | Niskie |
| **2.5** | Bezpieczny (atomowy) zapis przy `dfmt -w` | **Średni** | 20 min | Niskie |
| **3.1** | Konfiguracja stylu `TFormatterConfig` | **Średni** | 1.5 godz. | Średnie |
| **3.2** | Poprawka pustych linii w sekcji `interface` | **Średni** | 30 min | Niskie |
| **3.3** | Zawijanie długich linii (wrapping parametrów) | **Niski** | 1.5 godz. | Średnie |
| **3.4** | Nowe przypadki golden dla nowoczesnej składni | **Średni** | 45 min | Niskie |
| **4.1** | Przycisk „Formatuj kod” w `AstViewer` | **Średni** | 25 min | Niskie |
| **4.2** | Dwukierunkowa nawigacja kursor $\to$ węzeł AST | **Niski** | 1 godz. | Niskie |
| **4.3** | Instrukcja integracji `dfmt` w RAD Studio IDE | **Niski** | 20 min | Zerowe |

---

## 5. Kryteria akceptacji (Definition of Done)

1. **Czystość pamięciowa (Zero Leaks)**:
   - Uruchomienie `AstViewer.exe` z flagą `ReportMemoryLeaksOnShutdown := True` i intensywna edycja tekstu w `Memo1` nie zgłasza żadnych wycieków obiektów `TSyntaxNode` po zamknięciu aplikacji.
2. **100% zgodności testów jednostkowych i golden**:
   - Wszystkie testy w [dfmt_golden.dpr](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/tests/dfmt_golden.dpr) oraz [dfmt_dunitx.dpr](file:///c:/Sources/github/rzemieslnik-kodu/delphi-formatter/tests/dfmt_dunitx.dpr) przechodzą bez błędów (`PASS`).
3. **Zgodność z potokami CI/CD**:
   - Polecenie `dfmt --check <plik>` zwraca kod wyjścia `0` dla sformatowanego kodu oraz kod `1` dla pliku wymagającego formatowania.
4. **Nienaruszalność inwariantów formatowania**:
   - `TokenFingerprint(Input) == TokenFingerprint(Output)` zachowane w 100% dla wszystkich plików testowych.
   - Idempotentność `Format(Format(Code)) = Format(Code)` bezwzględnie spełniona.
