#!/bin/sh
# Build the bundled widget packs from themes/ into src/share/conky-manager3/themepacks/.
# Conky Manager 3 installs any new pack found there into ~/.conky on startup.
# Usage: ./packaging/build-themepacks.sh
set -e
SRC="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$SRC/src/share/conky-manager3/themepacks"
SEVENZIP=$(command -v 7za || command -v 7z || command -v 7zz)
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

build() { # build <theme dir under themes/> <pack name>
    rm -rf "$STAGE/.conky"
    mkdir -p "$STAGE/.conky"
    for d in "$SRC/themes/$1"/*/; do
        cp -r "$d" "$STAGE/.conky/"
    done
    rm -f "$OUT/$2"
    (cd "$STAGE" && "$SEVENZIP" a -bd -mx=9 "$OUT/$2" .conky >/dev/null)
    echo "$OUT/$2"
}

build liquid-glass liquid-glass-1.1.cmtp.7z
build minimal minimal-1.1.cmtp.7z
