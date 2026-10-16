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
export DISTRO DRY_RUN OXWM_LOG_DIR FORCE_AUTOLOGIN NO_AUTOLOGIN OXWM_DM OXWM_GETTY_DROPIN OXWM_XSESSION_DIR OXWM_PIPE_GRACE TARGET_HOME NO_UPDATE LATEST UNINSTALL

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
code=0; bash install.sh --force-autologin --no-autologin >/dev/null 2>&1 || code=$?
[[ "$code" -eq 2 ]] && ok "flag autologin bertentangan exit 2" || ng "flag autologin bertentangan exit $code"
bash install.sh --help 2>/dev/null | grep -q "force-autologin" \
    && ok "--help dokumentasikan autologin" || ng "--help dokumentasikan autologin"

# 9. Deteksi display manager (murni, tanpa sentuh sistem).
units_enabled="$(printf 'sddm.service enabled\nlightdm.service disabled\n')"
[[ "$(dm_from_units "$units_enabled")" == "sddm" ]] \
    && ok "dm_from_units dahulukan yang enabled" || ng "dm_from_units dahulukan yang enabled"
units_installed="$(printf 'lightdm.service disabled\nsddm.service disabled\n')"
[[ "$(dm_from_units "$units_installed")" == "lightdm" ]] \
    && ok "dm_from_units fallback terpasang" || ng "dm_from_units fallback terpasang"
[[ -z "$(dm_from_units "")" ]] \
    && ok "dm_from_units kosong bila tak ada DM" || ng "dm_from_units kosong bila tak ada DM"
units_tab="$(printf 'gdm.service\tenabled\n')"
[[ "$(dm_from_units "$units_tab")" == "gdm" ]] \
    && ok "dm_from_units tahan tab" || ng "dm_from_units tahan tab"

ln -s /usr/lib/systemd/system/sddm.service "$T/dm-sddm.service"
[[ "$(dm_from_symlink "$T/dm-sddm.service")" == "sddm" ]] \
    && ok "dm_from_symlink baca sddm" || ng "dm_from_symlink baca sddm"
ln -s /usr/lib/systemd/system/cosmic-greeter.service "$T/dm-unknown.service"
[[ "$(dm_from_symlink "$T/dm-unknown.service")" == "cosmic-greeter" ]] \
    && ok "dm_from_symlink akui DM tak dikenal" || ng "dm_from_symlink akui DM tak dikenal"
echo "bukan symlink" > "$T/bukan-symlink"
[[ -z "$(dm_from_symlink "$T/bukan-symlink")" ]] \
    && ok "dm_from_symlink abaikan file biasa" || ng "dm_from_symlink abaikan file biasa"

[[ "$(OXWM_DM=sddm detect_dm)" == "sddm" ]] \
    && ok "detect_dm hormati OXWM_DM" || ng "detect_dm hormati OXWM_DM"
[[ -z "$(OXWM_DM='' detect_dm)" ]] \
    && ok "detect_dm paksa kosong via OXWM_DM" || ng "detect_dm paksa kosong via OXWM_DM"

# 10. Blok startx .bash_profile (idempoten + bisa dihapus saat pindah ke DM).
prof="$T/bash_profile"
rm -f "$prof"
ensure_startx_block "$prof"
ensure_startx_block "$prof"
[[ "$(grep -c "oxwm-installer: startx otomatis" "$prof")" -eq 1 ]] \
    && ok "startx idempoten" || ng "startx idempoten"
grep -q "exec startx" "$prof" && ok "startx ada exec" || ng "startx ada exec"
remove_startx_block "$prof"
! grep -q "oxwm-installer" "$prof" 2>/dev/null \
    && ok "startx terhapus (mode DM)" || ng "startx terhapus (mode DM)"
remove_startx_block "$prof" && ok "hapus startx 2x aman" || ng "hapus startx 2x aman"

