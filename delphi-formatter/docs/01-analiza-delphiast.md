# Analiza DelphiAST pod kątem formattera (fazy 1–4)

Dokument opisuje **rzeczywisty** stan biblioteki DelphiAST znajdującej się w `delphi-ast/`
oraz wnioski dla architektury formattera. Każdy fakt został potwierdzony w kodzie źródłowym
lub zrzutem AST (`delphi-formatter/tools/astdump/samples/*.ast.txt`).

## 1. Projekt

| Element | Ustalenie |
|---|---|
| Wersja Delphi | `ProjectVersion 20.4` w `.dproj` → Delphi 12 Athens (`SimpleParser.inc` zna `VER360`/`VER370`) |
| Zależności | brak menedżera pakietów; DelphiAST wkopiowane do `delphi-ast/` (12 unitów), kompilacja przez `dcc32 -U".\delphi-ast"` |
| Istniejący kod parsera | `ast-viewer/SemanticTools.DelphiAstParser.pas` – `IAstParser.TryParse/TryParseStream` (wrapper na `TPasSyntaxTreeBuilder`, obsługa `{$I}` przez `IIncludeHandler`) |
| Istniejący formatter | brak – `dfmt.dpr` to pusty szablon konsoli, `Tests.Sample.pas` to jeden test-atrapa |
| Wyświetlanie AST | `ast-viewer/MainForm.pas` (TTreeView) |
| Writer w bibliotece | `DelphiAST.Writer.pas` – **tylko XML/binary serializacja**, nie ma pretty printera ani generatora kodu |

Wnioski: nic z istniejącego kodu nie pełni roli formattera; `SemanticTools.DelphiAstParser`
można wykorzystać jako fasadę parsera (jest w `ast-viewer`, wymagałoby przeniesienia do wspólnego katalogu).

## 2. Rzeczywiste API DelphiAST

### Parser (`DelphiAST.pas`)

```pascal
TPasSyntaxTreeBuilder = class(TmwSimplePasParEx)
  constructor Create; override;
  function Run(SourceStream: TStream): TSyntaxNode;            // instancyjny – zwraca root ntUnit
  class function Run(const FileName: string; InterfaceOnly: Boolean = False;
    IncludeHandler: IIncludeHandler = nil; OnHandleString: TStringEvent = nil): TSyntaxNode;
  property Comments: TObjectList<TCommentNode>;                // OwnsObjects = True
```

* `Run(TStream)` – jeśli strumień nie jest `TStringStream`, kopiuje go do własnego `TStringStream`
  (`SimpleParser.pas:705`). Dla `string` trzeba samemu utworzyć `TStringStream`.
* `InitDefinesDefinedByCompiler` pochodzi z lexera (`SimpleParser.Lexer.pas:2708`) – dodaje
  `VERxxx`, `MSWINDOWS` itd. zgodnie z kompilatorem, którym zbudowano formatter.
* Błąd składni → `ESyntaxTreeException` (`Line`, `Col`, `FileName`, `SyntaxTree` = częściowe drzewo).
  **Wyjątek jest właścicielem częściowego drzewa i zwalnia je w destruktorze** (`DelphiAST.pas:2822`).
* Pusty plik **nie** rzuca wyjątku – zwraca `ntUnit` bez atrybutów i dzieci.
* Fragment bez `unit ...;` (np. sama procedura) parsuje się poprawnie: root `ntUnit` bez `anName`
  z `ntMethod` jako dziecko.

### `TSyntaxNode` (`DelphiAST.Classes.pas`)

Klasa (nie rekord). Hierarchia:

