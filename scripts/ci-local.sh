#!/bin/bash
set -euo pipefail

# Griffel - die CI hier auf dem Mac
#
# Warum es das braucht: der Build laeuft in der CI auf einem macOS-Runner -
# in einem privaten Repository mit Faktor 10 aufs Minutenkontingent, und auch
# wo Minuten frei sind als langsamster, am laengsten wartender Schritt. Wer
# das Ergebnis vor dem Push will oder wessen Kontingent aufgebraucht ist,
# faehrt dieselben zwei Schritte stattdessen hier.
#
# Zwei bewusste Unterschiede zum Runner:
#
#   Der Secret-Scan laeuft gegen einen sauberen Export von HEAD, nicht gegen
#   den Arbeitsbaum. Ein Runner checkt aus, was committet ist; der Arbeitsbaum
#   traegt daneben Build-Ordner, .claude/ und was sonst noch herumliegt, und
#   jeder Fund darin waere ein Fehlalarm.
#
#   Der Build laeuft im Arbeitsbaum, weil er in einem frischen Export jedes
#   Swift-Paket neu aufloesen und MLX' Metal-Shader neu uebersetzen muesste.
#   Ist der Baum schmutzig, sagt das Skript es - dann baust du nicht das,
#   was du pushst.

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

PATTERNS_FILE=".github/secret-scan-patterns.txt"

SCAN_ONLY=false

usage() {
    cat <<'USAGE'
Verwendung: ./scripts/ci-local.sh [--scan-only] [--install-hook]

Ohne Optionen laufen beide CI-Schritte:
  1. Secret-Scan gegen einen Export von HEAD
  2. ./build.sh --debug

--scan-only     Nur Schritt 1. Dauert Sekunden statt Minuten.
--install-hook  Legt einen pre-push-Hook an, der vor jedem Push
                ./scripts/ci-local.sh --scan-only ausfuehrt.
                Git teilt Hooks ueber alle Worktrees hinweg.
USAGE
}

install_hook() {
    local hook_dir hook
    hook_dir="$(git rev-parse --git-path hooks)"
    hook="$hook_dir/pre-push"

    if [ -e "$hook" ]; then
        echo "❌ Es gibt schon einen pre-push-Hook:"
        echo "   $hook"
        echo ""
        echo "   Der wird nicht ueberschrieben. Sieh ihn dir an und haeng die"
        echo "   Zeile selbst an, wenn du beides willst:"
        echo "       \"\$(git rev-parse --show-toplevel)/scripts/ci-local.sh\" --scan-only"
        exit 1
    fi

    mkdir -p "$hook_dir"
    cat > "$hook" <<'HOOK'
#!/bin/bash
# Angelegt von scripts/ci-local.sh --install-hook.
#
# Absichtlich nur der Scan: er dauert Sekunden und verhindert das eine, was
# sich nicht zurueckholen laesst - einen gepushten Schluessel. Der Build
# dauert Minuten und ist an dieser Stelle der falsche Ort dafuer. Wer ihn
# trotzdem will, haengt hier --scan-only ab.
exec "$(git rev-parse --show-toplevel)/scripts/ci-local.sh" --scan-only
HOOK
    chmod +x "$hook"
    echo "✅ pre-push-Hook angelegt: $hook"
    echo "   Ueberspringen im Einzelfall: git push --no-verify"
}

for arg in "$@"; do
    case "$arg" in
        --scan-only)    SCAN_ONLY=true ;;
        --install-hook) install_hook; exit 0 ;;
        --help|-h)      usage; exit 0 ;;
        *)
            echo "Unbekannte Option: $arg"
            echo ""
            usage
            exit 1
            ;;
    esac
done

# --- 1. Secret-Scan ---------------------------------------------------------
echo "1️⃣  Secret-Scan gegen HEAD ..."

if [ ! -f "$PATTERNS_FILE" ]; then
    echo "   ❌ $PATTERNS_FILE fehlt - dieselbe Bedingung laesst die CI scheitern."
    exit 1
fi

PATTERN="$(grep -vE '^[[:space:]]*(#|$)' "$PATTERNS_FILE" | paste -sd'|' -)"
if [ -z "$PATTERN" ]; then
    echo "   ❌ Keine Muster aus $PATTERNS_FILE geladen."
    exit 1
fi

EXPORT_DIR="$(mktemp -d)"
trap 'rm -rf "$EXPORT_DIR"' EXIT
git archive HEAD | tar -x -C "$EXPORT_DIR"
echo "   $(find "$EXPORT_DIR" -type f | wc -l | tr -d ' ') Dateien aus HEAD exportiert."

if (cd "$EXPORT_DIR" && grep -RInE \
        --exclude-dir=.git \
        --exclude=secret-scan-patterns.txt \
        "$PATTERN" .); then
    echo ""
    echo "   ❌ Sieht aus wie ein Schluessel oder ein privater Verweis - oben steht wo."
    echo "      Die CI bricht an derselben Stelle ab."
    exit 1
fi
echo "   ✅ sauber."

if [ "$SCAN_ONLY" = true ]; then
    echo ""
    echo "✅ Fertig (nur Scan)."
    exit 0
fi

# --- 2. Build ---------------------------------------------------------------
echo ""
DIRTY="$(git status --porcelain --untracked-files=no)"
if [ -n "$DIRTY" ]; then
    echo "   ⚠️  Der Arbeitsbaum weicht von HEAD ab. Gebaut wird der Arbeitsbaum,"
    echo "      gescannt wurde HEAD - die beiden sind hier nicht dasselbe:"
    echo "$DIRTY" | sed 's/^/      /'
    echo ""
fi

echo "2️⃣  ./build.sh --debug ..."
./build.sh --debug

echo ""
echo "✅ Beide CI-Schritte sind hier durchgelaufen."
