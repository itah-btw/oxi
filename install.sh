#!/usr/bin/env bash
# Shim kompatibilitas: installer sekarang bernama `oxi` (OXWM Installer).
# Dipakai oleh perintah lama/oxu versi sebelumnya; jangan ditambah fitur di sini.
set -euo pipefail
src="${BASH_SOURCE[0]:-}"
if [[ -n "$src" && -f "$src" ]]; then
    here="$(cd "$(dirname "$src")" && pwd)"
    exec bash "$here/oxi" "$@"
fi
exec curl -fsSL --retry 3 --retry-delay 2 --proto '=https' --proto-redir '=https' \
    "https://raw.githubusercontent.com/itah-btw/oxi/main/oxi" | bash