| Klasa | Dodatkowe pola | Gdzie używana |
|---|---|---|
| `TSyntaxNode` | `Typ`, `ChildNodes: TArray<TSyntaxNode>`, `Attributes: TArray<TPair<TAttributeName,string>>`, `ParentNode`, `Line`, `Col`, `LineSeq`, `FileName` | większość węzłów |
| `TCompoundSyntaxNode` | `EndLine`, `EndCol` | `ntInterface`, `ntImplementation`, `ntUses`, `ntMethod`, `ntTypeDecl`, `ntStatements`, `ntInitialization`, `ntFinalization` (root `ntUnit` jest zwykłym `TSyntaxNode` – `DelphiAST.pas:2111`) |
| `TValuedSyntaxNode` | `Value: string` | `ntLiteral`, `ntName`, `ntLabel`, `ntField` (w stałych rekordowych) |
| `TCommentNode` | `Text: string` | tylko w `Builder.Comments`, **nie w drzewie** |

Metody: `GetAttribute(anX): string` (pusty string gdy brak), `HasAttribute`, `FindNode(ntX)` (tylko
bezpośrednie dzieci), `FindNode([ntA, ntB, ...])` (ścieżka, `ntUnknown` = dowolny), `HasChildren`,
`Clone`. Brak `GetChild(i)` – iteracja przez `for Child in Node.ChildNodes`.

**Ownership:** `AddChild` ustawia `ParentNode`; `TSyntaxNode.Destroy` zwalnia wszystkie dzieci
(`FreeAndNil(FChildNodes[i])`). Zwalnia się **wyłącznie root**. Komentarze są własnością
`TPasSyntaxTreeBuilder.Comments` i giną razem z builderem – trzeba je skopiować (`Clone`) lub
trzymać builder przy życiu do końca formatowania.

### `TSyntaxNodeType` (`DelphiAST.Consts.pas`)

130 wartości. Istotne dla formattera (potwierdzone zrzutami):

```
ntUnit ntInterface ntImplementation ntInitialization ntFinalization ntUses ntUnit(w uses)
ntTypeSection ntTypeDecl ntType ntTypeParams ntTypeParam ntConstraints ntTypeArgs ntHelper ntGuid
ntConstants ntConstant ntResourceString ntValue ntVariables ntVariable ntName ntField ntFields
ntPrivate ntProtected ntPublic ntPublished ntStrictPrivate ntStrictProtected
ntMethod ntParameters ntParameter ntReturnType ntProperty ntRead ntWrite ntIndex ntDefault ntMessage ntExternal
ntStatements ntStatement ntEmptyStatement ntAssign ntLHS ntRHS ntCall ntExpressions ntExpression
ntIf ntThen ntElse ntFor ntFrom ntTo ntDownTo ntIn ntWhile ntRepeat ntCase ntCaseSelector ntCaseLabels ntCaseLabel ntCaseElse
ntWith ntTry ntExcept ntExceptionHandler ntFinally ntRaise ntInherited ntGoto ntLabel
ntIdentifier ntLiteral ntSet ntElement ntDot ntIndexed ntGeneric ntAddr ntDeref ntUnaryMinus ntNot
ntAdd ntSub ntMul ntFDiv ntDiv ntMod ntAnd ntOr ntXor ntShl ntShr ntEqual ntNotEqual ntLower ntLowerEqual
ntGreater ntGreaterEqual ntAs ntIs ntIsNot ntNotIn ntBounds ntDimension ntAttributes ntAttribute ntExports
ntAnsiComment ntBorComment ntSlashesComment (tylko TCommentNode poza drzewem)
```

**Nie istnieją**: `ntCompoundStatement`, `ntVarSection`, `ntClass`, `ntRecord`, `ntProcedure`,
`ntFunction`, `ntBegin`, `ntEnd`, `ntComment`, `ntDirective`. Rodzaj typu jest w atrybucie
`anType` węzła `ntType` (`class`, `record`, `interface`, `array`, `set`, `pointer`, `classof`, `enum`
jako `anName=enum`), rodzaj metody w `anKind` węzła `ntMethod` (`procedure`, `function`, `constructor`,
`destructor`; **brak wartości dla `class operator`**).

### `TAttributeName` (14 wartości)

`anType anClass anForwarded anKind anName anVisibility anCallingConvention anPath anMethodBinding
anReintroduce anOverload anAbstract anInline anAlign`.
Wartości to stringi lower-case: `anMethodBinding` ∈ {`virtual`,`override`,`dynamic`},
`anCallingConvention` = token (`stdcall`…), flagi = `'true'`, `anKind` w `ntParameter` ∈ {`const`,`var`,`out`}.