# 11. Drop-in autologin berpenanda (hanya hapus buatan sendiri).
export OXWM_GETTY_DROPIN="$T/autologin.conf"
rm -f "$T/autologin.conf"
setup_autologin "itah"
grep -q "oxwm-installer" "$T/autologin.conf" && grep -q "autologin itah" "$T/autologin.conf" \
    && ok "setup_autologin tulis penanda" || ng "setup_autologin tulis penanda"
remove_autologin
[[ ! -f "$T/autologin.conf" ]] \
    && ok "remove_autologin hapus buatan sendiri" || ng "remove_autologin hapus buatan sendiri"
echo "[Service]" > "$T/autologin.conf"
remove_autologin
[[ -f "$T/autologin.conf" ]] \
    && ok "remove_autologin tak sentuh config user" || ng "remove_autologin tak sentuh config user"
unset OXWM_GETTY_DROPIN

# 12. Entri sesi xsessions (bisa dipilih di DM mana pun).
export OXWM_XSESSION_DIR="$T/xsessions"
install_xsession_entry
grep -q "TryExec=/usr/local/bin/oxwm" "$T/xsessions/oxwm.desktop" \
    && ok "xsessions ada TryExec" || ng "xsessions ada TryExec"
[[ "$(stat -c %a "$T/xsessions/oxwm.desktop")" == "644" ]] \
    && ok "xsessions mode 644" || ng "xsessions mode 644"
unset OXWM_XSESSION_DIR

# 13. enable_services --dry-run tunjukkan keputusan DM vs autologin (read-only,
# tanpa butuh root/distro — langsung panggil fungsi, bukan main penuh).
DRY_RUN=1
OXWM_DM=sddm enable_services 2>/dev/null | grep -qi "sddm" \
    && ok "dry-run sebut DM" || ng "dry-run sebut DM"
OXWM_DM='' enable_services 2>/dev/null | grep -qi "autologin tty1" \
    && ok "dry-run sebut autologin bila tak ada DM" || ng "dry-run sebut autologin bila tak ada DM"
NO_AUTOLOGIN=1 OXWM_DM='' enable_services 2>/dev/null | grep -qi "no-autologin" \
    && ok "dry-run sebut no-autologin" || ng "dry-run sebut no-autologin"
DRY_RUN=0; unset OXWM_DM; NO_AUTOLOGIN=0

# 14. packages/*.txt sinkron dengan PKGMAP (anti-drift).
miss=0
for d in arch debian fedora; do
    DISTRO="$d"
    while IFS= read -r k; do
        name="$(pkg_for "$k")"
        [[ -z "$name" ]] && continue
        grep -qF -- "$name" "packages/${d}-oxwm.txt" || { echo "  hilang: $d/$k ($name)"; miss=$((miss + 1)); }
    done < <(printf '%s\n' "${!PKGMAP[@]}" | sort)
done
[[ "$miss" -eq 0 ]] && ok "paket txt sinkron PKGMAP" || ng "$miss paket hilang dari txt"

# 15. check_arch() + pin default OXWM.
check_arch x86_64 && ok "arch x86_64 diterima" || ng "arch x86_64 diterima"
if (check_arch aarch64 >/dev/null 2>&1); then ng "arch asing ditolak"; else ok "arch asing ditolak"; fi
[[ "$OXWM_PIN" =~ ^[0-9a-f]{40}$ ]] \
    && ok "OXWM_PIN default pin valid" || ng "OXWM_PIN default pin valid (dapat '${OXWM_PIN:-kosong}')"

# 16. Masa tenggang mode pipe (bypass via --yes).
OXWM_PIPE_GRACE=0 pipe_grace && ok "pipe_grace 0 instan" || ng "pipe_grace 0 instan"
if printf '' | (ASSUME_YES=0 DRY_RUN=0 DISTRO=uji THEME=tokyonight OXWM_PIPE_GRACE=0 confirm >/dev/null 2>&1); then
    ok "confirm pipe lanjut setelah tenggang"
else
    ng "confirm pipe lanjut setelah tenggang"
