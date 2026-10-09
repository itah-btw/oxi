#!/usr/bin/env bash
#
# oxwm-installer — instalasi otomatis window manager OXWM di Arch Linux.
# Cara pakai: sudo ./install.sh [--dry-run] [--yes] [--help]
#
# Alur: cek root -> deteksi Arch -> konfirmasi -> update sistem ->
#       instal paket resmi -> instal yay (bila perlu) -> instal oxwm-git (AUR) ->
#       deploy dotfiles -> aktifkan display manager -> catat riwayat -> selesai.
#
set -euo pipefail

LOG_FILE="install.log"
DB_FILE="install_history.db"
DRY_RUN=0
ASSUME_YES=0
WM="oxwm"
DISTRO=""

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; log_db "fatal" "gagal" "$*"; exit 1; }

# --- Riwayat instalasi (SQLite, fallback ke berkas bila sqlite3 tak ada) ---
db_init() {
    command -v sqlite3 >/dev/null || { log "sqlite3 tidak ada, riwayat hanya ke berkas log"; return 1; }
    sqlite3 "$DB_FILE" "CREATE TABLE IF NOT EXISTS instalasi(id INTEGER PRIMARY KEY AUTOINCREMENT, waktu_mulai TEXT, distro TEXT, wm TEXT, status TEXT);
        CREATE TABLE IF NOT EXISTS log_tahap(id INTEGER PRIMARY KEY AUTOINCREMENT, id_instalasi INTEGER, waktu TEXT, tahap TEXT, status TEXT, pesan TEXT);"
    RUN_ID=$(sqlite3 "$DB_FILE" "INSERT INTO instalasi(waktu_mulai, distro, wm, status) VALUES(datetime('now'),'${DISTRO:-?}','${WM}','berjalan'); SELECT last_insert_rowid();")
    log "riwayat sesi #$RUN_ID dibuka di $DB_FILE"
}

log_db() { # $1=tahap $2=status $3=pesan
    [[ -n "${RUN_ID:-}" ]] || return 0
    sqlite3 "$DB_FILE" "INSERT INTO log_tahap(id_instalasi, waktu, tahap, status, pesan) VALUES($RUN_ID, datetime('now'), '$1', '$2', '$3');" 2>/dev/null || true
}

usage() {
    cat <<'EOF'
Pakai: sudo ./install.sh [OPSI]

  --dry-run   simulasi saja: tampilkan rencana tanpa mengubah sistem
              (tidak butuh sudo)
  --yes       lewati konfirmasi (untuk otomatisasi)
  --help      tampilkan bantuan ini

Contoh:
  sudo ./install.sh --dry-run   # lihat rencana dulu
  sudo ./install.sh              # instalasi penuh
EOF
}

check_root() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati cek root"
        return 0
    fi
    [[ "$EUID" -eq 0 ]] || die "jalankan dengan sudo: sudo ./install.sh"
    [[ -n "${SUDO_USER:-}" ]] || die "jalankan via sudo dari user biasa (bukan langsung sebagai root)"
    TARGET_HOME="$(eval echo "~$SUDO_USER")"
    log "user target: $SUDO_USER ($TARGET_HOME)"
}

detect_distro() {
    if [[ -f /etc/arch-release ]] || command -v pacman >/dev/null; then
        DISTRO="arch"; PKG="pacman -S --needed --noconfirm"
    else
        die "script ini khusus Arch Linux (pacman tidak ditemukan)"
    fi
    log "distro: $DISTRO | installer paket: $PKG"
}

confirm() {
    if [[ "$DRY_RUN" -eq 1 || "$ASSUME_YES" -eq 1 ]]; then
        log "konfirmasi dilewati (dry-run/--yes)"
        return 0
    fi
    echo "Ringkasan: instal OXWM + aplikasi pendukung + dotfiles standar di Arch Linux."
    read -rp "Lanjut? [y/N] " jawab
    [[ "$jawab" == "y" || "$jawab" == "Y" ]] || { log_db "konfirmasi" "dibatalkan" "pengguna menjawab tidak"; die "dibatalkan pengguna"; }
    log_db "konfirmasi" "ok" "pengguna menyetujui"
}

run_or_dry() { # "$@" = perintah; dry-run hanya mencetak
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) $*"
    else
        log "jalankan: $*"
        "$@"
    fi
}

