#!/bin/bash
set -euo pipefail

# Griffel macOS App - Build & Run
# Voraussetzungen: Full Xcode 26+, Metal-Toolchain, xcodegen
#
# Signieren: standardmaessig ad-hoc. Setze GRIFFEL_CODESIGN_IDENTITY
# oder lege .codesign-identity neben dieses Skript, um mit einer festen
# Identitaet zu signieren - dann ueberleben die erteilten Rechte einen Rebuild.

RUN_AFTER=false
INSTALL_APP=false
BUILD_CONFIGURATION="Release"
BUILD_ARCHS="arm64"

for arg in "$@"; do
    case "$arg" in
        --debug)
            BUILD_CONFIGURATION="Debug"
            ;;
        --run)
            RUN_AFTER=true
            ;;
        --install)
            INSTALL_APP=true
            ;;
        --release)
            BUILD_CONFIGURATION="Release"
            ;;
        *)
            echo "Unbekannte Option: $arg"
            echo "Verwendung: ./build.sh [--install] [--run] [--release] [--debug]"
            exit 1
            ;;
    esac
done

verify_app_architecture() {
    local app_path="$1"
    local app_name
    local binary_path
    local archs

    app_name="$(basename "$app_path" .app)"
    binary_path="$app_path/Contents/MacOS/$app_name"

    if [ ! -f "$binary_path" ]; then
        echo "❌ Konnte App-Binary nicht finden: $binary_path"
        exit 1
    fi

    archs="$(lipo -archs "$binary_path" 2>/dev/null || true)"

    if [[ -z "$archs" ]]; then
        echo "❌ Konnte Architekturen nicht lesen: $binary_path"
        file "$binary_path" 2>/dev/null || true
        exit 1
    fi

    # MLX rechnet ueber Metal auf der unified memory der M-Serie und baut nicht
    # fuer x86_64. Seit der lokalen Qwen-Nachbearbeitung ist die App daher
    # Apple-Silicon-only statt universal.
    if [[ " $archs " != *" arm64 "* ]]; then
        echo "❌ Build enthaelt kein arm64. Gefunden: $archs"
        file "$binary_path" 2>/dev/null || true
        exit 1
    fi

    echo "✅ Apple-Silicon-Binary verifiziert: $archs"
}

# MLX bringt eigene Metal-Shader mit, die beim Bauen kompiliert werden. Xcode 26
# liefert die dafuer noetige Toolchain nicht mehr mit. Ohne sie bricht der Build
# erst spaet ab - mitten in den MLX-Targets, mit sechs Fehlerbloecken, in denen
# der eine hilfreiche Satz untergeht. Deshalb hier vorne pruefen.
ensure_metal_toolchain() {
    if xcrun metal --version >/dev/null 2>&1; then
        return
    fi

    echo "❌ Die Metal-Toolchain fehlt."
    echo "   MLX kompiliert beim Bauen eigene Metal-Shader; Xcode bringt die"
    echo "   dafuer noetige Toolchain seit Version 26 nicht mehr mit."
    echo ""
    echo "   Einmalig nachladen (mehrere GB):"
    echo "   xcodebuild -downloadComponent MetalToolchain"
    echo ""
    exit 1
}

ensure_xcodebuild_available() {
    if xcodebuild -version >/dev/null 2>&1; then
        return
    fi

    local default_xcode="/Applications/Xcode.app/Contents/Developer"
    if [ -d "$default_xcode" ]; then
        export DEVELOPER_DIR="$default_xcode"
        if xcodebuild -version >/dev/null 2>&1; then
            echo "⚠️  Aktiver Developer-Pfad nutzt kein vollständiges Xcode. Verwende: $DEVELOPER_DIR"
            return
        fi
    fi

    echo "❌ xcodebuild ist nicht verfügbar."
    echo "   Installiere Xcode und wähle es mit:"
    echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/GriffelMac"
PROJECT_FILE="$PROJECT_DIR/GriffelMac.xcodeproj"
DERIVED_DATA_PATH="$SCRIPT_DIR/.derivedData-griffel-build"
cd "$PROJECT_DIR"

ensure_xcodebuild_available
ensure_metal_toolchain

# Feste Signier-Identitaet, falls konfiguriert. Ohne sie wird ad-hoc signiert,
# und weil eine Ad-hoc-Signatur keine stabile Identitaet hat, sieht jeder
# Rebuild fuer die Rechteverwaltung wie eine neue App aus.
# Der alte Name wird weiter akzeptiert: waere er nur umbenannt worden, fiele
# ein bestehendes Setup still auf Ad-hoc-Signatur zurueck - und damit setzt
# jeder Build die erteilten Rechte zurueck, also genau das, wogegen eine feste
# Identitaet gesetzt wurde.
CODESIGN_IDENTITY="${GRIFFEL_CODESIGN_IDENTITY:-}"
if [ -z "$CODESIGN_IDENTITY" ] && [ -f "$SCRIPT_DIR/.codesign-identity" ]; then
    CODESIGN_IDENTITY="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$SCRIPT_DIR/.codesign-identity" | head -1)"