## 3. Rzeczywista struktura AST – kluczowe obserwacje

Pełne zrzuty: `delphi-formatter/tools/astdump/samples/*.ast.txt` (narzędzie `AstDump.dpr`, kompilowalne
pod Delphi 12 i FPC 3.2.2 w trybie `-Mdelphi`).

* Sekcje: `ntUnit(anName)` → `ntInterface`, `ntImplementation`, `ntInitialization`, `ntFinalization`.
  Program (`.dpr`) też jest `ntUnit` – **słowo `program`/`library`/`unit` nie jest rozróżnialne**.
* Uses: `ntUses` → `ntUnit(anName='System.SysUtils')`, `anPath` dla `in 'plik.pas'`.
* Typy: `ntTypeSection` → `ntTypeDecl(anName)` → `ntType(anType=class|record|…)`; członkowie klasy
  zawsze przeniesieni pod węzły widoczności (`MoveMembersToVisibilityNodes`), rekordy bez sekcji
  widoczności mają pola bezpośrednio pod `ntType`.
* Metoda: `ntMethod(anKind, anName, anClass, anMethodBinding, anOverload, anAbstract, anInline,
  anReintroduce, anCallingConvention)` → `ntParameters` → `ntParameter(anKind)` → `ntName`, `ntType`,
  opcjonalnie `ntExpression` (wartość domyślna); `ntReturnType` → `ntType`; lokalne `ntVariables`,
  `ntConstants`, `ntLabel`, zagnieżdżone `ntMethod`; ciało = `ntStatements` (compound, ma EndLine/EndCol).
* **Grupa parametrów `A, B: Integer` jest rozbita na dwa `ntParameter`** z osobnym klonem `ntType`
  (identyczna `Line:Col` typu pozwala odtworzyć grupowanie – heurystyka). Tak samo pola klasy i zmienne.
* Instrukcje: `ntAssign(ntLHS, ntRHS)`, `ntCall` (statement-level opakowuje `ntCall` wyrażeniowy),
  `ntIf(ntExpression, ntThen, ntElse)`, `ntFor(ntIdentifier, ntFrom, ntTo|ntDownTo, body)`,
  `ntWhile(ntExpression, body)`, `ntRepeat(ntStatements, ntExpression)`,
  `ntCase(ntExpression, ntCaseSelector(ntCaseLabels, body)*, ntCaseElse)`,
  `ntTry(ntStatements, ntExcept(ntExceptionHandler(ntVariable, body))|ntFinally(ntStatements))`,
  `ntWith(ntExpressions, body)`, `ntInherited`, `ntRaise`, `ntGoto(ntLabel)`.
  Blok `begin..end` = `ntStatements`; pojedyncza instrukcja po `then` = bezpośrednie dziecko `ntThen`.
* Wyrażenia: drzewo operatorów (`ntAdd(lewy, prawy)`), **nawiasy zachowane** jako
  `ntExpressions → ntExpression` (s9: `(X + Y) * Z`). Typecast `Integer(X)` = `ntCall`. Generyki
  `TList<Integer>.Create` = `ntDot(ntGeneric(ntIdentifier, ntTypeArgs), ntIdentifier)`.
* Literały: `ntLiteral(anType=numeric|string|nil, Value)`. Liczby surowe (`$FF`, `3.14`).
  **Stringi są dequotowane**: `'It''s'` → `It's`, `'Hello'` → `Hello`.
* Pozycje: każdy węzeł ma `Line`, `Col` (1-based, pozycja tokenu otwierającego) i `LineSeq`.
  `EndLine/EndCol` tylko w compound nodes (`ntStatements`, `ntMethod`, `ntTypeDecl`, `ntUses`, sekcje).
  Węzły syntetyczne mogą mieć `0:0` (np. `ntAssign` dla `var Y := 5`).

## 4. Komentarze