system_update() {
    log "update sistem..."
    log_db "update" "mulai" "pacman -Syu"
    run_or_dry pacman -Syu --noconfirm
    log_db "update" "ok" "sistem mutakhir"
}

install_packages() {
    local pkgs=(
        base-devel git
        xorg-server xorg-xinit xorg-xsetroot
        zig libx11 libxft freetype2 fontconfig libxinerama
        alacritty rofi picom feh scrot
        ttf-jetbrains-mono ttf-font-awesome
        network-manager-applet pavucontrol
        lightdm lightdm-gtk-greeter
        sqlite3
    )
    log "instal ${#pkgs[@]} paket resmi: ${pkgs[*]}"
    log_db "paket-resmi" "mulai" "${pkgs[*]}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati instalasi paket"
    else
        # shellcheck disable=SC2086
        pacman -S --needed --noconfirm "${pkgs[@]}"
    fi
    log_db "paket-resmi" "ok" "selesai"
}

install_yay() { # AUR helper, dibangun sebagai user biasa (makepkg dilarang via root)
    command -v yay >/dev/null && { log "yay sudah ada, lewati"; return 0; }
    log "pasang yay (AUR helper)..."
    log_db "yay" "mulai" "bangun dari AUR"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati pembangunan yay"
    else
        su "$SUDO_USER" -c "git clone https://aur.archlinux.org/yay.git /tmp/yay-build" 2>/dev/null || true
        su "$SUDO_USER" -c "cd /tmp/yay-build && makepkg -si --noconfirm"
        rm -rf /tmp/yay-build
    fi
    log_db "yay" "ok" "selesai"
}

install_oxwm() { # dari AUR: oxwm-git (+ file sesi display manager otomatis)
    log "pasang oxwm-git dari AUR..."
    log_db "oxwm" "mulai" "yay -S oxwm-git"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati pemasangan oxwm-git"
    else
        su "$SUDO_USER" -c "yay -S --needed --noconfirm oxwm-git"
    fi
    log_db "oxwm" "ok" "selesai"
}

deploy_dotfiles() { # salin config standar bila pengguna belum punya
    local src_dir
    src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dotfiles"
    local dest_home="${TARGET_HOME:-$HOME}"
    log "deploy dotfiles $src_dir -> $dest_home"
    log_db "dotfiles" "mulai" "$src_dir"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati penyalinan dotfiles"
        return 0
    fi
    local backup="$dest_home/.config-backup-$(date +%F)"
    [[ -d "$dest_home/.config" ]] && { mkdir -p "$backup"; cp -r "$dest_home/.config" "$backup/"; log "backup config lama -> $backup"; }
    mkdir -p "$dest_home/.config/oxwm"
    [[ -f "$dest_home/.config/oxwm/config.lua" ]] || cp "$src_dir/oxwm/config.lua" "$dest_home/.config/oxwm/config.lua"
    [[ -f "$dest_home/.xinitrc" ]] || cp "$src_dir/xinitrc" "$dest_home/.xinitrc"
    chown -R "$SUDO_USER:$SUDO_USER" "$dest_home/.config/oxwm" "$dest_home/.xinitrc"
    log_db "dotfiles" "ok" "backup: $backup"
}

enable_services() {
    log "aktifkan display manager (lightdm)..."
    log_db "layanan" "mulai" "systemctl enable lightdm"
    run_or_dry systemctl enable lightdm
    log_db "layanan" "ok" "lightdm aktif saat boot"
}

finish() {
    if [[ "$DRY_RUN" -eq 0 && -n "${RUN_ID:-}" ]]; then
        sqlite3 "$DB_FILE" "UPDATE instalasi SET status='selesai' WHERE id=$RUN_ID;" 2>/dev/null || true
    fi
    log "selesai. reboot, pilih sesi OXWM di layar login (atau jalankan 'startx' bila tanpa display manager)."
}

main() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run) DRY_RUN=1 ;;
            --yes) ASSUME_YES=1 ;;
            --help) usage; exit 0 ;;
            *) echo "opsi tidak dikenal: $arg (lihat --help)"; exit 2 ;;
        esac
    done
    check_root
    detect_distro
    db_init || true
    log_db "mulai" "ok" "instalasi OXWM dimulai (dry-run=$DRY_RUN)"
    confirm
    system_update
    install_packages
    install_yay
    install_oxwm
    deploy_dotfiles
    enable_services
    finish
}

main "$@"