fi

sign_app() {
    local target="$1"
    if [ -n "$CODESIGN_IDENTITY" ]; then
        echo "🔏 Signiere mit fester Identitaet: $CODESIGN_IDENTITY"
        codesign --force --sign "$CODESIGN_IDENTITY" "$target" 2>&1
    else
        echo "🔏 Signiere lokale Development-App ad-hoc. Dieses Artefakt ist nicht notarisiert."
        codesign --force --sign - "$target" 2>&1
    fi
}

if command -v xcodegen &> /dev/null; then
    echo "⚙️  Generiere Xcode-Projekt ..."
    xcodegen generate 2>&1
elif [ -d "$PROJECT_FILE" ]; then
    echo "⚠️  xcodegen nicht gefunden – nutze vorhandenes Xcode-Projekt."
else
    echo "❌ xcodegen fehlt."
    echo "   Installiere xcodegen explizit mit:"
    echo "   brew install xcodegen"
    echo "   Oder stelle sicher, dass $PROJECT_FILE vorhanden ist."
    exit 1
fi

# Bauen
echo "🔨 Baue Griffel ..."
xcodebuild \
    -project GriffelMac.xcodeproj \
    -scheme GriffelMac \
    -destination 'platform=macOS' \
    -configuration "$BUILD_CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="$BUILD_ARCHS" \
    clean build

# App finden
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/Griffel.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build fehlgeschlagen – keine App gefunden."
    exit 1
fi

verify_app_architecture "$APP_PATH"

# Resources manuell ins Bundle kopieren (xcodegen kopiert sie nicht automatisch)
echo "📋 Kopiere Resources ..."
RESOURCES_DIR="$APP_PATH/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
cp -f "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/" 2>/dev/null || true

# In Projektordner kopieren
DEST="$SCRIPT_DIR/Griffel.app"
rm -rf "$DEST"
cp -R "$APP_PATH" "$DEST"
sign_app "$DEST"
verify_app_architecture "$DEST"

RUN_TARGET="$DEST"

if [ "$INSTALL_APP" = true ]; then
    APPS_DIR="/Applications"
    INSTALL_DEST="$APPS_DIR/Griffel.app"
    if [ ! -w "$APPS_DIR" ]; then
        echo "❌ /Applications ist nicht beschreibbar."
        echo "   Fuehre den Befehl mit passenden Rechten erneut aus oder ziehe die App manuell nach /Applications."
        exit 1
    fi
    rm -rf "$INSTALL_DEST"
    cp -R "$DEST" "$INSTALL_DEST"
    sign_app "$INSTALL_DEST"
    verify_app_architecture "$INSTALL_DEST"
    RUN_TARGET="$INSTALL_DEST"
fi

echo ""
echo "✅ Fertig! App liegt unter:"
echo "   $DEST"
if [ "$INSTALL_APP" = true ]; then
    echo "   $RUN_TARGET"
fi
echo ""
echo "Build-Typ: $BUILD_CONFIGURATION"
echo "Architekturen: $BUILD_ARCHS"
echo "Kompatibel: Apple Silicon (macOS 14+)"
echo ""
echo "Naechste Schritte:"
echo "1. App starten"
echo "2. Mikrofon erlauben"
echo "3. Fuer direktes Einfuegen zusaetzlich Bedienungshilfen erlauben"
echo "4. In Griffel deinen eigenen OpenAI API Key eintragen"
echo "5. Loslegen und bei Bedarf im Code weiterbauen"
echo ""
if [ -z "$CODESIGN_IDENTITY" ]; then
    echo "ℹ️  Ad-hoc signiert: macOS haelt jeden Rebuild fuer eine neue App, also"
    echo "   sind Mikrofon und Bedienungshilfen nach dem naechsten Build erneut"
    echo "   faellig und alte Eintraege bleiben in der Liste stehen."
    echo "   Aufraeumen:        ./scripts/reset-app.sh"
    echo "   Dauerhaft loesen:  feste Signatur, siehe README (\"A stable signing identity\")"
    echo ""
fi

# Optional: direkt starten
if [ "$RUN_AFTER" = true ]; then
    echo "🚀 Starte Griffel ..."
    open "$RUN_TARGET"
fi