* **Nie są w drzewie.** Lexer wywołuje `OnComment`; builder tworzy `TCommentNode(ntAnsiComment |
  ntBorComment | ntSlashesComment)` z `Line`, `Col`, `Text` (treść bez ograniczników) i dodaje do
  `Builder.Comments` (`DelphiAST.pas:1816`).
* Komentarz w **nieaktywnej gałęzi `{$IFDEF}` jest pomijany** (`SimpleParser.Lexer.pas:1343`:
  `if not FUseDefines or (FDefineStack = 0)`).
* Pozycja wskazuje początek komentarza; brak pozycji końca (można ją policzyć z `Text`).
* Aby przypisać komentarz do miejsca w kodzie, trzeba porównywać `Line/Col` komentarza z pozycjami
  węzłów – AST nie daje bezpośredniego powiązania.

## 5. Dyrektywy kompilatora

* **Żadna dyrektywa nie trafia do AST.** Lexer rozpoznaje `ptCompDirect`, `ptIfDefDirect`, `ptElseDirect`,
  `ptEndIfDirect`, `ptDefineDirect`, `ptIncludeDirect`, `ptIfDirect`, `ptElseIfDirect`, `ptIfEndDirect`,
  `ptIfOptDirect`, `ptResourceDirect`, `ptScopedEnumsDirect`, `ptUndefDirect`; parser (`SimpleParser.pas:817–905`)
  jedynie przechodzi dalej (`Sender.Next`). Zwykłe `{$R+}` / `{$APPTYPE}` wywołują `OnMessage(meNotSupported)` –
  builder ignoruje (rzuca tylko na `meError`).
* **Ewaluacja `{$IFDEF}` jest aktywna** (`UseDefines = True` domyślnie): tokeny i komentarze w gałęzi
  nieaktywnej są traktowane jak junk – zrzut s8 pokazuje, że `const Mode = 'Debug'` z gałęzi
  `{$IFDEF DEBUG}` **zniknęło całkowicie**, a `{$ELSE}` gałąź została sparsowana jak zwykły kod.
  Kod z gałęzi nieaktywnej **nie może być odtworzony z AST**.
* Lexer wystawia zdarzenia `OnCompDirect`, `OnIfDefDirect`, … oraz `IsCompilerDirective` – można nimi
  zebrać pozycje dyrektyw, ale nie ich wpływ na strukturę (np. `{$IFDEF}` obejmujący pół instrukcji `if`).
* `{$I plik.inc}` jest **rozwijany inline** gdy ustawiono `IncludeHandler` (węzły z pliku include mają
  inny `FileName`); bez handlera jest pomijany.

## 6. Potwierdzona utrata informacji w AST (blokery dla czystego AST-writera)

| Konstrukcja | Co widać w AST | Skutek |
|---|---|---|
| `'#13'` vs `#13` | oba `ntLiteral value="#13" anType=string` | niejednoznaczność – nie da się bezpiecznie odtworzyć literału |
| `'a'#13'b'` | `value="a#13b"` | jak wyżej |
| `reference to function: Integer` | `ntTypeDecl` → tylko `ntReturnType`, brak `ntType` | ginie `reference to` |
| `procedure(...) of object` | `ntType anName=procedure` | ginie `of object` |
| `TAlias = type Integer` | identycznie jak `TAlias = Integer` | ginie `type` |
| `class sealed`, `class abstract`, `packed` | brak atrybutu | ginie |
| `class var Count` | zwykłe `ntField` | ginie `class var` |
| `class operator Add` | `ntMethod anClass=true` bez `anKind` | ginie `operator` |
| `static;`, `deprecated 'x'`, `platform`, `library`, `experimental`, `final`, `assembler`, `varargs`, `export` | brak | ginie |
| `stored False`, `nodefault`, `dispid` w property | brak węzła | ginie |
| `case Kind: Integer of 0: (I: Integer)` w rekordzie | spłaszczone rodzeństwo `ntType/ntExpression/ntName/ntType` | struktura wariantu nie do odtworzenia |
| `Done:` (etykieta instrukcji) | tylko deklaracja `ntLabel` i `ntGoto` | ginie miejsce etykiety |
| `asm ... end` | `ntStatements anType=asm` bez dzieci | ginie treść |
| `program`/`library`/`unit` | zawsze `ntUnit` | ginie słowo kluczowe |
| komentarze | poza drzewem | wymagają osobnego scalania |
| wszystkie `{$...}` | brak | gubione; nieaktywne gałęzie znikają |
| `A, B: Integer` | 2× `ntParameter` | zmiana stylu deklaracji (semantycznie OK) |
| `Integer(X)` typecast | `ntCall` | odtwarzalne identycznie – OK |
| wielkość liter identyfikatorów/słów kluczowych | `anName` zachowuje oryginał; słowa kluczowe nie są w AST | OK dla identyfikatorów |

