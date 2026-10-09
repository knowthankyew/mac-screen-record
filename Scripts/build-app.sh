#!/usr/bin/env bash
# Build script: compiles the Swift package and wraps the binary into a .app bundle.
# Without full Xcode we cannot produce a notarized build, but this produces a
# locally-runnable app with ad-hoc code signing — enough for development.
set -euo pipefail

CONFIG="${1:-release}"           # debug | release
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Mac Screen Record"
EXEC_NAME="MacScreenRecord"
BUNDLE_ID="com.macscreenrecord.app"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

ARCH="${ARCH:-$(uname -m)}"

echo "==> Building Swift package ($CONFIG for $ARCH)..."
cd "$ROOT"
swift build -c "$CONFIG" --arch "$ARCH"

BIN_PATH="$(swift build -c "$CONFIG" --arch "$ARCH" --show-bin-path)"
BIN="$BIN_PATH/$EXEC_NAME"
test -f "$BIN" || { echo "Binary not found at $BIN"; exit 1; }

echo "==> Assembling .app bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Generate CycloneDX SBOM & embed supply chain notices
if [ -f "$ROOT/Scripts/generate-sbom.py" ]; then
    echo "==> Generating CycloneDX SBOM..."
    mkdir -p "$DIST_DIR"
    VERSION="$(defaults read "$ROOT/Resources/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "0.3.0")"
    python3 "$ROOT/Scripts/generate-sbom.py" "$DIST_DIR/bom.json" "$ARCH" "$VERSION"
    cp "$DIST_DIR/bom.json" "$APP_DIR/Contents/Resources/bom.json"
fi
if [ -f "$ROOT/NOTICE.md" ]; then
    cp "$ROOT/NOTICE.md" "$APP_DIR/Contents/Resources/NOTICE.md"
fi

# PkgInfo (legacy but expected)
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

CERT_NAME="Mac Screen Record Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
    if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
        SIGN_IDENTITY="$CERT_NAME"
        echo "==> Code signing with stable identity '$CERT_NAME'..."
    elif security find-certificate -c "Free Mac Screen Recorder Local" "$KEYCHAIN" >/dev/null 2>&1; then
        SIGN_IDENTITY="Free Mac Screen Recorder Local"
        echo "==> Code signing with inherited identity 'Free Mac Screen Recorder Local'..."
    else
        SIGN_IDENTITY="-"
        echo "==> Ad-hoc signing (run Scripts/setup-stable-signing.sh for persistent TCC permissions)..."
    fi
fi
find "$APP_DIR" -name "*.cstemp" -delete 2>/dev/null || true
codesign --force --deep --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Resources/MacScreenRecord.entitlements" \
    --options runtime \
    "$APP_DIR" || {
        echo "WARN: signing failed; bundle is unsigned." >&2
    }

echo ""
echo "✓ Built: $APP_DIR"
echo ""
echo "Run with:  open \"$APP_DIR\""
echo "Or:        \"$APP_DIR/Contents/MacOS/$EXEC_NAME\""
echo ""
echo "First launch: macOS will prompt for Screen Recording, Camera, Microphone"
echo "permissions. Grant them in System Settings → Privacy & Security, then"
echo "relaunch the app."
