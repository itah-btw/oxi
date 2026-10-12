#!/usr/bin/env bash
#
# oxwm-installer — instalasi otomatis window manager OXWM, distro-agnostic.
# Didukung: Arch Linux (pacman), Debian/Ubuntu (apt), Fedora (dnf).
# Cara pakai: sudo ./install.sh [--dry-run] [--yes] [--theme NAMA] [--help]
#
# Alur: cek root -> deteksi distro -> konfirmasi -> update sistem ->
#       instal paket (nama dipetakan per distro) -> pastikan toolchain zig ->
#       pastikan font Nerd -> bangun & pasang OXWM dari source ->
#       pasang perintah pendamping -> deploy dotfiles (topbar, keybind, tema,
#       dmenu/dunst bertema, skrip status, khal) -> autologin getty tty1 +
#       startx otomatis -> catat riwayat -> selesai.
#
# Tanpa display manager: login konsol otomatis di tty1 lalu startx.
set -euo pipefail

LOG_FILE="install.log"
DB_FILE="install_history.db"
DRY_RUN=0
ASSUME_YES=0
THEME="tokyonight"
THEME_SET=0
WM="oxwm"
DISTRO=""
ZIG_VERSION="0.16.0"          # dipakai bila distro tidak menyediakan paket zig (oxwm butuh zig>=0.16)
OXWM_REPO="https://github.com/tonybanters/oxwm"
REPO_SLUG="itah-btw/oxwm-installer"
REF="${OXWM_REF:-main}"         # timpa untuk coba cabang lain: OXWM_REF=dev ... | bash
REPO_DIR=""                     # diisi resolve_repo_dir(); jangan diakses langsung

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; log_db "fatal" "gagal" "$*"; exit 1; }

# --- Lokasi repo (mendukung one-liner via pipe) ---
# Bila dijalankan dari pipe (curl ... | bash), BASH_SOURCE tak menunjuk ke
# file dan dotfiles/ tak tersedia lokal: unduh tarball repo ke /tmp.
resolve_repo_dir() {
    local src="${BASH_SOURCE[0]:-}"
    if [[ -n "$src" && -f "$src" ]]; then
        local here
        here="$(cd "$(dirname "$src")" && pwd)"
        if [[ -d "$here/dotfiles" && -d "$here/bin" ]]; then
            REPO_DIR="$here"
            return 0
        fi
    fi
    command -v curl >/dev/null || die "butuh curl untuk mengunduh repo (atau clone manual)"
    command -v tar >/dev/null || die "butuh tar untuk membuka arsip repo (atau clone manual)"
    local tmp
    tmp="$(mktemp -d)"
    log "unduh repo $REPO_SLUG@$REF ke $tmp..."
    curl -fsSL "https://github.com/$REPO_SLUG/archive/refs/heads/$REF.tar.gz" -o "$tmp/repo.tar.gz" \
        || die "unduhan repo gagal (cek koneksi/nama cabang)"
    tar -xzf "$tmp/repo.tar.gz" -C "$tmp" \
        || die "arsip repo rusak"
    # Tarball GitHub mengembang ke <repo>-<ref>, mis. oxwm-installer-main.
    REPO_DIR="$tmp/${REPO_SLUG##*/}-$REF"
    [[ -d "$REPO_DIR/dotfiles" && -d "$REPO_DIR/bin" ]] \
        || die "struktur repo tak dikenal di $REPO_DIR"
    log "repo siap di $REPO_DIR"
}

# Home dir user target, lewat user database (bukan tilde expansion yang
# diam-diam gagal literal bila NSS sedang glitch).
user_home() { # $1=user -> cetak $HOME-nya atau gagal
    local h
    h="$(getent passwd "$1" | cut -d: -f6)"
    [[ -n "$h" ]] || die "home untuk user '$1' tak ketemu (getent kosong)"
    printf '%s' "$h"
}

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

Satu baris (butuh curl; tanpa klon dulu):
  curl -fsSL https://cdn.jsdelivr.net/gh/itah-btw/oxwm-installer@main/install.sh | sudo bash
  curl -fsSL https://cdn.jsdelivr.net/gh/itah-btw/oxwm-installer@main/install.sh | sudo bash -s -- --theme gruvbox
  (cermin jsDelivr dari repo yang sama; URL mentah GitHub juga bisa dipakai)
  Cabang lain: OXWM_REF=dev ... | sudo bash -s -- --theme gruvbox

