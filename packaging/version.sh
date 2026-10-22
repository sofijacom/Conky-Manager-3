# Sourced by the build scripts: sets SRC and VERSION from src/Main.vala.
SRC="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(sed -n 's/^public const string AppVersion = "\(.*\)";/\1/p' "$SRC/src/Main.vala")
[ -n "$VERSION" ] || { echo "Could not read AppVersion from src/Main.vala" >&2; exit 1; }
