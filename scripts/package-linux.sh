#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT_DIR"

VERSION=$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)
BUNDLE_DIR=build/linux/x64/release/bundle
OUT_DIR=build/releases/linux
WORK_DIR=build/packaging/linux
APP_DIR=$WORK_DIR/FAV.AppDir
DEB_ROOT=$WORK_DIR/deb

if [[ ! -x "$BUNDLE_DIR/fav" ]]; then
  echo "Linux release bundle not found; run 'flutter build linux --release' first." >&2
  exit 1
fi

if find "$BUNDLE_DIR" \( -name __pycache__ -o -name '*.pyc' -o -name '.__*' \) \
  -print -quit | grep -q .; then
  echo "Refusing to package generated or metadata files:" >&2
  find "$BUNDLE_DIR" \( -name __pycache__ -o -name '*.pyc' -o -name '.__*' \) >&2
  exit 1
fi

rm -rf "$OUT_DIR" "$WORK_DIR"
mkdir -p "$OUT_DIR" "$APP_DIR/usr/lib/fav" "$DEB_ROOT"
cp -a "$BUNDLE_DIR/." "$APP_DIR/usr/lib/fav/"

install -Dm755 packaging/linux/AppRun "$APP_DIR/AppRun"
install -Dm644 packaging/linux/fav.desktop \
  "$APP_DIR/usr/share/applications/fav.desktop"
install -Dm644 packaging/linux/fav.png \
  "$APP_DIR/usr/share/icons/hicolor/512x512/apps/fav.png"
ln -s usr/share/applications/fav.desktop "$APP_DIR/fav.desktop"
ln -s usr/share/icons/hicolor/512x512/apps/fav.png "$APP_DIR/fav.png"

LINUXDEPLOY_VERSION=1-alpha-20251107-1
LINUXDEPLOY_SHA256=c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d
LINUXDEPLOY=$WORK_DIR/linuxdeploy-x86_64.AppImage
RUNTIME_VERSION=20251108
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
RUNTIME=$WORK_DIR/runtime-x86_64
curl --fail --location --silent --show-error \
  "https://github.com/linuxdeploy/linuxdeploy/releases/download/$LINUXDEPLOY_VERSION/linuxdeploy-x86_64.AppImage" \
  --output "$LINUXDEPLOY"
echo "$LINUXDEPLOY_SHA256  $LINUXDEPLOY" | sha256sum --check --status
chmod +x "$LINUXDEPLOY"
curl --fail --location --silent --show-error \
  "https://github.com/AppImage/type2-runtime/releases/download/$RUNTIME_VERSION/runtime-x86_64" \
  --output "$RUNTIME"
echo "$RUNTIME_SHA256  $RUNTIME" | sha256sum --check --status

APPIMAGE_EXTRACT_AND_RUN=1 APPIMAGETOOL_RUNTIME_FILE="$RUNTIME" \
  ARCH=x86_64 LINUXDEPLOY_OUTPUT_VERSION="$VERSION" \
  "$LINUXDEPLOY" --appdir "$APP_DIR" \
  --executable "$APP_DIR/usr/lib/fav/fav" \
  --desktop-file packaging/linux/fav.desktop \
  --icon-file packaging/linux/fav.png \
  --custom-apprun packaging/linux/AppRun \
  --output appimage
mv FAV-"$VERSION"-x86_64.AppImage "$OUT_DIR/fav-$VERSION-x86_64.AppImage"

install -Dm755 "$BUNDLE_DIR/fav" "$DEB_ROOT/usr/lib/fav/fav"
cp -a "$BUNDLE_DIR/lib" "$BUNDLE_DIR/data" "$DEB_ROOT/usr/lib/fav/"
mkdir -p "$DEB_ROOT/usr/bin"
ln -s /usr/lib/fav/fav "$DEB_ROOT/usr/bin/fav"
install -Dm644 packaging/linux/fav.desktop \
  "$DEB_ROOT/usr/share/applications/fav.desktop"
install -Dm644 packaging/linux/fav.png \
  "$DEB_ROOT/usr/share/icons/hicolor/512x512/apps/fav.png"
mkdir -p "$DEB_ROOT/DEBIAN"
cat >"$DEB_ROOT/DEBIAN/control" <<EOF
Package: fav
Version: $VERSION
Section: net
Priority: optional
Architecture: amd64
Maintainer: FAV contributors
Depends: libgtk-3-0 | libgtk-3-0t64, libsecret-1-0
Description: Free and verifiable WireGuard VPN provisioner
 Provision and manage dedicated Debian or Ubuntu WireGuard servers over SSH.
EOF
dpkg-deb --root-owner-group --build "$DEB_ROOT" \
  "$OUT_DIR/fav_${VERSION}_amd64.deb"

(cd "$OUT_DIR" && sha256sum ./* > SHA256SUMS-linux-x64)
echo "Linux packages written to $OUT_DIR"
