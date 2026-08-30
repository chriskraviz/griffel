#!/bin/bash
set -euo pipefail

# Griffel - sauberer Neustart auf diesem Mac
#
# Warum es das braucht: build.sh signiert die App ad-hoc, und eine Ad-hoc-
# Signatur hat keine stabile Identitaet. macOS erkennt eine App an Bundle-ID
# *plus* Signatur, also sieht jeder Rebuild fuer die Rechteverwaltung (TCC) wie
# eine neue App aus, waehrend der alte Eintrag stehen bleibt. Nach ein paar
# Builds stehen mehrere "Griffel" in den Bedienungshilfen und keiner
# davon ist der, der laeuft.
#
# Dieses Skript raeumt das auf. Nutzerdaten bleiben unangetastet, ausser du
# gibst --with-data ausdruecklich an.

BUNDLE_ID="app.griffel.mac"
KEYCHAIN_SERVICE="app.griffel.credentials"

# Fruehere Generationen dieser App, neueste zuerst: Griffel ist aus
# Blitztext hervorgegangen, und das kann noch Reste hinterlassen haben.
LEGACY_BUNDLE_IDS=("app.blitztext.mac")
LEGACY_KEYCHAIN_SERVICES=("app.blitztext.preview.credentials")

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_SUPPORT="$HOME/Library/Application Support/Griffel"
LEGACY_APP_SUPPORTS=(
    "$HOME/Library/Application Support/Blitztext"
)

WITH_DATA=false
DRY_RUN=false
ASSUME_YES=false

usage() {
    cat <<'USAGE'
Verwendung: ./scripts/reset-app.sh [--with-data] [--dry-run] [--yes]

Ohne Optionen:
  - beendet eine laufende Griffel-Instanz
  - setzt alle erteilten Rechte zurueck (Mikrofon, Bedienungshilfen, ...)
  - entfernt die von build.sh erzeugten App-Kopien und den Build-Ordner
  - meldet Geister-Eintraege aus der LaunchServices-Datenbank ab, damit
    sie aus der Rechteliste verschwinden

  Einstellungen, API-Key und deine Ablage mit den Aufnahmen bleiben.

--with-data
  Loescht zusaetzlich Einstellungen, Statistik, Braindump-Eingang, die
  Standard-Ablage und den OpenAI-Key aus dem Schluesselbund.
  Eine Ablage, die du auf einen eigenen Ordner gezeigt hast, wird NIE
  geloescht - das Skript sagt dir, wo sie liegt.

--dry-run   Zeigt nur, was passieren wuerde. Aendert nichts.
--yes       Ueberspringt die Rueckfrage bei --with-data.
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --with-data) WITH_DATA=true ;;
        --dry-run)   DRY_RUN=true ;;
        --yes|-y)    ASSUME_YES=true ;;
        --help|-h)   usage; exit 0 ;;
        *)
            echo "Unbekannte Option: $arg"
            echo ""
            usage
            exit 1
            ;;
    esac
done

run() {
    if [ "$DRY_RUN" = true ]; then
        echo "   [dry-run] $*"
        return 0
    fi
    "$@"
}

remove_path() {
    local target="$1"
    if [ ! -e "$target" ]; then
        return
    fi
    if [ "$DRY_RUN" = true ]; then
        echo "   [dry-run] wuerde entfernen: $target"
        return
    fi
    echo "   entferne: $target"
    rm -rf "$target"
}

if [ "$DRY_RUN" = true ]; then
    echo "🧪 Trockenlauf - es wird nichts veraendert."
    echo ""
fi

# --- 1. Laufende Instanz beenden -------------------------------------------
echo "1️⃣  Beende laufende Instanz ..."
if pgrep -f "Griffel.app/Contents/MacOS/Griffel" >/dev/null 2>&1; then
    run osascript -e 'tell application "Griffel" to quit' >/dev/null 2>&1 || true
    if [ "$DRY_RUN" = false ]; then
        sleep 1
        pkill -f "Griffel.app/Contents/MacOS/Griffel" 2>/dev/null || true
    fi
    echo "   beendet."
else
    echo "   laeuft nicht."
fi

# --- 2. Ablage-Ordner nachschlagen, bevor irgendetwas verschwindet ----------
CUSTOM_LIBRARY=""
SETTINGS_FILE="$APP_SUPPORT/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    CUSTOM_LIBRARY="$(plutil -extract library.rootPath raw -o - "$SETTINGS_FILE" 2>/dev/null || true)"
fi

# --- 3. Rechte zuruecksetzen -----------------------------------------------
# Muss VOR dem Loeschen der App-Bundles laufen: tccutil findet die Bundle-ID
# ueber die registrierte App und scheitert sonst mit
# "No such bundle identifier".
echo ""
echo "2️⃣  Setze erteilte Rechte zurueck ..."
for bundle in "$BUNDLE_ID" "${LEGACY_BUNDLE_IDS[@]}"; do
    if [ "$DRY_RUN" = true ]; then
        echo "   [dry-run] tccutil reset All $bundle"
        continue
    fi
    if tccutil reset All "$bundle" >/dev/null 2>&1; then
        echo "   zurueckgesetzt: $bundle"
    else
        # Exit 64 heisst nur "diese Bundle-ID kennt macOS nicht" - bei einer
        # nie installierten Alt-App der Normalfall, kein Fehler.
        echo "   nichts zurueckzusetzen: $bundle"
    fi
done

# --- 4. Gebaute Kopien entfernen -------------------------------------------
echo ""
echo "3️⃣  Entferne gebaute App-Kopien ..."
remove_path "$REPO_DIR/Griffel.app"
remove_path "$REPO_DIR/.derivedData-griffel-build"
remove_path "/Applications/Griffel.app"

