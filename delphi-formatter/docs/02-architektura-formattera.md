# Delphi Code Formatter – architektura (wariant C)

Silnik: `delphi-formatter/src/DelphiAST.Formatter.Engine.pas`.
Analiza, na której oparto decyzje: `01-analiza-delphiast.md`.

## Architecture

```
ASourceCode
   ├── TPasSyntaxTreeBuilder.Run(TStringStream)  → AST (TSyntaxNode, pozycje Line/Col, EndLine/EndCol)
   └── TmwPasLex (UseDefines = False)            → TSourceTokens: KAŻDY token, także whitespace,
                                                    komentarze, dyrektywy, obie gałęzie {$IFDEF}
             ↓                                          ↓
        TLayoutPlanner  ── odwiedza AST, dla tokenów ustawia TLayoutMark:
                           BreakBefore / Indent / BlankBefore / JoinPrevious / GenericBracket
             ↓
        TTokenEmitter   ── iteruje po tokenach w kolejności źródłowej:
                           pomija oryginalne spacje i CRLF, wstawia własne łamanie linii i wcięcia
                           (2 spacje na poziom), normalizuje odstępy między tokenami
             ↓
        Formatted Source
```

Klasy:

| Klasa | Odpowiedzialność |
|---|---|
| `TDelphiCodeFormatter` | API: `FormatSource`, `Coverage`, `TokenFingerprint`; parsowanie, orkiestracja, zwalnianie |
| `TSourceTokens` | drugi przebieg lexera, indeks `(Line, Col) → token`, klasyfikacja tokenów |
| `TLayoutPlanner` | traverser AST: `VisitRoot/VisitSection/VisitDeclaration/VisitTypeDecl/VisitTypeBody/VisitMember/VisitMethod/VisitBlock/VisitStatement/VisitIf/VisitLoop/VisitRepeat/VisitCase/VisitTry`; wyznacza zakresy tokenów węzłów (`StartIndex`, `EndIndex`, `ClosingTokenIndex`) |
| `TTokenEmitter` | reguły odstępów (`NeedSpaceBefore`), pustych linii, linii kontynuacji, komentarzy i dyrektyw |

Kluczowa własność: **AST decyduje tylko o układzie**, tekst pochodzi wyłącznie z tokenów.
Dlatego formatter nie może zgubić ani zmienić żadnego tokenu, niezależnie od tego, jak dużo AST
rozumie. Inwariant `TokenFingerprint(Input) = TokenFingerprint(Output)` jest sprawdzany w każdym
teście golden.

### Reguły układu

* Sekcje `interface/implementation/initialization/finalization` i końcowe `end.` – kolumna 0, pusta
  linia przed. Pierwsza deklaracja w sekcji oraz `uses/type/const/var/exports` i metody w
  `implementation` – pusta linia przed.
* `uses` – każdy moduł w osobnej linii, wcięcie 1.
* `type/const/var` – słowo kluczowe na poziomie sekcji, deklaracje +1. Grupy `A, B: Integer` są
  rozpoznawane po wspólnej pozycji sklonowanego węzła `ntType` i pozostają w jednej linii.
* Klasa/rekord/interfejs – widoczności na poziomie deklaracji typu, członkowie +1, `end` na poziomie
  deklaracji. Prefiksy `class var`, `class const`, `strict` są dołączane do członka.
* Metody – nagłówek na poziomie sekcji (metody zagnieżdżone +1), `begin/end` na poziomie nagłówka,
  instrukcje +1.
* `if/for/while/with/on` – blok `begin` na poziomie instrukcji nadrzędnej, pojedyncza instrukcja +1;
  `else if` w jednej linii; `case` – etykiety +1, pojedyncza instrukcja po etykiecie w tej samej linii,
  blok `begin` +2, `else` na poziomie `case`; `try/finally/except/until/end` na poziomie instrukcji.
* Wyrażenia, listy parametrów, typy – bez łamania; odstępy: 1 spacja wokół operatorów binarnych i `:=`,
  po `,` i `:`, brak przed `; , ) ] . :`, brak po `( [ . @`, brak wokół `..` i nawiasów generyków,
  brak między identyfikatorem/typem a `(`/`[`, jednoargumentowe `-`/`+`/`@`/`^` bez spacji.
* Łamanie linii wewnątrz instrukcji wprowadzone przez autora jest zachowane jako linia kontynuacji
  (+1 względem instrukcji). Puste linie autora są zachowane (maksymalnie jedna), z wyjątkiem miejsc
  bez informacji (po `begin`, przed `end`).

## Supported AST nodes

Węzły z dedykowaną regułą układu (raport `Coverage.Handled` dla 20 testów golden):

```
ntUnit ntInterface ntImplementation ntInitialization ntFinalization ntUses ntUnit(uses)
ntTypeSection ntTypeDecl ntType(class|record|interface|dispinterface|object) ntTypeParams ntTypeArgs
ntPrivate ntProtected ntPublic ntPublished ntStrictPrivate ntStrictProtected
ntField ntProperty ntConstant ntConstants ntResourceString ntVariables ntVariable ntLabel
ntExports ntElement ntAttributes ntGuid ntMethod ntAnonymousMethod
ntStatements ntAssign ntCall ntInherited ntRaise ntGoto ntEmptyStatement
ntIf ntThen ntElse ntFor ntWhile ntWith ntRepeat
ntCase ntCaseSelector ntCaseElse ntTry ntFinally ntExcept ntExceptionHandler
```

## Unsupported AST nodes

