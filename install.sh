#!/usr/bin/env bash
#
# oxwm-installer — instalasi otomatis window manager OXWM, distro-agnostic.
# Didukung: Arch Linux (pacman), Debian/Ubuntu (apt), Fedora (dnf).
# Cara pakai: sudo ./install.sh [--dry-run] [--yes] [--help]
#
# Alur: cek root -> deteksi distro -> konfirmasi -> update sistem ->
#       instal paket (nama dipetakan per distro) -> pastikan toolchain zig ->
#       bangun & pasang OXWM dari source -> pasang file sesi display manager ->
#       deploy dotfiles -> aktifkan display manager -> catat riwayat -> selesai.
#
set -euo pipefail

LOG_FILE="install.log"
DB_FILE="install_history.db"
DRY_RUN=0
ASSUME_YES=0
WM="oxwm"
DISTRO=""
ZIG_VERSION="0.13.0"          # dipakai bila distro tidak menyediakan paket zig
OXWM_REPO="https://github.com/tonybanters/oxwm"

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

Distro didukung: Arch Linux, Debian/Ubuntu, Fedora (terdeteksi otomatis).

  --dry-run   simulasi saja: tampilkan rencana tanpa mengubah sistem
              (tidak butuh sudo)
  --yes       lewati konfirmasi (untuk otomatisasi)
  --help      tampilkan bantuan ini

Contoh:
  ./install.sh --dry-run   # lihat rencana dulu (aman)
  sudo ./install.sh        # instalasi penuh
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

# --- Pemetaan paket per distro ---
# Format: "arch|debian|fedora" (kosong = tidak tersedia di distro itu)
declare -A PKGMAP=(
    [xserver]="xorg-server|xorg|xorg-x11-server-Xorg"
    [xinit]="xorg-xinit|xinit|xinit"
    [xsetroot]="xorg-xsetroot|x11-xserver-utils|xorg-x11-server-utils"
    [zigbuild]="zig||zig"
    # Kolom Debian dikosongkan: Debian/Ubuntu tanpa paket zig resmi,
    # ensure_zig() akan mengunduh tarball resmi bila binari zig belum ada.
    [x11]="libx11|libx11-dev|libX11-devel"
    [xft]="libxft|libxft-dev|libXft-devel"
    [freetype]="freetype2|libfreetype6-dev|freetype-devel"
    [fontconfig]="fontconfig|libfontconfig1-dev|fontconfig-devel"
    [xinerama]="libxinerama|libxinerama-dev|libXinerama-devel"
    [term]="alacritty|alacritty|alacritty"
    [launcher]="rofi|rofi|rofi"
    [compositor]="picom|picom|picom"
    [wallpaper]="feh|feh|feh"
    [shot]="scrot|scrot|scrot"
    [fontmono]="ttf-jetbrains-mono|fonts-jetbrains-mono|jetbrains-mono-fonts"
    [fonticon]="ttf-font-awesome|fonts-font-awesome|fontawesome-fonts"
    [netapplet]="network-manager-applet|network-manager-gnome|NetworkManager-applet"
    [audio]="pavucontrol|pavucontrol|pavucontrol"
    [dm]="lightdm|lightdm|lightdm"
    [dmgreet]="lightdm-gtk-greeter|lightdm-gtk-greeter|lightdm-gtk"
    [sqlite]="sqlite3|sqlite3|sqlite"
    [git]="git|git|git"
    [curl]="curl|curl|curl"
    [vcsbuild]="base-devel|build-essential|@development-tools"
)

pkg_for() { # $1=kunci -> nama paket distro aktif (kolom 1/2/3)
    local idx=1
    [[ "$DISTRO" == "debian" ]] && idx=2
    [[ "$DISTRO" == "fedora" ]] && idx=3
    echo "${PKGMAP[$1]}" | cut -d'|' -f"$idx"
}

detect_distro() {
    if [[ -f /etc/arch-release ]] || command -v pacman >/dev/null; then
        DISTRO="arch"; UPDATE=(pacman -Syu --noconfirm); INSTALL=(pacman -S --needed --noconfirm)
    elif command -v apt-get >/dev/null && [[ -f /etc/debian_version ]]; then
        DISTRO="debian"; UPDATE=(apt-get update); UPDATE2=(apt-get upgrade -y); INSTALL=(apt-get install -y)
    elif command -v apt-get >/dev/null; then
        DISTRO="debian"; UPDATE=(apt-get update); UPDATE2=(apt-get upgrade -y); INSTALL=(apt-get install -y)
    elif command -v dnf >/dev/null; then
        DISTRO="fedora"; UPDATE=(dnf upgrade -y --refresh); INSTALL=(dnf install -y)
    else
        die "distro tidak didukung (butuh pacman/apt/dnf)"
    fi
    log "distro: $DISTRO"
}

