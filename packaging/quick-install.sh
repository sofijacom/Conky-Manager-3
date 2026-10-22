#!/bin/sh
# Conky Manager 3 one-liner installer.
#
#   curl -fsSL https://raw.githubusercontent.com/thuutien/Conky-Manager-3/main/packaging/quick-install.sh | sudo bash
#
# Pick a version, skip dependency installation, or uninstall:
#
#   curl -fsSL .../quick-install.sh | sudo bash -s -- 3.0.0
#   curl -fsSL .../quick-install.sh | sudo bash -s -- --no-deps
#   curl -fsSL .../quick-install.sh | sudo bash -s -- --uninstall
#
# Environment overrides: CONKY_MANAGER3_REPO (default thuutien/Conky-Manager-3),
# CONKY_MANAGER3_VERSION (default latest).
set -eu

REPO="${CONKY_MANAGER3_REPO:-thuutien/Conky-Manager-3}"
VERSION="${CONKY_MANAGER3_VERSION:-latest}"
INSTALL_DEPS=1
UNINSTALL=0

for arg in "$@"; do
    case "$arg" in
        --no-deps) INSTALL_DEPS=0 ;;
        --deps) INSTALL_DEPS=1 ;;
        --uninstall) UNINSTALL=1 ;;
        -h|--help)
            echo "Usage: quick-install.sh [version] [--no-deps] [--uninstall]"
            exit 0 ;;
        *) VERSION="$arg" ;;
    esac
done

if [ "$(id -u)" != 0 ]; then
    echo "Please run as root (pipe into 'sudo bash')." >&2
    exit 1
fi
command -v curl >/dev/null || { echo "curl is required." >&2; exit 1; }

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "Prebuilt binaries are x86_64 only. On $ARCH, build from source:" >&2
    echo "https://github.com/$REPO/blob/main/HOWTOBUILD.md" >&2
    exit 1
fi

if [ "$VERSION" = "latest" ]; then
    TAG=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
    VERSION="${TAG#v}"
    [ -n "$VERSION" ] || { echo "Could not determine the latest release." >&2; exit 1; }
fi

apt_install_one_of() {
    for pkg in "$@"; do
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" && return 0
    done
    return 1
}

install_deps() {
    if command -v apt-get >/dev/null; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y libgee-0.8-2 libjson-glib-1.0-0 rsync psmisc imagemagick
        # Debian 13 / Ubuntu 24.04 renamed these for the 64-bit time_t transition.
        apt_install_one_of libgtk-3-0t64 libgtk-3-0
        apt_install_one_of conky-all conky
        apt_install_one_of p7zip-full 7zip
    elif command -v dnf >/dev/null; then
        dnf install -y gtk3 libgee json-glib conky rsync psmisc p7zip p7zip-plugins ImageMagick
    elif command -v pacman >/dev/null; then
        pacman -Sy --needed --noconfirm gtk3 libgee json-glib conky rsync psmisc p7zip imagemagick
    elif command -v zypper >/dev/null; then
        zypper install -y libgtk-3-0 libgee-0_8-2 libjson-glib-1_0-0 conky rsync psmisc p7zip ImageMagick
    else
        echo "No supported package manager found; install dependencies manually" >&2
        echo "(GTK 3, libgee 0.8, json-glib, conky, rsync, psmisc, p7zip and ImageMagick)." >&2
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
cd "$TMP"
echo "Downloading Conky Manager 3 $VERSION..."
curl -fsSL -o conky-manager3.tar.gz \
    "https://github.com/$REPO/releases/download/v$VERSION/conky-manager3-$VERSION-$ARCH.tar.gz"
tar xzf conky-manager3.tar.gz
cd "conky-manager3-$VERSION"

if [ "$UNINSTALL" = 1 ]; then
    sh install.sh --uninstall
    exit 0
fi
[ "$INSTALL_DEPS" = 1 ] && install_deps
sh install.sh
echo "Conky Manager 3 $VERSION installed. Run it with: conky-manager3"