Distro didukung: Arch Linux, Debian/Ubuntu, Fedora (terdeteksi otomatis).

  --dry-run   simulasi saja: tampilkan rencana tanpa mengubah sistem
              (tidak butuh sudo)
  --yes       lewati konfirmasi (untuk otomatisasi)
  --theme NAMA
              tema awal: tokyonight (bawaan) | gruvbox | catppuccin.
              Menimpa ~/.config/oxwm/theme; tanpa flag ini file tema
              yang sudah ada tidak diubah.
  --help      tampilkan bantuan ini

Contoh:
  ./install.sh --dry-run   # lihat rencana dulu (aman)
  sudo ./install.sh        # instalasi penuh
  sudo ./install.sh --theme gruvbox --yes
EOF
}

check_root() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati cek root"
        return 0
    fi
    [[ "$EUID" -eq 0 ]] || die "jalankan dengan sudo: sudo ./install.sh"
    [[ -n "${SUDO_USER:-}" ]] || die "jalankan via sudo dari user biasa (bukan langsung sebagai root)"
    TARGET_HOME="$(user_home "$SUDO_USER")"
    log "user target: $SUDO_USER ($TARGET_HOME)"
}

# --- Pemetaan paket per distro ---
# Format: "arch|debian|fedora" (kosong = tidak tersedia di distro itu)
declare -A PKGMAP=(
    [xserver]="xorg-server|xorg|xorg-x11-server-Xorg"
    [xinit]="xorg-xinit|xinit|xinit"
    [xsetroot]="xorg-xsetroot|x11-xserver-utils|xsetroot"
    [zigbuild]="zig||zig"
    # Kolom Debian dikosongkan: Debian/Ubuntu tanpa paket zig resmi,
    # ensure_zig() akan mengunduh tarball resmi bila binari zig belum ada.
    [x11]="libx11|libx11-dev|libX11-devel"
    [xft]="libxft|libxft-dev|libXft-devel"
    [freetype]="freetype2|libfreetype6-dev|freetype-devel"
    [fontconfig]="fontconfig|libfontconfig1-dev|fontconfig-devel"
    [xinerama]="libxinerama|libxinerama-dev|libXinerama-devel"
    [launcher]="dmenu|dmenu|dmenu"
    [wallpaper]="feh|feh|feh"
    [shot]="maim|maim|maim"
    [shotsel]="slop|slop|slop"
    [keysim]="xdotool|xdotool|xdotool"
    [fontmono]="ttf-jetbrains-mono|fonts-jetbrains-mono|jetbrains-mono-fonts"
    [fonticon]="ttf-font-awesome|fonts-font-awesome|fontawesome-fonts"
    [notify]="dunst|dunst|dunst"
    [clipboard]="xclip|xclip|xclip"
    [libnotify]="libnotify|libnotify-bin|libnotify"
    [bright]="brightnessctl|brightnessctl|brightnessctl"
    [monitor]="btop|btop|btop"
    [fetch]="fastfetch|fastfetch|fastfetch"
    [calendar]="khal|khal|khal"
    [ocr]="tesseract|tesseract-ocr|tesseract"
    [mixer]="wireplumber|wireplumber|wireplumber"
    [powerprof]="power-profiles-daemon|power-profiles-daemon|power-profiles-daemon"
    [netcli]="networkmanager|network-manager|NetworkManager"
    [bluetooth]="bluez-utils|bluez|bluez"
    [sqlite]="sqlite3|sqlite3|sqlite"
    [git]="git|git|git"
    [curl]="curl|curl|curl"
    [unzip]="unzip|unzip|unzip"
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
    # Via pipe, stdin adalah scriptnya sendiri: read akan menelan baris
    # script. Mode pipe berarti pengguna sudah sadar mem-pipe installer ke
    # sudo bash, jadi lanjut otomatis (setara --yes).
    if [[ ! -t 0 ]]; then
        log "mode pipe tanpa TTY: lanjut otomatis"
        return 0
    fi
    echo "Ringkasan: instal OXWM (build dari source) + aplikasi pendukung + dotfiles standar (topbar, keybind, 3 tema, dmenu/dunst bertema; tema: $THEME) di $DISTRO. Tanpa display manager (autologin tty1 + startx)."
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

retry() { # $1=maksimal coba, sisanya perintah; mirror kadang tersendat
    local maks=$1; shift
    local coba=1
    until "$@"; do
        (( coba++ >= maks )) && return 1
        log "percobaan $coba/$maks gagal, ulangi setelah 5 dtk..."
        sleep 5
    done
}

system_update() {
    log "update sistem..."
    log_db "update" "mulai" "${UPDATE[*]}"
    run_or_dry retry 3 "${UPDATE[@]}"
    if [[ -n "${UPDATE2[*]:-}" ]]; then
        run_or_dry retry 3 "${UPDATE2[@]}"
    fi
    log_db "update" "ok" "sistem mutakhir"
}

install_packages() {
    local keys=(git curl unzip vcsbuild xserver xinit xsetroot zigbuild x11 xft freetype fontconfig xinerama
                launcher wallpaper shot shotsel keysim fontmono fonticon notify clipboard libnotify
                bright monitor fetch calendar ocr mixer powerprof netcli bluetooth sqlite)
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
        retry 3 "${INSTALL[@]}" "${pkgs[@]}"
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
            curl -fL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
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
    log_db "oxwm" "ok" "terpasang di /usr/local/bin/oxwm"
}

build_st() { # terminal st dari source suckless, 3 build bertema + dispatcher `st`
    # Repo distro tak konsisten menyediakan st (Arch bahkan tak punya), jadi
    # bangun seragam di semua distro. Pola sed sama dengan modul Nix
    # (config.def.h: komentar dulu baru kembaran polosnya — urutan penting).
    local build_dir="/tmp/st-build" repo="https://git.suckless.org/st"
    local theme fg bg cur c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15
    log "bangun & pasang st 3 tema dari source ($repo)..."
    log_db "st" "mulai" "make 3 tema"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati clone + build st"
        return 0
    fi
    rm -rf "$build_dir"
    if [[ -n "${SUDO_USER:-}" ]]; then
        su "$SUDO_USER" -c "git clone --depth 1 $repo $build_dir"
    else
        git clone --depth 1 "$repo" "$build_dir"
    fi
    for theme in tokyonight gruvbox catppuccin; do
        case "$theme" in
            gruvbox) fg="#ebdbb2"; bg="#282828"; cur="#ebdbb2"
                c0="#282828"; c1="#cc241d"; c2="#98971a"; c3="#d79921"
                c4="#458588"; c5="#b16286"; c6="#689d6a"; c7="#a89984"
                c8="#928374"; c9="#fb4934"; c10="#b8bb26"; c11="#fabd2f"
                c12="#83a598"; c13="#d3869b"; c14="#8ec07c"; c15="#ebdbb2" ;;
            catppuccin) fg="#cdd6f4"; bg="#1e1e2e"; cur="#f5e0dc"
                c0="#45475a"; c1="#f38ba8"; c2="#a6e3a1"; c3="#f9e2af"
                c4="#89b4fa"; c5="#cba6f7"; c6="#94e2d5"; c7="#bac2de"
                c8="#585b70"; c9="#f38ba8"; c10="#a6e3a1"; c11="#f9e2af"
                c12="#89b4fa"; c13="#cba6f7"; c14="#94e2d5"; c15="#a5adcb" ;;
            *) fg="#c0caf5"; bg="#1a1b26"; cur="#c0caf5"
                c0="#15161e"; c1="#f7768e"; c2="#9ece6a"; c3="#e0af68"
                c4="#7aa2f7"; c5="#bb9af7"; c6="#7dcfff"; c7="#a9b1d6"
                c8="#414868"; c9="#f7768e"; c10="#9ece6a"; c11="#e0af68"
                c12="#7aa2f7"; c13="#bb9af7"; c14="#7dcfff"; c15="#c0caf5" ;;
        esac
        (
            cd "$build_dir"
            git checkout -- config.def.h 2>/dev/null || true
            sed -i \
                -e "s|\"gray90\", /\\* default foreground colour \\*/|\"${fg}\",|" \
                -e "s|\"black\", /\\* default background colour \\*/|\"${bg}\",|" \
                -e "s|\"#cccccc\",|\"${cur}\",|" \
                -e "s|\"#555555\",|\"${bg}\",|" \
                -e "s|\"black\",|\"${c0}\",|" \
                -e "s|\"red3\",|\"${c1}\",|" \
                -e "s|\"green3\",|\"${c2}\",|" \
                -e "s|\"yellow3\",|\"${c3}\",|" \
                -e "s|\"blue2\",|\"${c4}\",|" \
                -e "s|\"magenta3\",|\"${c5}\",|" \
                -e "s|\"cyan3\",|\"${c6}\",|" \
                -e "s|\"gray90\",|\"${c7}\",|" \
                -e "s|\"gray50\",|\"${c8}\",|" \
                -e "s|\"red\",|\"${c9}\",|" \
                -e "s|\"green\",|\"${c10}\",|" \
                -e "s|\"yellow\",|\"${c11}\",|" \
                -e "s|\"#5c5cff\",|\"${c12}\",|" \
                -e "s|\"magenta\",|\"${c13}\",|" \
                -e "s|\"cyan\",|\"${c14}\",|" \
                -e "s|\"white\",|\"${c15}\",|" \
                -e 's|static char \*font = "Liberation Mono:pixelsize=12:antialias=true:autohint=true";|static char *font = "JetBrainsMono Nerd Font:style=Regular:size=10:antialias=true:autohint=true";|' \
                config.def.h
            make
            install -m 0755 st "/usr/local/bin/st-${theme}"
            make clean >/dev/null 2>&1 || true
        ) || die "build st-$theme gagal"
    done
    cat > /usr/local/bin/st <<'EOF'
