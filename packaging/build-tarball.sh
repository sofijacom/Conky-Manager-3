#!/bin/sh
# Build an install archive with a prebuilt binary: dist/conky-manager3-<version>-<arch>.tar.gz
# Users extract it and run: sudo ./install.sh
set -e
. "$(dirname "$0")/version.sh"
ARCH=$(uname -m)
NAME="conky-manager3-$VERSION"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

make -C "$SRC/src" all >/dev/null 2>&1 || make -C "$SRC/src" all
git -C "$SRC" archive --format=tar --prefix="$NAME/" HEAD | tar -x -C "$STAGE"
install -m 755 "$SRC/src/conky-manager3" "$STAGE/$NAME/src/"
for po in "$SRC"/po/*.po; do
    lang=$(basename "$po" .po)
    install -d "$STAGE/$NAME/locale/$lang/LC_MESSAGES"
    msgfmt -o "$STAGE/$NAME/locale/$lang/LC_MESSAGES/conky-manager3.mo" "$po"
done
mkdir -p "$SRC/dist"
tar -C "$STAGE" -czf "$SRC/dist/$NAME-$ARCH.tar.gz" --owner=0 --group=0 "$NAME"
ls "$SRC/dist/$NAME-$ARCH.tar.gz"