confirm() {
    if [[ "$DRY_RUN" -eq 1 || "$ASSUME_YES" -eq 1 ]]; then
        log "konfirmasi dilewati (dry-run/--yes)"
        return 0
    fi
    echo "Ringkasan: instal OXWM (build dari source) + aplikasi pendukung + dotfiles standar di $DISTRO."
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
    log_db "update" "mulai" "${UPDATE[*]}"
    run_or_dry "${UPDATE[@]}"
    if [[ -n "${UPDATE2[*]:-}" ]]; then
        run_or_dry "${UPDATE2[@]}"
    fi
    log_db "update" "ok" "sistem mutakhir"
}

install_packages() {
    local keys=(git curl vcsbuild xserver xinit xsetroot zigbuild x11 xft freetype fontconfig xinerama
                term launcher compositor wallpaper shot fontmono fonticon netapplet audio dm dmgreet sqlite)
    local pkgs=()
    local k name
    for k in "${keys[@]}"; do
        name="$(pkg_for "$k")"
        [[ -z "$name" ]] && { log "lewati '$k' (tidak tersedia di $DISTRO, ditangani modul khusus)"; continue; }
        pkgs+=("$name")
    done
    log "instal ${#pkgs[@]} paket: ${pkgs[*]}"
    log_db "paket" "mulai" "${pkgs[*]}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati instalasi paket"
    else
        "${INSTALL[@]}" "${pkgs[@]}"
    fi
    log_db "paket" "ok" "selesai"
}

ensure_zig() { # pastikan compiler zig ada; unduh tarball resmi bila tak tersedia
    if command -v zig >/dev/null; then
        log "zig sudah ada: $(zig version)"
        return 0
    fi
    log "binari zig belum ada -> unduh tarball resmi zig $ZIG_VERSION"
    log_db "zig" "mulai" "tarball $ZIG_VERSION"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "(dry-run) lewati unduhan zig"
        else
            curl -fL "https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz" \
                -o /tmp/zig.tar.xz
            rm -rf /opt/zig && mkdir -p /opt/zig
            tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1
            ln -sf /opt/zig/zig /usr/local/bin/zig
            rm -f /tmp/zig.tar.xz
        fi
        log_db "zig" "ok" "tarball terpasang"
}

install_oxwm() { # bangun dari source: seragam di semua distro
    local build_dir="/tmp/oxwm-build"
    log "bangun & pasang OXWM dari source ($OXWM_REPO)..."
    log_db "oxwm" "mulai" "zig build dari source"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati clone + build oxwm"
    else
        rm -rf "$build_dir"
        if [[ -n "${SUDO_USER:-}" ]]; then
            su "$SUDO_USER" -c "git clone --depth 1 $OXWM_REPO $build_dir"
            (cd "$build_dir" && zig build -Doptimize=ReleaseSmall)
        else
            git clone --depth 1 "$OXWM_REPO" "$build_dir"
            (cd "$build_dir" && zig build -Doptimize=ReleaseSmall)
        fi
        install -m 0755 "$build_dir/zig-out/bin/oxwm" /usr/local/bin/oxwm
        rm -rf "$build_dir"
    fi
    # file sesi agar OXWM muncul di display manager
    local session="usr/share/xsessions/oxwm.desktop"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) tulis /$session"
    else
        printf '[Desktop Entry]\nName=OXWM\nComment=Dynamic window manager\nExec=/usr/local/bin/oxwm\nType=XSession\n' > "/$session"
    fi
    log_db "oxwm" "ok" "terpasang di /usr/local/bin/oxwm"
}

deploy_dotfiles() { # salin config standar bila pengguna belum punya
    local src_dir
    src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/dotfiles"
    local dest_home="${TARGET_HOME:-$HOME}"
    local owner="${SUDO_USER:-$(whoami)}"
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
    chown -R "$owner:$owner" "$dest_home/.config/oxwm" "$dest_home/.xinitrc" 2>/dev/null || true
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
    log "selesai. reboot, pilih sesi OXWM di layar login (atau 'startx' bila tanpa display manager)."
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
    log_db "mulai" "ok" "instalasi OXWM dimulai (distro=$DISTRO dry-run=$DRY_RUN)"
    confirm
    system_update
    install_packages
    ensure_zig
    install_oxwm
    deploy_dotfiles
    enable_services
    finish
}

main "$@"
