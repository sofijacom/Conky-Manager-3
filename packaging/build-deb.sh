#!/bin/sh
# Build a .deb package for Linux Mint / Ubuntu / Debian.
# Usage: ./packaging/build-deb.sh   ->   dist/conky-manager3_<version>_<arch>.deb
set -e
. "$(dirname "$0")/version.sh"
ARCH=$(dpkg --print-architecture)
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

make -C "$SRC/src" all >/dev/null 2>&1 || make -C "$SRC/src" all
chmod 755 "$STAGE"
sh "$SRC/install.sh" --prefix-root "$STAGE"
install -d "$STAGE/DEBIAN"
cat > "$STAGE/DEBIAN/control" <<CTRL
Package: conky-manager3
Version: $VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Depends: libc6 (>= 2.34), libgtk-3-0t64 | libgtk-3-0, libglib2.0-0t64 | libglib2.0-0, libgee-0.8-2, libjson-glib-1.0-0, conky-all | conky-std | conky, rsync, psmisc, p7zip-full | 7zip, imagemagick
Conflicts: conky-manager2
Replaces: conky-manager2
Maintainer: Conky Manager 3 <conky-manager3@localhost>
Homepage: https://github.com/thuutien/Conky-Manager-3
Description: Utility for managing Conky widgets and themes
 Conky Manager 3 is a GTK front-end for Conky, the light-weight system
 monitor for X. It starts, stops, browses, previews and edits Conky widgets
 and themes, and supports both classic and Lua-based (1.10+) configs.
 It is a fork of conky-manager2 by Tony George and Scott Caudle.
CTRL
cat > "$STAGE/DEBIAN/postinst" <<'POST'
#!/bin/sh
set -e
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true
POST
chmod 755 "$STAGE/DEBIAN/postinst"
mkdir -p "$SRC/dist"
dpkg-deb --root-owner-group --build "$STAGE" "$SRC/dist/conky-manager3_${VERSION}_${ARCH}.deb"