Wszystkie pozostałe typy (wyrażenia: `ntExpression`, `ntAdd`, `ntDot`, `ntLiteral`, …; `ntParameters`,
`ntReturnType`, `ntBounds`, `ntEnum`, `ntSet`, `ntHelper`, …) **nie wymagają** obsługi – ich tokeny są
przepisywane w linii z normalizacją odstępów. Nieznany typ instrukcji lub deklaracji otrzymuje
domyślną regułę "nowa linia na bieżącym poziomie" i trafia do `Coverage.Unhandled`.
`dfmt --coverage plik.pas` oraz `dfmt_golden --coverage` drukują raport.

## Comment handling

DelphiAST nie umieszcza komentarzy w drzewie (lista `Builder.Comments` poza drzewem, pomijane w
nieaktywnych gałęziach). Formatter **nie korzysta z tej listy** – komentarze są zwykłymi tokenami
drugiego przebiegu lexera, więc żaden nie ginie:

* komentarz w osobnej linii → osobna linia z wcięciem następnej zaplanowanej linii kodu
  (przed `end/until/finally/except/else` +1),
* komentarz końcowy (`X := 1; // c`) → pozostaje w tej samej linii, 1 spacja przed,
* komentarz `{ }` / `(* *)` w środku instrukcji → pozostaje w linii,
* po `//` łamanie linii jest wymuszone (także dla `else // c` + `if`),
* wymagana pusta linia przed deklaracją jest wstawiana **przed** komentarzem, który ją dokumentuje.

## Directive handling

Dyrektywy `{$...}` również nie istnieją w AST. Lexer formattera pracuje z `UseDefines = False`, więc
tokeny **obu gałęzi** `{$IFDEF}/{$ELSE}` są w strumieniu. Gałąź, którą parser AST uznał za nieaktywną,
nie ma węzłów, więc jej kod jest przepisywany "płasko": każda linia źródłowa na poziomie wcięcia
dyrektywy, która ją otwiera. Dyrektywy w osobnej linii są wyrównywane do następnej linii kodu;
dyrektywy w środku linii pozostają w linii. `{$I plik}` – lexer połyka ten token, gdy nie ma
`IncludeHandler`; `TSourceTokens` odtwarza go z luki między tokenami i wstawia bez zmian.
Formatter nie rozwija plików include (brak `IncludeHandler` w builderze).

## Memory ownership

| Obiekt | Właściciel | Zwalnianie |
|---|---|---|
| `TPasSyntaxTreeBuilder` | `ParseSource` | `try/finally Builder.Free` – od razu po `Run` |
| root `TSyntaxNode` (`ntUnit`) | `FormatSource` | `try/finally Root.Free`; dzieci zwalnia destruktor węzła, **nigdy nie zwalnia się dzieci osobno** |
| częściowe drzewo przy błędzie | `ESyntaxTreeException` | zwalniane w destruktorze wyjątku; formatter przepisuje tylko komunikat do `EDelphiFormatterException` |
| `Builder.Comments` | builder | nieużywane przez formatter |
| `TStringStream`, `TSourceTokens`, `TLayoutPlanner`, `TTokenEmitter`, `TStringBuilder`, `TmwPasLex` | metoda, która je tworzy | `try/finally` |

## Error handling

* pusty lub złożony tylko z białych znaków kod → `''`,
* błąd parsera → `EDelphiFormatterException` z pozycją (`Parse error at L:C: ...`); formatter nie
  produkuje wyniku częściowego, bo bez AST nie może ręczyć za układ,
* nieobsługiwane węzły → przepisanie tokenów + raport `Coverage`, nigdy utrata kodu.

## Known limitations

1. Kod w nieaktywnej gałęzi `{$IFDEF}` nie jest formatowany strukturalnie (płaskie wcięcie).
2. `{$IFDEF}` przecinający instrukcję (np. obejmujący `else`) – `end`/`else` mogą nie zostać
   rozpoznane, wtedy fragment pozostaje w układzie źródłowym; kod nie jest tracony.
3. Brak łamania długich linii i wyrównywania; łamanie w wyrażeniach jest takie jak w źródle.
4. Parser DelphiAST jest tolerancyjny (np. akceptuje `if then`) – formatter nie waliduje składni.
5. Wiele dyrektyw w jednej linii (`{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}`) rozdzielane jest spacjami.
6. Etykiety instrukcji (`Done:`) i treść bloków `asm` są przepisywane jako linie kontynuacji.
7. Wielkość liter słów kluczowych i identyfikatorów nie jest zmieniana (zgodnie z zasadą
   zachowania tokenów).
8. Wyjście używa końca linii `#13#10`; testy porównują po normalizacji końców linii.
9. Kompilacja pod Free Pascal wymaga poprawki `{$IFDEF FPC}` w `SimpleParser.pas` (poza tym repo);
   pod Delphi 12 nie ma tej potrzeby.

## Future extensions

* Łamanie długich list parametrów/argumentów (planer zna `ntParameters`/`ntExpressions`).
* Konfiguracja stylu (`begin` w linii `then`, szerokość wcięcia) – tylko zmiany w planerze.
* Formatowanie nieaktywnych gałęzi przez drugi przebieg parsera z odwróconymi definicjami.
* Rozwijanie `{$I}` przez `IncludeHandler` z pominięciem węzłów o innym `FileName`.
* Opcjonalna normalizacja wielkości liter słów kluczowych (zmienia tokeny – wymaga osobnego
  inwariantu porównującego bez rozróżniania wielkości).
