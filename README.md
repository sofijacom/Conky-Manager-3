# Conky Manager 3

A GTK tool for managing [Conky](https://github.com/brndnmtthws/conky) widgets and themes: browse, start/stop, preview and edit them, with support for both classic and Lua-based (conky 1.10+) configs.

This is a fork of [conky-manager2](https://github.com/zcot/conky-manager2) by Scott Caudle, itself a fork of the original Conky Manager by teejee2008 (Tony George). See [version-history](./version-history) for what changed.

## Install

Download the files from the [latest release](https://github.com/thuutien/Conky-Manager-3/releases/latest):

- Debian / Ubuntu / Linux Mint / Pop!_OS: `sudo apt install ./conky-manager3_3.0.0_amd64.deb`
- Any distro: `tar xzf conky-manager3-3.0.0-x86_64.tar.gz && cd conky-manager3-3.0.0 && sudo ./install.sh`
- One-liner: `curl -fsSL https://raw.githubusercontent.com/thuutien/Conky-Manager-3/main/packaging/quick-install.sh | sudo bash`

Prebuilt binaries need x86_64 and glibc 2.34 or newer (Ubuntu 22.04, Mint 21, Debian 12 and later). Conky Manager 3 installs alongside your conky configs in `~/.conky` and replaces the `conky-manager2` package if you have it; your conky-manager2 settings are carried over on first run.

Uninstall with `sudo apt remove conky-manager3`, or `sudo ./install.sh --uninstall` from the extracted tarball.

## Build from source

See [HOWTOBUILD.md](./HOWTOBUILD.md), then run `sudo ./install.sh` from the source tree. Release files are built with `packaging/build-deb.sh` and `packaging/build-tarball.sh`.