#!/bin/sh
# Dispatcher tema st (baca ~/.config/oxwm/theme).
theme=$(cat "$HOME/.config/oxwm/theme" 2>/dev/null || echo tokyonight)
theme=$(printf '%s' "$theme" | tr -d '[:space:]')
case "$theme" in
    gruvbox) exec st-gruvbox "$@" ;;
    catppuccin) exec st-catppuccin "$@" ;;
    *) exec st-tokyonight "$@" ;;
esac
EOF
    chmod 0755 /usr/local/bin/st
    rm -rf "$build_dir"
    log_db "st" "ok" "st-{tokyonight,gruvbox,catppuccin} + dispatcher terpasang"
}

install_helpers() { # perintah pendamping (oxwm-theme, dmenu, dunst bertema) ke /usr/local/bin
    log "pasang perintah pendamping..."
    log_db "helpers" "mulai" "bin/*"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) tulis /usr/local/bin dari $REPO_DIR/bin/*"
    else
        local f
        for f in "$REPO_DIR"/bin/*; do
            [[ -f "$f" ]] || continue
            install -m 0755 "$f" "/usr/local/bin/$(basename "$f")"
        done
    fi
    log_db "helpers" "ok" "perintah pendamping terpasang"
}

deploy_dotfiles() { # salin config standar bila pengguna belum punya
    local src_dir="$REPO_DIR/dotfiles"
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
    mkdir -p "$dest_home/.config/oxwm/colors" "$dest_home/.config/oxwm/wallpapers" "$dest_home/.config/khal" "$dest_home/.config/fastfetch" "$dest_home/.calendars"
    local f
    for f in "$src_dir"/oxwm/colors/*.lua "$src_dir"/oxwm/wallpapers/* "$src_dir"/oxwm/*-status.sh "$src_dir"/oxwm/dunstrc-*; do
        [[ -f "$f" ]] || continue
        local rel="${f#$src_dir/oxwm/}"
        # dunstrc + skrip status selalu disegarkan agar ikut tema/perbaikan;
        # sisanya hanya bila pengguna belum punya.
        case "$rel" in
            dunstrc-*|*-status.sh) cp "$f" "$dest_home/.config/oxwm/$rel" ;;
            *) [[ -f "$dest_home/.config/oxwm/$rel" ]] || cp "$f" "$dest_home/.config/oxwm/$rel" ;;
        esac
    done
    [[ -f "$dest_home/.config/khal/config" ]] || cp "$src_dir/khal/config" "$dest_home/.config/khal/config"
    [[ -f "$dest_home/.config/fastfetch/config.jsonc" ]] || cp "$src_dir/fastfetch/config.jsonc" "$dest_home/.config/fastfetch/config.jsonc"
    if [[ "$THEME_SET" -eq 1 || ! -f "$dest_home/.config/oxwm/theme" ]]; then
        echo "$THEME" > "$dest_home/.config/oxwm/theme"
        log "tema aktif: $THEME"
    else
        log "tema yang ada dipertahankan: $(cat "$dest_home/.config/oxwm/theme")"
    fi
    chown -R "$owner:$owner" "$dest_home/.config/oxwm" "$dest_home/.xinitrc" 2>/dev/null || true
    log_db "dotfiles" "ok" "backup: $backup"
}

enable_services() { # tanpa display manager: autologin getty di tty1 + startx otomatis
    local owner="${SUDO_USER:-$(whoami)}"
    log "siapkan autologin konsol tty1 + startx otomatis untuk $owner..."
    log_db "layanan" "mulai" "getty tty1 + startx"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) tulis drop-in getty@tty1 + ~/.bash_profile + matikan DM lama"
        return 0
    fi
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $owner --noclear %I \$TERM
EOF
    # daemon-reload bisa gagal di lingkungan tanpa systemd aktif (container/
    # chroot); unit drop-in sudah tertulis, reload menyusul saat boot.
    systemctl daemon-reload 2>/dev/null || log "peringatan: daemon-reload gagal (lanjut tanpa reload)"
    # DM lama (bila ada) dimatikan agar tak berebut VT.
    local dm
    for dm in lightdm gdm sddm; do
        if systemctl list-unit-files --no-legend 2>/dev/null | grep -q "^$dm.service"; then
            systemctl disable "$dm" --now || log "peringatan: disable $dm gagal"
        fi
    done
    # startx otomatis saat login konsol di tty1 (cangkang login: bash).
    local profile
    profile="$(user_home "$owner")/.bash_profile"
    if ! grep -q "oxwm-installer: startx otomatis" "$profile" 2>/dev/null; then
        cat >> "$profile" <<'EOF'

# oxwm-installer: startx otomatis di tty1
if [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ]; then
    exec startx
fi
EOF
    fi
    chown "$owner:$owner" "$profile" 2>/dev/null || true
    log_db "layanan" "ok" "autologin tty1 aktif"
}

ensure_nerdfont() { # ikon topbar butuh JetBrainsMono Nerd Font; unduh bila tak ada
    if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd"; then
        log "font JetBrainsMono Nerd sudah ada"
        return 0
    fi
    local owner="${SUDO_USER:-$(whoami)}"
    local target
    target="$(user_home "$owner")/.local/share/fonts"
    log "font Nerd belum ada -> unduh JetBrainsMono Nerd Font ke $target"
    log_db "font" "mulai" "JetBrainsMono.zip"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati unduhan font"
    else
        mkdir -p "$target"
        curl -fL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip" \
            -o /tmp/JetBrainsMono.zip
        unzip -o -q /tmp/JetBrainsMono.zip -d "$target"
        rm -f /tmp/JetBrainsMono.zip
        fc-cache -f "$target" >/dev/null 2>&1 || true
        chown -R "$owner:$owner" "$target" 2>/dev/null || true
    fi
    log_db "font" "ok" "font Nerd terpasang"
}

finish() {
    if [[ "$DRY_RUN" -eq 0 && -n "${RUN_ID:-}" ]]; then
        sqlite3 "$DB_FILE" "UPDATE instalasi SET status='selesai' WHERE id=$RUN_ID;" 2>/dev/null || true
    fi
    log "selesai. reboot: login konsol otomatis di tty1 lalu startx jalan sendiri ke OXWM."
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --yes) ASSUME_YES=1; shift ;;
            --theme)
                [[ -n "${2:-}" ]] || { echo "opsi --theme butuh nilai (tokyonight|gruvbox|catppuccin)"; exit 2; }
                THEME="$2"; THEME_SET=1; shift 2 ;;
            --help) usage; exit 0 ;;
            *) echo "opsi tidak dikenal: $1 (lihat --help)"; exit 2 ;;
        esac
    done
    case "$THEME" in
        tokyonight|gruvbox|catppuccin) ;;
        *) echo "tema tidak dikenal: $THEME (pilih: tokyonight|gruvbox|catppuccin)"; exit 2 ;;
    esac
    check_root
    detect_distro
    db_init || true
    log_db "mulai" "ok" "instalasi OXWM dimulai (distro=$DISTRO dry-run=$DRY_RUN)"
    confirm
    resolve_repo_dir
    system_update
    install_packages
    ensure_zig
    ensure_nerdfont
    install_oxwm
    build_st
    install_helpers
    deploy_dotfiles
    enable_services
    finish
}

# Guard ini memungkinkan unit-test: source file ini tanpa argumen
# menjalankan fungsi-fungsinya tanpa mengeksekusi instalasi.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