Wniosek: **AST DelphiAST jest drzewem semantycznym, nie składniowym (lossy).** Sam AST nie wystarcza,
by formatter był *structure-preserving* dla realnego kodu.

## 7. Warianty architektury

| Wariant | Zalety | Wady | Ryzyko | Koszt | Rekomendacja |
|---|---|---|---|---|---|
| **A. AST Writer** | prosta, naturalna dla AST, pełna kontrola układu | musi odtwarzać tekst z lossy AST: dyrektywy, `reference to`, `packed`, `static`, literały `#13` – **niemożliwe bez zgadywania**; komentarze doklejane heurystycznie | **wysokie**: cicha zmiana semantyki (zniknięcie `{$IFDEF}` i całych gałęzi kodu) | średni na start, rosnący (130 typów) | **nie** jako samodzielne rozwiązanie; akceptowalne tylko w trybie "fail-fast" na kodzie bez dyrektyw – nieprzydatne praktycznie |
| **B. AST → IR → Writer** | separacja, testowalność | odziedzicza wszystkie straty A + drugi model do utrzymania | wysokie (jak A) + koszt | wysoki | **nie** – abstrakcja nie rozwiązuje problemu źródłowego (brak danych w AST) |
| **C. AST + source range / tokeny (hybryda)** | AST decyduje o **strukturze** (wcięcia, łamanie linii, bloki), tekst pochodzi z **tokenów źródła** → zero utraty: komentarze, dyrektywy, `packed`, literały zachowane 1:1; nieaktywne gałęzie `{$IFDEF}` kopiowane jako tokeny | dwa źródła prawdy do zsynchronizowania (Line/Col węzła ↔ indeks tokenu); węzły syntetyczne z pozycją `0:0`; AST buduje się z `UseDefines=True`, tokeny trzeba pobrać drugim przebiegiem lexera z `UseDefines=False` | średnie: błędy mapowania widoczne od razu w golden testach; fallback = przepisz tokeny bez zmian | średni | **TAK** |
| **D. Token/lexer based** | `TmwPasLex` gotowy, dyrektywy i komentarze to zwykłe tokeny, nic nie ginie | brak wiedzy o strukturze → własny mini-parser do wcięć (`begin/end/case/record/class/try`), trudne wyrażenia wieloliniowe, `end` kończy klasę/rekord/case/begin/asm – kontekst trzeba śledzić ręcznie | średnie: ryzyko złych wcięć w rzadkich konstrukcjach, brak wykrywania błędów składni | średni | fallback / składnik wariantu C |
| **E. Istniejący writer** | – | `DelphiAST.Writer` to serializer XML/binarny; nie ma pretty printera ani visitora | – | – | **brak takiego mechanizmu**; do wykorzystania: `TmwPasLex` (lexer), `TSyntaxTreeWriter.ToXML` do debugowania |

### Rekomendacja: wariant C

Pipeline:

