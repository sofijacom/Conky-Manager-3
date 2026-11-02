#!/bin/sh
# Build an .rpm package for Fedora, openSUSE and other RPM distributions.
# Usage: ./packaging/build-rpm.sh   ->   dist/conky-manager3-<version>-1.<arch>.rpm
# Needs rpmbuild (Fedora: rpm-build, Arch: rpm-tools). Packages the prebuilt binary, like build-deb.sh.
set -e
. "$(dirname "$0")/version.sh"
ARCH=$(uname -m)
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

make -C "$SRC/src" all >/dev/null 2>&1 || make -C "$SRC/src" all
mkdir -p "$STAGE/root" "$STAGE/SPECS" "$SRC/dist"
sh "$SRC/install.sh" --prefix-root "$STAGE/root"
cat > "$STAGE/SPECS/conky-manager3.spec" <<SPEC
# The binary is prebuilt: skip the build host's stripping, debug package and other post-processing.
%global __os_install_post %{nil}
%global debug_package %{nil}

Name:           conky-manager3
Version:        $VERSION
Release:        1
Summary:        Utility for managing Conky widgets and themes
License:        GPL-2.0-or-later
URL:            https://github.com/thuutien/Conky-Manager-3
# Libraries (GTK 3, libgee, json-glib) come from rpmbuild's automatic soname requirements
Requires:       conky, curl, rsync, psmisc, (7zip or p7zip), ImageMagick
Obsoletes:      conky-manager2 < 3

%description
Conky Manager 3 is a GTK front-end for Conky, the light-weight system
monitor for X. It starts, stops, browses, previews and edits Conky widgets
and themes, and supports both classic and Lua-based (1.10+) configs.
It is a fork of conky-manager2 by Tony George and Scott Caudle.

%install
cp -a "$STAGE/root/." %{buildroot}/

%post
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true

%postun
command -v update-desktop-database >/dev/null && update-desktop-database -q /usr/share/applications || true

%files
/usr/bin/conky-manager3
/usr/share/conky-manager3
/usr/share/applications/conky-manager3.desktop
/usr/share/pixmaps/conky-manager3.png
/usr/share/metainfo/conky-manager3.appdata.xml
/usr/share/man/man1/conky-manager3.1.gz
/usr/share/locale/*/LC_MESSAGES/conky-manager3.mo
SPEC
rpmbuild --define "_topdir $STAGE" --target "$ARCH" -bb "$STAGE/SPECS/conky-manager3.spec" >/dev/null
OUT="$SRC/dist/conky-manager3-$VERSION-1.$ARCH.rpm"
cp "$STAGE/RPMS/$ARCH/conky-manager3-$VERSION-1.$ARCH.rpm" "$OUT"
echo "$OUT"