# Weitere registrierte Kopien nur melden, nicht loeschen - sie koennen
# ueberall liegen, und ungefragt im Dateisystem des Nutzers aufzuraeumen
# waere die falsche Art von hilfsbereit.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    OTHER_COPIES="$("$LSREGISTER" -dump 2>/dev/null \
        | grep -oE "path: +[^ ]*Griffel\.app" \
        | sed 's/path: *//' \
        | sort -u \
        | grep -v "^$REPO_DIR/Griffel.app$" \
        | grep -v "^/Applications/Griffel.app$" \
        | grep -v "^$REPO_DIR/.derivedData-griffel-build" || true)"
    if [ -n "$OTHER_COPIES" ]; then
        echo ""
        echo "   ℹ️  Weitere Kopien sind bei macOS registriert. Diese loescht das"
        echo "      Skript nicht - pruefe selbst, ob du sie noch brauchst:"
        echo "$OTHER_COPIES" | sed 's/^/      /'
    fi
fi

# --- 5. Karteileichen aus LaunchServices abmelden --------------------------
# Hier stand frueher `lsregister -kill -r -domain ...`. macOS 26 hat -kill
# entfernt - der Aufruf scheitert dort mit "The -kill option has been removed",
# und unter `set -e` riss das den ganzen Reset mit, nachdem die App-Kopien
# bereits geloescht waren. Der naheliegende Ersatz -gc hilft nicht: er laesst
# genau die Eintraege stehen, deren Bundle nicht mehr existiert - also die
# Geister, die in den Bedienungshilfen stehen bleiben.
#
# Abgemeldet wird deshalb einzeln, und nur was nicht mehr auf der Platte liegt.
# Eine Kopie, die es noch gibt, bleibt registriert, auch wenn sie zu einem
# anderen Checkout gehoert - sie gehoert uns nicht.
echo ""
echo "4️⃣  Melde Karteileichen aus der LaunchServices-Datenbank ab ..."
if [ -x "$LSREGISTER" ]; then
    STALE="$("$LSREGISTER" -dump 2>/dev/null \
        | grep -oE "path: +[^ ]*Griffel\.app" \
        | sed 's/path: *//' \
        | sort -u \
        | while read -r registered; do
              [ -e "$registered" ] || echo "$registered"
          done)"
    if [ -z "$STALE" ]; then
        echo "   keine gefunden."
    else
        while IFS= read -r registered; do
            [ -n "$registered" ] || continue
            if [ "$DRY_RUN" = true ]; then
                echo "   [dry-run] wuerde abmelden: $registered"
            else
                echo "   meldet ab: $registered"
                "$LSREGISTER" -u "$registered" >/dev/null 2>&1 || true
            fi
        done <<< "$STALE"
    fi
else
    echo "   ⚠️  lsregister nicht gefunden - uebersprungen."
fi

# --- 6. Optional: Nutzerdaten ----------------------------------------------
if [ "$WITH_DATA" = true ]; then
    echo ""
    echo "5️⃣  Nutzerdaten loeschen"
    echo ""
    echo "   Das entfernt unwiderruflich:"
    echo "     - Einstellungen, Statistik, haeufige Phrasen, Braindump-Eingang"
    echo "     - den OpenAI API Key aus dem Schluesselbund"
    if [ -n "$CUSTOM_LIBRARY" ]; then
        echo ""
        echo "   Deine Ablage liegt in einem eigenen Ordner und bleibt unangetastet:"
        echo "     $CUSTOM_LIBRARY"
    else
        echo "     - die Standard-Ablage mit allen Aufnahmen und Transkripten:"
        echo "       $APP_SUPPORT/Aufnahmen"
    fi
    echo ""

    if [ "$ASSUME_YES" = false ] && [ "$DRY_RUN" = false ]; then
        read -r -p "   Wirklich loeschen? [tippe: loeschen] " answer
        if [ "$answer" != "loeschen" ]; then
            echo "   Abgebrochen. Es wurden keine Daten geloescht."
            exit 0
        fi
    fi

    remove_path "$APP_SUPPORT"
    remove_path "$HOME/Library/Caches/$BUNDLE_ID"
    remove_path "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    remove_path "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"

    for legacy_support in "${LEGACY_APP_SUPPORTS[@]}"; do
        remove_path "$legacy_support"
    done
    for legacy_bundle in "${LEGACY_BUNDLE_IDS[@]}"; do
        remove_path "$HOME/Library/Caches/$legacy_bundle"
        remove_path "$HOME/Library/Preferences/$legacy_bundle.plist"
        remove_path "$HOME/Library/Saved Application State/$legacy_bundle.savedState"
    done

    for service in "$KEYCHAIN_SERVICE" "${LEGACY_KEYCHAIN_SERVICES[@]}"; do
        if [ "$DRY_RUN" = true ]; then
            echo "   [dry-run] security delete-generic-password -s $service"
            continue
        fi
        # Mehrfach, weil pro Aufruf nur ein Eintrag verschwindet.
        while security delete-generic-password -s "$service" >/dev/null 2>&1; do :; done
        echo "   Schluesselbund geleert: $service"
    done
fi

echo ""
echo "✅ Fertig."
echo ""
echo "Naechste Schritte:"
echo "  1. ./build.sh --install --run"
echo "  2. Mikrofon erlauben"
echo "  3. Bedienungshilfen erlauben - der Kopie in /Applications,"
echo "     damit es genau eine gibt, die Rechte hat"
echo ""
echo "Damit die Rechte kuenftig einen Rebuild ueberleben, signiere mit einer"
echo "festen Identitaet statt ad-hoc - siehe \"A stable signing identity\" in der README."