```
Source
  ├─ TPasSyntaxTreeBuilder.Run  →  AST (struktura, pozycje Line/Col/EndLine)
  └─ TmwPasLex (UseDefines=False, wszystkie tokeny łącznie z komentarzami/dyrektywami/whitespace)
         ↓
  TokenIndex: (Line,Col) → indeks tokenu
         ↓
  TASTCodeWriter: odwiedza AST, dla każdego "elementu liniowego" (nagłówek unitu, pozycja uses,
  deklaracja typu, pole, nagłówek metody, instrukcja) wyznacza zakres tokenów [start, end)
  i emituje go z normalizacją whitespace + własnym wcięciem; tokeny nienależące do żadnego
  węzła (komentarze, dyrektywy, gałęzie nieaktywne) są emitowane w kolejności źródłowej
  w miejscu, w którym występują między zakresami.
         ↓
  Formatted Source
```

Zasady bezpieczeństwa wynikające z tego wariantu:

* **Każdy token źródła musi zostać wyemitowany dokładnie raz** (inwariant sprawdzany w testach:
  `Tokens(Format(S)) minus whitespace == Tokens(S) minus whitespace`). To daje twardą gwarancję
  braku zmiany semantyki, niezależną od pokrycia AST.
* Węzły, których formatter nie rozumie, nie są gubione – ich zakres tokenów jest przepisywany bez zmian
  (tryb fallback), a typ węzła trafia do raportu "unhandled" (faza 11).
* Idempotencja: wynik zależy tylko od (tokeny bez whitespace, struktura AST); oba są identyczne dla
  wejścia i wyjścia, więc `Format(Format(S)) = Format(S)` z konstrukcji – testowane.

Ryzyka wariantu C:

1. Mapowanie węzła na zakres tokenów: `Line/Col` wskazuje pierwszy token, koniec trzeba wyznaczyć
   z następnego rodzeństwa lub `EndLine/EndCol` (dostępne tylko dla compound nodes) albo ze skanu tokenów
   do `;`. Wymaga starannych testów.
2. Węzły syntetyczne z pozycją `0:0` (inline `var Y := 5`) – trzeba je pominąć przy mapowaniu.
3. `{$IFDEF}` obejmujący fragment instrukcji – formatter musi degradować do przepisania linii bez zmian.
4. Pliki include (`{$I}`): AST zawiera węzły z innego `FileName`; formatter musi ignorować węzły
   spoza formatowanego pliku i przepisać dyrektywę `{$I}` jako token.
5. Środowisko: w tym kontenerze nie ma `dcc32`; DelphiAST kompiluje się pod FPC 3.2.2 po jednej
   poprawce w kopii `SimpleParser.pas` (rekurencja helpera `GetDataString`, tylko gałąź `{$IFDEF FPC}`).
   Silnik formattera można więc kompilować i sprawdzać pod FPC, ale DUnitX wymaga Delphi.

### Proponowany zakres pierwszego milestone (wariant C)

1. `DelphiAST.Formatter.Engine.pas`: `TDelphiCodeFormatter.FormatSource`, `TASTCodeWriter`
   (indent 2 spacje, `TStringBuilder`), `TSourceTokens` (lexer pass, indeks pozycji).
2. Układ (łamanie linii + wcięcia) dla: nagłówek unitu, sekcje, `uses` (jeden unit na linię),
   `type`/`const`/`var` sekcje, deklaracja klasy/rekordu/interfejsu z widocznościami i członkami,
   nagłówki i ciała metod, `begin/end`, `if/else`, `for`, `while`, `repeat`, `case`, `try/except/finally`,
   `with`, instrukcje proste.
3. Tekst wewnątrz linii (wyrażenia, listy parametrów, typy): przepisany token-po-tokenie z
   normalizacją odstępów (1 spacja wokół `:=` i operatorów binarnych, po `,` i `:`, brak przed `;`).
4. Komentarze i dyrektywy: zachowane 1:1 w miejscu wystąpienia (linia własna lub końcówka linii).
5. Testy: 20 testów z fazy 10 jako golden tests (`Input.pas` → `Expected.pas`), test inwariantu
   tokenów, test idempotencji, raport pokrycia `TSyntaxNodeType`.

Poza milestone 1 (do decyzji): łamanie długich linii, wyrównywanie, sortowanie niczego (formatter nie
zmienia kolejności), `asm`, rekordy wariantowe (przepisywane bez zmian w fallbacku).
