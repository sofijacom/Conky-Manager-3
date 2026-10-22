#!/bin/sh
# Install (or uninstall with --uninstall) Conky Manager 3 system-wide.
# Usage: sudo ./install.sh [--uninstall] [--prefix-root DIR]
#
# Release tarballs ship a prebuilt binary. From a source checkout the binary is
# compiled first, which needs the build packages listed in HOWTOBUILD.md.
set -e

APP=conky-manager3
ROOT=""
UNINSTALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --uninstall) UNINSTALL=1 ;;
        --prefix-root) ROOT="$2"; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
    shift
done

BIN="$ROOT/usr/bin/$APP"
SHARE="$ROOT/usr/share"
DESKTOP="$SHARE/applications/$APP.desktop"
ICON="$SHARE/pixmaps/$APP.png"
METAINFO="$SHARE/metainfo/$APP.appdata.xml"
MAN="$SHARE/man/man1/$APP.1.gz"
DATA="$SHARE/$APP"

if [ "$UNINSTALL" = 1 ]; then
    rm -rf "$BIN" "$DESKTOP" "$ICON" "$METAINFO" "$MAN" "$DATA"
    rm -f "$SHARE"/locale/*/LC_MESSAGES/$APP.mo
    echo "Conky Manager 3 uninstalled."
    exit 0
fi

if [ -z "$ROOT" ] && [ "$(id -u)" != 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

SRC="$(cd "$(dirname "$0")" && pwd)"

if [ ! -x "$SRC/src/$APP" ]; then
    command -v valac >/dev/null || {
        echo "No prebuilt binary and valac is not installed; see HOWTOBUILD.md." >&2
        exit 1
    }
    echo "Building $APP..."
    make -C "$SRC/src" all >/dev/null
fi

install -D -m 755 "$SRC/src/$APP" "$BIN"
install -D -m 644 "$SRC/src/$APP.desktop" "$DESKTOP"
install -D -m 644 "$SRC/src/share/pixmaps/$APP.png" "$ICON"
install -D -m 644 "$SRC/src/$APP.appdata.xml" "$METAINFO"
install -d "$(dirname "$MAN")"
gzip -9n -c "$SRC/man/$APP.1" > "$MAN"
chmod 644 "$MAN"

rm -rf "$DATA"
install -d "$DATA"
cp -r "$SRC/src/share/$APP/images" "$SRC/src/share/$APP/themepacks" "$DATA/"
find "$DATA" -type d -exec chmod 755 {} +
find "$DATA" -type f -exec chmod 644 {} +

# Translations: release tarballs ship compiled .mo files; otherwise compile them if gettext is present.
for po in "$SRC"/po/*.po; do
    lang=$(basename "$po" .po)
    mo="$SRC/locale/$lang/LC_MESSAGES/$APP.mo"
    dest="$SHARE/locale/$lang/LC_MESSAGES/$APP.mo"
    if [ -f "$mo" ]; then
        install -D -m 644 "$mo" "$dest"
    elif command -v msgfmt >/dev/null; then
        install -d "$(dirname "$dest")"
        msgfmt -o "$dest" "$po"
        chmod 644 "$dest"
    fi
done

if [ -z "$ROOT" ]; then
    command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
    echo "Conky Manager 3 installed. Launch it from the menu (Accessories > Conky Manager 3) or run: $APP"
fi
