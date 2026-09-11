#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Ramlet"
BIN_NAME="ramlet"
PROFILE="release"
SKIP_DMG=0
ARCH="$(uname -m)"

usage() {
  echo "usage: $0 [--release|--debug] [--skip-dmg] [arm64|x86_64]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)
      PROFILE="release"
      ;;
    --debug)
      PROFILE="debug"
      ;;
    --skip-dmg)
      SKIP_DMG=1
      ;;
    arm64|x86_64)
      ARCH="$1"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
  shift
done

case "$ARCH" in
  arm64|aarch64)
    ARCH="arm64"
    TARGET_TRIPLE="aarch64-apple-darwin"
    ;;
  x86_64)
    TARGET_TRIPLE="x86_64-apple-darwin"
    ;;
  *)
    echo "unsupported arch: $ARCH" >&2
    exit 2
    ;;
esac

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS-$ARCH.zip"
DMG_DIR="$DIST_DIR/dmg"
DMG_PATH="$DIST_DIR/$APP_NAME-$ARCH.dmg"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-13.0}"

BUILD_ARGS=(--manifest-path "$ROOT_DIR/Cargo.toml" --locked --target "$TARGET_TRIPLE")
if [[ "$PROFILE" == "release" ]]; then
  BUILD_ARGS=(--release "${BUILD_ARGS[@]}")
fi

echo "Building $APP_NAME for $ARCH ($PROFILE)..."
if command -v rustup >/dev/null 2>&1; then
  rustup target add "$TARGET_TRIPLE" >/dev/null
fi
cargo build "${BUILD_ARGS[@]}"

BINARY="$ROOT_DIR/target/$TARGET_TRIPLE/$PROFILE/$BIN_NAME"

echo "Creating app bundle..."
rm -rf "$APP_DIR" "$DMG_DIR" "$ZIP_PATH" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY" "$MACOS_DIR/$BIN_NAME"
chmod 755 "$MACOS_DIR/$BIN_NAME"
cp "$ROOT_DIR/macos/Info.plist" "$CONTENTS_DIR/Info.plist"

shopt -s nullglob
for lproj in "$ROOT_DIR"/macos/*.lproj; do
  dest="$RESOURCES_DIR/$(basename "$lproj")"
  mkdir -p "$dest"
  cp -R "$lproj/." "$dest/"
done

if [[ -n "${RAMLET_CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --sign "$RAMLET_CODESIGN_IDENTITY" --deep "$APP_DIR"
else
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Creating zip..."
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if [[ "$SKIP_DMG" -eq 0 ]]; then
  echo "Creating DMG..."
  mkdir -p "$DMG_DIR"
  cp -R "$APP_DIR" "$DMG_DIR/"
  ln -s /Applications "$DMG_DIR/Applications"
  hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"
  rm -rf "$DMG_DIR"
  echo "$DMG_PATH"
fi

echo "$APP_DIR"
echo "$ZIP_PATH"