fi
(ASSUME_YES=1 DRY_RUN=0 DISTRO=uji THEME=tokyonight confirm >/dev/null 2>&1) \
    && ok "confirm --yes tetap instan" || ng "confirm --yes tetap instan"

# 17. --version + --no-update.
code=0; out="$(bash install.sh --version 2>/dev/null)" || code=$?
[[ "$code" -eq 0 && "$out" == "oxwm-installer "* ]] \
    && ok "--version ($out)" || ng "--version (code $code)"
NO_UPDATE=1 system_update >/dev/null 2>&1
grep -q -- "--no-update" "$LOG_FILE" \
    && ok "--no-update lewati upgrade" || ng "--no-update lewati upgrade"
NO_UPDATE=0

# 18. check_st_theme(): lolos bila sed benar, gagal keras bila meleset.
cat > "$T/st-good.h" <<'EOF'
static const char *colorname[] = {
	"#15161e",
	"#f7768e",
};
static char *font = "JetBrainsMono Nerd Font:style=Regular:size=10:antialias=true:autohint=true";
EOF
cp "$T/st-good.h" "$T/st-bad.h"
sed -i 's|^\};$|\t"red3",\n};|' "$T/st-bad.h"
check_st_theme "$T/st-good.h" uji "#15161e" "#f7768e" \
    && ok "st theme valid lolos" || ng "st theme valid lolos"
if (check_st_theme "$T/st-bad.h" uji "#15161e" "#f7768e" >/dev/null 2>&1); then
    ng "st theme rusak ditolak"
else
    ok "st theme rusak ditolak"
fi

# 19. do_uninstall(): bersih-bersih tanpa sentuh config user.
TARGET_HOME="$T/fakehome"; mkdir -p "$TARGET_HOME"
ensure_startx_block "$TARGET_HOME/.bash_profile"
export OXWM_XSESSION_DIR="$T/us-xsess" OXWM_GETTY_DROPIN="$T/us-autologin.conf"
install_xsession_entry
setup_autologin "itah" >/dev/null 2>&1
do_uninstall >/dev/null 2>&1
[[ ! -f "$T/us-xsess/oxwm.desktop" ]] \
    && ok "uninstall hapus xsessions" || ng "uninstall hapus xsessions"
[[ ! -f "$T/us-autologin.conf" ]] \
    && ok "uninstall hapus autologin" || ng "uninstall hapus autologin"
! grep -q "oxwm-installer" "$TARGET_HOME/.bash_profile" \
    && ok "uninstall hapus startx" || ng "uninstall hapus startx"
unset OXWM_XSESSION_DIR OXWM_GETTY_DROPIN TARGET_HOME

# 20. Pin upstream (#3): format versi + sha256 valid.
[[ "$ZIG_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    && ok "pin zig versi ($ZIG_VERSION)" || ng "pin zig versi ($ZIG_VERSION)"
[[ "$FASTFETCH_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    && ok "pin fastfetch versi ($FASTFETCH_VERSION)" || ng "pin fastfetch versi ($FASTFETCH_VERSION)"
[[ "$NERDFONT_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    && ok "pin nerdfont versi ($NERDFONT_VERSION)" || ng "pin nerdfont versi ($NERDFONT_VERSION)"
sums_ok=1
for sum in "$ZIG_SHA256" "$FASTFETCH_SHA256" "$NERDFONT_SHA256"; do
    [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || sums_ok=0
done
[[ "$sums_ok" -eq 1 ]] && ok "pin sha256 64-heksa" || ng "pin sha256 64-heksa"

# 21. Binary-first oxwm: tabel kosong -> fallback source (return 1, tanpa sentuh sistem).
if (DISTRO=arch install_oxwm_binary >/dev/null 2>&1); then
    ng "binary kosong fallback source"
else
    ok "binary kosong fallback source"
fi

if [[ "$fail" -eq 0 ]]; then echo "SEMUA UJI LOLOS"; else echo "ADA UJI GAGAL"; fi
exit "$fail"
