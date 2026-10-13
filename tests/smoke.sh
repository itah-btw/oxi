#!/usr/bin/env bash
# Uji asap oxwm-installer: sintaks + fungsi murni. Tidak menyentuh sistem,
# tidak butuh root. Jalan dari akar repo: bash tests/smoke.sh
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
ok() { echo "ok: $*"; }
ng() { echo "GAGAL: $*"; fail=1; }

# 1. Sintaks semua skrip shell.
for f in install.sh bin/* tests/smoke.sh; do
    code=0
    bash -n "$f" 2>/dev/null || code=$?
    if [[ "$code" -eq 0 ]]; then ok "sintaks $f"; else ng "sintaks $f"; fi
done

# 2. Muat fungsi tanpa menjalankan instalasi (dijaga guard BASH_SOURCE di install.sh).
# shellcheck source=../install.sh
source ./install.sh
# Diekspor agar jelas dipakai lintas-berkas oleh fungsi install.sh (sekaligus
# menenangkan SC2034: shellcheck tak melihat pemakaian antar-berkas).
export DISTRO DRY_RUN OXWM_LOG_DIR

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
LOG_FILE="$T/t.log"
DRY_RUN=1

# 3. tahap(): status "ok" saat dry-run tidak boleh mengklaim sukses.
tahap "uji" "ok" "langkah fiktif"
grep -q '(dry-run) \[uji\] dilewati: langkah fiktif' "$T/t.log" \
    && ok "tahap() jujur saat dry-run" || ng "tahap() jujur saat dry-run"
tahap "uji" "mulai" "langkah fiktif"
grep -q '\[uji\] mulai: langkah fiktif' "$T/t.log" \
    && ok "tahap() catat mulai" || ng "tahap() catat mulai"

# 4. pkg_for(): pemetaan paket per distro.
DISTRO=arch;   [[ "$(pkg_for xserver)" == "xorg-server" ]] && ok "pkg arch" || ng "pkg arch"
DISTRO=debian; [[ "$(pkg_for xserver)" == "xorg" ]] && ok "pkg debian" || ng "pkg debian"
DISTRO=fedora; [[ "$(pkg_for xserver)" == "xorg-x11-server-Xorg" ]] && ok "pkg fedora" || ng "pkg fedora"
DISTRO=debian; [[ -z "$(pkg_for fetch)" ]] && ok "fetch kosong di debian" || ng "fetch kosong di debian"
DISTRO=debian; [[ -z "$(pkg_for zigbuild)" ]] && ok "zigbuild kosong di debian" || ng "zigbuild kosong di debian"
DISTRO=arch;   [[ "$(pkg_for zigbuild)" == "zig" ]] && ok "zigbuild arch" || ng "zigbuild arch"

# 5. valid_user(): tolak nama user aneh (dipakai sebelum tulis drop-in getty).
valid_user "itah" && ok "user valid diterima" || ng "user valid diterima"
valid_user 'root; reboot' && ng "user jahat ditolak" || ok "user jahat ditolak"
valid_user "" && ng "user kosong ditolak" || ok "user kosong ditolak"

# 6. retry(): jumlah percobaan + nomor yang dilaporkan benar.
echo 0 > "$T/cnt"
flaky() { local n; n=$(cat "$T/cnt"); n=$((n + 1)); echo "$n" > "$T/cnt"; [[ "$n" -ge 3 ]]; }
out="$(retry 3 flaky)"
cnt_now=$(cat "$T/cnt")
if [[ "$cnt_now" == "3" ]] && grep -q "percobaan 1/3" <<<"$out" && grep -q "percobaan 2/3" <<<"$out"; then
    ok "retry 3x lalu sukses"
else
    ng "retry 3x lalu sukses"
fi
if retry 2 false; then
    ng "retry menyerah setelah 2x"
else
    ok "retry menyerah setelah 2x"
fi

# 7. init_log(): pakai path tetap bila bisa ditulis.
DRY_RUN=0
OXWM_LOG_DIR="$T/logs"
LOG_FILE="seharusnya-ditimpa"
init_log
if [[ "$LOG_FILE" == "$T/logs/install.log" && -f "$LOG_FILE" ]]; then
    ok "init_log path tetap"
else
    ng "init_log path tetap (dapat $LOG_FILE)"
fi

# 8. CLI: --help dan flag tak dikenal, tanpa root.
code=0; bash install.sh --help >/dev/null 2>&1 || code=$?
[[ "$code" -eq 0 ]] && ok "--help exit 0" || ng "--help exit $code"
code=0; bash install.sh --bogus >/dev/null 2>&1 || code=$?
[[ "$code" -eq 2 ]] && ok "flag tak dikenal exit 2" || ng "flag tak dikenal exit $code"

if [[ "$fail" -eq 0 ]]; then echo "SEMUA UJI LOLOS"; else echo "ADA UJI GAGAL"; fi
exit "$fail"
