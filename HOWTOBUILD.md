# How to build Conky Manager 3

Install the build tools (Debian/Ubuntu package names):

```bash
sudo apt install build-essential git valac libgtk-3-dev libgee-0.8-dev libjson-glib-dev gettext conky-all p7zip-full imagemagick rsync
```

Build and install:

```bash
git clone https://github.com/thuutien/Conky-Manager-3.git
cd Conky-Manager-3
make -C src
sudo ./install.sh
```

Run `src/conky-manager3` to try it without installing. Uninstall with `sudo ./install.sh --uninstall`.

Release files:

- `packaging/build-deb.sh` builds `dist/conky-manager3_<version>_<arch>.deb`
- `packaging/build-tarball.sh` builds `dist/conky-manager3-<version>-<arch>.tar.gz` with a prebuilt binary
- `packaging/build-themepacks.sh` rebuilds the bundled widget packs from `themes/`

`meson.build` is also kept up to date if you prefer Meson.
