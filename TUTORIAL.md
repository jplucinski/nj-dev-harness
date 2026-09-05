# Dev Harness: tutorial

Instrukcja obejmuje instalację, wybór projektu, worktree, kontekst dla AI oraz
notatki i TODO w Obsidianie.

> Dev Harness udostępnia ogólne narzędzia deweloperskie. Polecenia właściwe dla projektu, takie jak budowanie, testowanie czy uruchamianie aplikacji, nadal należą do lokalnego `Taskfile.yml` projektu.

## 1. Przygotuj środowisko

Wymagane są:

- Bash — systemowy na macOS albo Git Bash na Windows;
- [Task](https://taskfile.dev/);
- Git;
- `fzf`;
- `rg` (ripgrep);
- `grepai`.

Opcjonalnie warto zainstalować:

- Ollama do lokalnych embeddingów dla `gtask index` / `gtask semantic`;
- VS Code z poleceniem `code` w `PATH`;
- Atuin do bogatszej listy ostatnich kontekstów;
- Obsidian 1.12.7+ z włączonym CLI i Bases;
- wybrane CLI AI, np. Codex, Claude, Gemini, Copilot CLI lub OpenCode;
- Docker, jeżeli chcesz używać `gtask logs` i `gtask shell`.

## Demo bez instalacji — Docker

W katalogu rozpakowanego wydania albo checkoutu źródeł wykonaj:

```bash
docker build -f demo/Dockerfile -t dev-harness-demo .
docker run --rm -it dev-harness-demo
```

Kontener uruchomi Bash w repozytorium `payments-demo` z jednym zmodyfikowanym i
jednym nieśledzonym plikiem:

```bash
gtask
gtask open
gtask changed
gtask search -- retry
gtask semantic -- retry
gtask index
gtask changes
gtask context
why
```

W demo edytorem jest `less`; klawisz `q` wraca do pickera.
Kontener nie montuje katalogów hosta ani nie otrzymuje sekretów. VS Code,
Obsidian, Docker-in-Docker i zewnętrzne CLI AI nie są podłączone.
Polecenie `exit` kończy sesję, a `--rm` usuwa kontener.

## 2. Zainstaluj Dev Harness

Uruchom polecenie z katalogu zawierającego źródła albo rozpakowane wydanie.

### macOS lub Git Bash

```bash
./install.sh --configure-shell
```

### Windows PowerShell

PowerShell uruchamia instalator w Git Bash:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 --configure-shell
```

Instalator sprawdza wymagane narzędzia przed zapisem. Pliki zarządzane trafiają
do `~/.dev-harness`, konfiguracja do `~/.config/dev-harness`, a opcja
`--configure-shell` dodaje oznaczony blok do `~/.bashrc`.

Uruchom ponownie terminal albo wczytaj konfigurację:

```bash
source ~/.bashrc
```

## 3. Skonfiguruj pierwszy workplace

`DEV_WORKPLACE` wskazuje katalog zawierający Twoje projekty Git. Przykładowy układ:

```text
~/Workplace/
├── payments/
├── orders/
└── notifications/
```

Otwórz plik:

```text
~/.config/dev-harness/config.env
```

Minimalna konfiguracja:

```bash
export DEV_WORKPLACE="$HOME/Workplace"
export DEV_EDITOR="code"
```

Przykład pełniejszej konfiguracji:

```bash
export DEV_WORKPLACE="$HOME/Workplace"
export DEV_EDITOR="code"

# Opcjonalny wspólny katalog worktree. Bez tej wartości używany jest
# sąsiedni katalog .worktrees obok repozytorium.
# export DEV_WORKTREE_ROOT="$HOME/Worktrees"

# Pusta wartość oznacza aktywny vault Obsidiana.
export DEV_OBSIDIAN_VAULT=""

# Ścieżka katalogu vaulta używana przez skrót cvault.
# export DEV_OBSIDIAN_VAULT_PATH="$HOME/Documents/Obsidian/My Vault"

export DEV_AI_COMMAND="codex"
export DEV_AI_REVIEW_COMMAND="codex exec -"
export DEV_AI_RESUME_COMMAND="codex exec -"

export DEV_CONTEXT_MAX_LINES="4000"
export DEV_RESUME_LIMIT="10"
export DEV_TODO_DEFAULT_PRIORITY="p2"

# Przydatne, jeśli Git nie potrafi sam wykryć głównej gałęzi.
# export DEV_MAIN_BRANCH="main"
```

Po zmianie konfiguracji otwórz nowy terminal lub ponownie wykonaj `source ~/.bashrc`.

## 4. Sprawdź instalację

```bash
gtask doctor
```

Podstawowy tryb rozróżnia błędy od brakujących opcjonalnych integracji. Bardziej rygorystyczna kontrola traktuje również brak narzędzi opcjonalnych jako błąd:

```bash
gtask doctor -- --all
```

Polecenia pomocy:

```bash
gtask help
gtask aliases
gtask --list
```

## 5. Find — znajdź kontekst pracy

### Paleta poleceń

Uruchomienie `gtask` bez argumentów otwiera paletę `fzf`:

```bash
gtask
```

Wpisz fragment nazwy lub opis, także po polsku, np. `projekt`, `plik`, `notatka` albo `zadanie`. Wybrane polecenie zostanie zapisane w historii Bash, a przy aktywnym Atuinie również w jego historii.

### Wybierz projekt

```bash
cproj    # wybierz projekt i przejdź do niego
oproj    # wybierz projekt i otwórz go w DEV_EDITOR
cwork    # przejdź do DEV_WORKPLACE
cvault   # przejdź do DEV_OBSIDIAN_VAULT_PATH
```

Oba polecenia korzystają z katalogów bezpośrednio pod `DEV_WORKPLACE`.

### Wróć do ostatniej pracy

```bash
resume
```

Lista zawiera projekty, worktree i, jeśli jest dostępny, katalogi z historii
Atuin. Podgląd wybranego elementu pokazuje branch, zmiany względem bazy i
najważniejsze TODO.

Najważniejsze akcje w pickerze `resume`:

```text
Enter    przejdź do wybranego katalogu
Ctrl-O   otwórz w DEV_EDITOR
Ctrl-Y   skopiuj kontekst wznowienia
Ctrl-A   wyślij kontekst do skonfigurowanego AI
Ctrl-R   rozpocznij review zmian worktree
```

Wariant taskowy drukuje wybraną ścieżkę, ponieważ nie może zmienić katalogu
procesu nadrzędnego:

```bash
gtask resume
```

### Szybka orientacja i przekazanie pracy

Dostępne fast pathy:

```bash
gr                  # wróć do roota bieżącego worktree
dirty               # przejdź do repozytorium z niezapisanymi zmianami
why                 # zobacz branch, bazę, zmiany, commity i następne TODO
focus p0            # wybierz najważniejsze TODO i przejdź do jego projektu
handoff --copy      # skopiuj kontekst po odfiltrowaniu sekretów
standup --day       # dopisz lokalny status do dzisiejszej notatki Daily
```

W pickerach `dirty` i `focus` klawisz Enter zmienia katalog tylko dla funkcji
shellowej. Wersje `gtask dirty` i `gtask focus -- p0` drukują ścieżkę, ponieważ
proces potomny nie może zmienić katalogu terminala. Ctrl-O otwiera odpowiednio
worktree w `DEV_EDITOR` albo notatkę TODO w Obsidianie.

`focus` nie zgaduje projektu. Najpierw sprawdza bieżące repozytorium, następnie
bezpośrednie katalogi w `DEV_WORKPLACE`; brak dopasowania i wiele dopasowań kończą
się czytelnym błędem. TODO nadal można wtedy otworzyć przez Ctrl-O.

Domyślne tryby niczego nie zapisują. `handoff --copy` i `standup --copy` jawnie
używają schowka, a `standup --day` jest jedynym automatycznym zapisem Daily w tym
zestawie. Żadne z tych poleceń nie uruchamia AI. Tematy commitów i tytuły TODO są
tekstem użytkownika, więc sprawdź raport przed skopiowaniem lub zapisaniem.

### Znajdź plik albo symbol

```bash
gtask open
gtask changed
gtask search -- OrderService
gtask semantic -- authentication
gtask index
```

`gtask open` rekurencyjnie przeszukuje katalog, w którym zostało uruchomione, i
nie wymaga repozytorium Git. `gtask changed` działa również w repozytorium bez
pierwszego commita. Pickery pozwalają m.in. otworzyć wynik w edytorze oraz
przekazać wybrane pliki do AI.

## 6. Do — pracuj w izolowanym worktree

Przejdź do bazowego repozytorium i utwórz worktree:

```bash
cd "$DEV_WORKPLACE/payments"
gtask wt -- feature/retry-policy
```

Nazwa zawiera datę i czas. Jeśli ścieżka już istnieje, otrzymuje sufiks liczbowy.

Znajdź utworzone worktree:

```bash
gtask worktrees
cwt     # wybierz i przejdź do worktree
owt     # wybierz i otwórz w DEV_EDITOR
```

Picker worktree obsługuje:

```text
Enter    wybór ścieżki
Ctrl-O   otwarcie w DEV_EDITOR
Ctrl-Y   kopiowanie ścieżki
Ctrl-A   uruchomienie AI wewnątrz worktree
Ctrl-X   status i potwierdzane usunięcie
```

## 7. Zbuduj bezpieczny kontekst dla AI

Podsumowanie i wybór kontekstu:

```bash
gtask changes
gtask context
```

`gtask context` pozwala wybrać pliki. Dostępne warianty:

```bash
gtask context -- --all
gtask context -- --staged
gtask context -- --copy
```

Kontekst zawiera ograniczony diff i informacje o repozytorium. Typowe sekrety — m.in. `.env`, klucze prywatne, `.ssh`, keystore'y oraz drzewa `credentials*` i `secrets*` — są odfiltrowywane centralną polityką.

> Filtr bezpieczeństwa zmniejsza ryzyko, ale nie zastępuje kontroli człowieka. Przed wysłaniem danych do zewnętrznego modelu zawsze sprawdź zakres zmian.

### Interaktywne review

```bash
gtask review
```

`fzf` pozwala wybrać pliki. Bez interaktywnego terminala komenda kończy się
błędem i nie uruchamia AI.

### Jawne review wszystkich bezpiecznych zmian

```bash
gtask review -- --all
```

`--all` jest świadomą zgodą na przekazanie wszystkich zmian, które przeszły filtr ścieżek wrażliwych. Używaj go dopiero po sprawdzeniu `git status` i `gtask changes`.

Jeśli `DEV_AI_REVIEW_COMMAND` nie jest ustawione, Dev Harness wypisze prompt lokalnie zamiast wysyłać go do procesu AI.

## 8. Remember — notatki

Notatki są zapisywane w trzech katalogach:

```text
Notes/    zwykłe notatki
Daily/    zapis tego, co wydarzyło się dzisiaj
Weekly/   podsumowania tygodnia
```

### Zwykła notatka

```bash
gtask note -- "Pomysł na uproszczenie retry policy"
```

Notatka trafia pod root `Notes/`. Jeżeli polecenie uruchomisz w repozytorium, otrzyma metadane projektu wynikające z nazwy katalogu głównego Git.

### Dziennik dnia

```bash
gtask day -- "Naprawiłem timeout płatności i dodałem test regresyjny"
```

Tekst jest dopisywany do dzisiejszej notatki. W Obsidianie skonfiguruj core plugin Daily notes tak, aby używał katalogu `Daily/`.

### Podsumowanie tygodnia

```bash
gtask week -- "Domknąłem migrację płatności; zostało monitorowanie produkcji"
```

Tygodniowe wpisy są przechowywane pod rootem `Weekly/`.

### Tagi i właściwości

Tag opisuje temat, a nie stan pracy. Przykłady dobrych tagów:

```text
java
security
backend
kafka
architecture
```

Pola `project`, `status`, `priority`, `created` i `completed` są właściwościami Obsidiana — nie duplikuj ich jako tagów. Dzięki temu Bases może filtrować zadania po stabilnych polach, a tagi pozostają użyteczne tematycznie.

## 9. TODO — jedno zadanie, jeden plik

TODO są globalnymi notatkami Markdown pod:

```text
TODO/<rok>/<miesiąc>/<timestamp>-<slug>.md
```

Utworzenie TODO wymaga repozytorium Git, ponieważ jego nazwa staje się wartością `project`.

```bash
gtask todo -- "Sprawdzić retry policy"          # domyślnie P2
gtask todo -- p0 "Naprawić wyciek danych"
gtask todo -- p1 "Przygotować plan migracji"
gtask todo -- p3 "Posprzątać nazwy testów"
```

Priorytety:

```text
P0  krytyczny
P1  wysoki
P2  średni — domyślny
P3  niski
```

Listowanie bieżącego projektu:

```bash
gtask todo
gtask todo -- p1
```

Listowanie całego vaulta:

```bash
gtask todos
gtask todos -- p0
gtask todos -- done
```

Zakończenie i ponowne otwarcie zadania:

```bash
gtask done
gtask done -- p0
gtask reopen
```

Picker wybiera istniejącą notatkę. Zmieniają się wyłącznie właściwości `status` i `completed`; plik zachowuje ścieżkę, więc linki w Obsidianie pozostają stabilne.

Przykładowe właściwości TODO:

```yaml
type: todo
title: Naprawić retry policy
status: open
priority: p1
project: payments
created: 2026-09-03T10:30:00+02:00
completed:
tags:
  - backend
  - resilience
```

## 10. Przykładowy dzień pracy

```bash
# Znajdź projekt
cproj

# Utwórz izolowane środowisko zadania
gtask wt -- feature/retry-policy
cwt

# Pracuj przy użyciu lokalnych poleceń projektu
task test

# Zobacz zakres zmian i wybierz pliki do review
gtask changes
gtask review

# Zapisz rezultat dnia i kolejne działanie
gtask day -- "Dodałem retry z backoffem i test scenariusza timeout"
gtask todo -- p1 "Sprawdzić metryki retry na środowisku testowym"

# Następnego dnia wróć jednym poleceniem
dirty
why
focus p1
```

## 11. Dodaj własne ogólne narzędzie

Nie edytuj `~/.dev-harness`, bo aktualizacja może zastąpić zarządzane pliki. Dodaj prywatny task do:

```text
~/.config/dev-harness/Taskfile.yml
```

Przykład:

```yaml
version: '3'

tasks:
  ports:
    desc: Show listening ports
    dir: '{{.USER_WORKING_DIR}}'
    cmds:
      - your-command-here
```

Uruchomienie:

```bash
gtask ports
```

Aby task był widoczny w palecie, dodaj wiersz rozdzielony tabulatorami do:

```text
~/.config/dev-harness/palette.tsv
```

```text
ports<TAB>show listening ports<TAB>network porty sockets
```

Typ rozszerzenia zależy od działania:

- alias — skrócenie jednego polecenia;
- funkcja Bash — operacja musi zmienić bieżący shell, np. `cd`;
- globalny task — ogólne, odkrywalne narzędzie;
- skrypt — logika wieloetapowa;
- lokalny Taskfile projektu — build, test, run, deploy i release.

Wbudowany przewodnik pokażesz poleceniem:

```bash
gtask extend
```

## 12. Aktualizacja, diagnostyka i odinstalowanie

Aktualizacja z nowego katalogu źródeł lub wydania:

```bash
./install.sh update
```

Podgląd operacji bez zapisu:

```bash
./install.sh --dry-run --configure-shell
./install.sh uninstall --dry-run
```

Odinstalowanie usuwa tylko pliki zapisane w manifeście instalacji:

```bash
./install.sh uninstall
```

Usunięcie znanych plików konfiguracji osobistej:

```bash
./install.sh uninstall --purge-config
```

Nieznane pliki w katalogu konfiguracji, notatki i vault Obsidiana pozostają zachowane.

## Ściąga

```bash
gtask                    # paleta
gtask help               # mapa workflow
gtask aliases            # aliasy
resume                   # wróć do pracy
gr                       # root bieżącego repozytorium
.. / ... / ....          # poziom wyżej
-                        # poprzedni katalog
ll / la                  # listing
mkcd DIR                 # utwórz katalog i wejdź
dirty                    # przejdź do repozytorium ze zmianami
why                      # wyjaśnij bieżący kontekst
handoff --copy           # skopiuj bezpieczny kontekst przekazania
standup / standup --copy # pokaż / skopiuj status
standup --day            # dopisz status do Daily
focus p0                 # wybierz TODO i przejdź do projektu
cproj / oproj            # projekt: cd / VS Code
cwork / cvault           # przejdź do workplace / vaulta
cwt / owt                # worktree: cd / VS Code
gtask open               # wybierz plik pod bieżącym katalogiem
gtask changed            # wybierz zmieniony plik
gtask search -- TEXT     # szukaj w DEV_WORKPLACE
gtask semantic -- TEXT   # szukaj po znaczeniu
gtask index              # zbuduj indeks semantyczny
gtask wt -- BRANCH       # utwórz worktree
gtask context            # wybierz lokalny kontekst
gtask review             # interaktywne AI review
gtask review -- --all    # jawnie wszystkie bezpieczne zmiany
gtask note -- TITLE      # zwykła notatka
gtask day -- TEXT        # wpis dzienny
gtask week -- TEXT       # wpis tygodniowy
gtask todo -- p1 TEXT    # nowe TODO
gtask todo               # TODO projektu
gtask todos              # TODO całego vaulta
gtask done / reopen      # zakończ / otwórz ponownie
gtask doctor             # diagnostyka
```
