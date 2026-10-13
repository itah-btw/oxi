#!/usr/bin/env bash
#
# oxwm-installer — instalasi otomatis window manager OXWM.
# Didukung: Arch Linux (pacman), Debian/Ubuntu (apt), Fedora (dnf).
# Cara pakai: sudo ./install.sh [--dry-run] [--yes] [--rebuild] [--theme NAMA] [--help]
#
# Alur: siapkan log -> cek root -> deteksi distro -> konfirmasi ->
#       update sistem -> instal paket (nama dipetakan per distro) ->
#       pastikan fastfetch/zig/font Nerd -> bangun & pasang OXWM dari source ->
#       bangun st 3 tema -> pasang perintah pendamping ->
#       deploy dotfiles (topbar, keybind, tema, dmenu/dunst bertema,
#       skrip status, khal) -> autologin getty tty1 + startx otomatis -> selesai.
#
# Tanpa display manager: login konsol otomatis di tty1 lalu startx.
set -euo pipefail

LOG_FILE="install.log"  # ditimpa init_log() ke path tetap bila bisa ditulis
DRY_RUN=0
ASSUME_YES=0
REBUILD=0
THEME="tokyonight"
THEME_SET=0
DISTRO=""
ZIG_VERSION="0.16.0"          # TERPIN: oxwm HEAD butuh zig 0.16.x (build.zig pakai b.args yang dihapus di zig 0.17)
ZIG_SHA256="70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00" # sha256 zig-x86_64-linux-0.16.0.tar.xz resmi (terverifikasi dari unduhan langsung)
OXWM_REPO="https://github.com/tonybanters/oxwm"
OXWM_PIN="${OXWM_PIN:-}"      # kosong = bangun dari HEAD terbaru; isi SHA-1 40 digit untuk pin reproduksibel
REPO_SLUG="itah-btw/oxwm-installer"
REF="${OXWM_REF:-main}"         # timpa untuk coba cabang lain: OXWM_REF=dev ... | bash
REPO_DIR=""                     # diisi resolve_repo_dir(); jangan diakses langsung

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }
tahap() { # $1=tahap $2=status $3=pesan — riwayat tahap ke berkas log
    # Status "ok" untuk langkah yang dilewati (dry-run) adalah dusta.
    if [[ "$DRY_RUN" -eq 1 && "$2" == "ok" ]]; then
        log "(dry-run) [$1] dilewati: $3"
    else
        log "[$1] $2: $3"
    fi
}
valid_user() { [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; } # nama user Linux yang waras

# --- Log: path tetap, bukan cwd acak tempat sudo dijalankan ---
init_log() {
    if [[ "$DRY_RUN" -eq 0 ]]; then
        local dir="${OXWM_LOG_DIR:-/var/log/oxwm-installer}"
        if mkdir -p "$dir" 2>/dev/null && touch "$dir/install.log" 2>/dev/null; then
            LOG_FILE="$dir/install.log"
        else
            log "peringatan: $dir tak bisa ditulis, log ke ./install.log"
        fi
    fi
}

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

usage() {
    cat <<'EOF'
Pakai: sudo ./install.sh [OPSI]

Satu baris (butuh curl; tanpa klon dulu; mode pipe wajib --yes eksplisit):
  curl -fsSL https://cdn.jsdelivr.net/gh/itah-btw/oxwm-installer@main/install.sh | sudo bash -s -- --yes
  curl -fsSL https://cdn.jsdelivr.net/gh/itah-btw/oxwm-installer@main/install.sh | sudo bash -s -- --theme gruvbox --yes
  (cermin jsDelivr dari repo yang sama; URL mentah GitHub juga bisa dipakai)
  Cabang lain: OXWM_REF=dev ... | sudo bash -s -- --theme gruvbox

Distro didukung: Arch Linux, Debian/Ubuntu, Fedora (terdeteksi otomatis).

  --dry-run   simulasi saja: tampilkan rencana tanpa mengubah sistem
              (tidak butuh sudo)
  --yes       lewati konfirmasi (untuk otomatisasi; wajib bila via pipe)
  --rebuild   bangun ulang oxwm + st walau binernya sudah ada
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
    valid_user "$SUDO_USER" || die "SUDO_USER tidak valid: '$SUDO_USER'"
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
    # ensure_zig() memasang tarball 0.16.0 (seri yang didukung oxwm) bila perlu.
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
    [fetch]="fastfetch||fastfetch" # Debian lama tanpa paket resmi -> ensure_fastfetch() (.deb upstream)
    [calendar]="khal|khal|khal"
    [ocr]="tesseract|tesseract-ocr|tesseract"
    [mixer]="wireplumber|wireplumber|wireplumber"
    [powerprof]="power-profiles-daemon|power-profiles-daemon|power-profiles-daemon"
    [netcli]="networkmanager|network-manager|NetworkManager"
    [bluetooth]="bluez-utils|bluez|bluez"
    [git]="git|git|git"
    [curl]="curl|curl|curl"
    [vcsbuild]="base-devel|build-essential|@development-tools"
)

pkg_for() { # $1=kunci -> nama paket distro aktif (tanpa fork cut)
    local map="${PKGMAP[$1]}"
    local first="${map%%|*}" rest="${map#*|}"
    local second="${rest%%|*}" third="${rest#*|}"
    case "$DISTRO" in
        debian) printf '%s' "$second" ;;
        fedora) printf '%s' "$third" ;;
        *)      printf '%s' "$first" ;;
    esac
}

detect_distro() {
    UPDATE2=()
    if [[ -f /etc/arch-release ]] || command -v pacman >/dev/null; then
        DISTRO="arch"; UPDATE=(pacman -Syu --noconfirm); INSTALL=(pacman -S --needed --noconfirm)
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
    # script, jadi tidak aman bertanya. Mode pipe wajib --yes eksplisit
    # agar tak ada sistem yang terinstalasi tanpa persetujuan sadar.
    if [[ ! -t 0 && "$ASSUME_YES" -eq 0 ]]; then
        die "mode pipe butuh --yes eksplisit: curl ... | sudo bash -s -- --yes"
    fi
    if [[ ! -t 0 ]]; then
        log "mode pipe + --yes: lanjut otomatis"
        return 0
    fi
    echo "Ringkasan: instal OXWM (build dari source) + aplikasi pendukung + dotfiles standar (topbar, keybind, 3 tema, dmenu/dunst bertema; tema: $THEME) di $DISTRO. Tanpa display manager (autologin tty1 + startx)."
    read -rp "Lanjut? [y/N] " jawab
    [[ "$jawab" == "y" || "$jawab" == "Y" ]] || { tahap "konfirmasi" "dibatalkan" "pengguna menjawab tidak"; die "dibatalkan pengguna"; }
    tahap "konfirmasi" "ok" "pengguna menyetujui"
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
    while true; do
        if "$@"; then
            return 0
        fi
        if [[ "$coba" -ge "$maks" ]]; then
            return 1
        fi
        log "percobaan $coba/$maks gagal, ulangi setelah 5 dtk..."
        sleep 5
        coba=$((coba + 1))
    done
}

system_update() {
    log "update sistem..."
    tahap "update" "mulai" "${UPDATE[*]}"
    run_or_dry retry 3 "${UPDATE[@]}"
    if [[ -n "${UPDATE2[*]:-}" ]]; then
        run_or_dry retry 3 "${UPDATE2[@]}"
    fi
    tahap "update" "ok" "sistem mutakhir"
}

install_packages() {
    local keys=(git curl vcsbuild xserver xinit xsetroot zigbuild x11 xft freetype fontconfig xinerama
                launcher wallpaper shot shotsel keysim fontmono fonticon notify clipboard libnotify
                bright monitor fetch calendar ocr mixer powerprof netcli bluetooth)
    local pkgs=()
    local k name
    for k in "${keys[@]}"; do
        name="$(pkg_for "$k")"
        [[ -z "$name" ]] && { log "lewati '$k' (tidak tersedia di $DISTRO, ditangani modul khusus)"; continue; }
        pkgs+=("$name")
    done
    log "instal ${#pkgs[@]} paket: ${pkgs[*]}"
    tahap "paket" "mulai" "${pkgs[*]}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati instalasi paket"
    else
        retry 3 "${INSTALL[@]}" "${pkgs[@]}"
    fi
    tahap "paket" "ok" "selesai"
}

ensure_fastfetch() { # Debian/Ubuntu lama tanpa paket fastfetch resmi -> .deb upstream
    command -v fastfetch >/dev/null && { log "fastfetch sudah ada"; return 0; }
    [[ "$DISTRO" == "debian" ]] || return 0  # non-Debian sudah dipasang via paket
    tahap "fastfetch" "mulai" "cek repo / fallback .deb upstream"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati fastfetch (.deb upstream bila repo tak punya)"
        return 0
    fi
    # Tampung dulu stdout-nya: grep -q langsung di pipa rawan SIGPIPE
    # (penulis mati lebih dulu -> pipefail gagal -> cabang salah).
    local policy ver api deb
    policy="$(apt-cache policy fastfetch 2>/dev/null)" || die "gagal baca info paket fastfetch"
    if grep -q "Candidate: (none)" <<<"$policy"; then
        log "fastfetch tak ada di repo -> unduh .deb upstream"
        api=/tmp/fastfetch-release.json
        curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest \
            -o "$api" || die "gagal ambil info rilis fastfetch"
        ver="$(grep -m1 '"tag_name"' "$api" | grep -o -m1 '[0-9][0-9.]*')"
        rm -f "$api"
        [[ -n "$ver" ]] || die "gagal deteksi versi fastfetch terbaru"
        deb="/tmp/fastfetch-${ver}-linux-amd64.deb"
        curl -fL "https://github.com/fastfetch-cli/fastfetch/releases/download/${ver}/fastfetch-linux-amd64.deb" \
            -o "$deb" || die "unduhan fastfetch gagal"
        dpkg -i "$deb" || apt-get install -f -y || die "pemasangan fastfetch .deb gagal"
        rm -f "$deb"
    else
        apt-get install -y fastfetch || die "pemasangan fastfetch gagal"
    fi
    command -v fastfetch >/dev/null || die "fastfetch tak ketemu setelah dipasang"
    tahap "fastfetch" "ok" "terpasang"
}

ensure_zig() { # pastikan compiler zig seri 0.16.x ada (yang didukung oxwm); kalau tidak, unduh tarball resmi
    if command -v zig >/dev/null; then
        local zv
        zv="$(zig version)"
        if [[ "$zv" == 0.16.* ]]; then
            log "zig sudah ada & cocok: $zv"
            return 0
        fi
        log "zig sistem ($zv) di luar seri 0.16.x -> pasang tarball $ZIG_VERSION"
    fi
    tahap "zig" "mulai" "tarball $ZIG_VERSION"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati unduhan zig"
        return 0
    fi
    local arsip=/tmp/zig.tar.xz
    curl -fL "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
        -o "$arsip" || die "unduhan zig gagal"
    log "verifikasi sha256 tarball zig..."
    echo "${ZIG_SHA256}  ${arsip}" | sha256sum -c - \
        || die "checksum zig tak cocok (unduhan rusak/disusupi?)"
    rm -rf /opt/zig && mkdir -p /opt/zig
    tar -xJf "$arsip" -C /opt/zig --strip-components=1 || die "ekstraksi zig gagal"
    ln -sf /opt/zig/zig /usr/local/bin/zig
    rm -f "$arsip"
    command -v zig >/dev/null || die "zig tak ketemu setelah dipasang"
    log "zig terpasang: $(zig version)"
    tahap "zig" "ok" "tarball terpasang"
}

install_oxwm() { # bangun dari source agar hasilnya sama di Arch/Fedora/Debian
    local build_dir="/tmp/oxwm-build"
    if [[ "$REBUILD" -eq 0 && -x /usr/local/bin/oxwm ]]; then
        log "oxwm sudah terpasang, lewati (pakai --rebuild untuk bangun ulang)"
        return 0
    fi
    # OXWM_PIN bisa ditimpa via environment: validasi sebelum dipakai di dalam
    # `su -c "..."` (injeksi shell berjalan sebagai user target). Kosong = HEAD terbaru.
    if [[ -n "$OXWM_PIN" ]]; then
        [[ "$OXWM_PIN" =~ ^[0-9a-f]{40}$ ]] || die "OXWM_PIN tidak valid (harus SHA-1 40 digit heksa)"
    fi
    [[ "$OXWM_REPO" != *"'"* && "$build_dir" != *"'"* ]] || die "path/repo mengandung kutip tunggal"
    log "bangun & pasang OXWM dari source ($OXWM_REPO)..."
    tahap "oxwm" "mulai" "zig build dari source"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati clone + build oxwm"
    else
        rm -rf "$build_dir"
        # Pin ke komit teruji agar hasil dapat diulang bila OXWM_PIN diisi;
        # kosong berarti HEAD terbaru. Clone sebagai pemilik repo agar tak kena
        # dubious ownership bila SUDO_USER terlibat.
        if [[ -n "${SUDO_USER:-}" ]]; then
            su "$SUDO_USER" -c "git clone --depth 1 '$OXWM_REPO' '$build_dir'"
            if [[ -n "$OXWM_PIN" ]]; then
                su "$SUDO_USER" -c "git -C '$build_dir' fetch --depth 1 origin '$OXWM_PIN' && git -C '$build_dir' checkout -q '$OXWM_PIN'"
            fi
        else
            git clone --depth 1 "$OXWM_REPO" "$build_dir"
            if [[ -n "$OXWM_PIN" ]]; then
                git -C "$build_dir" fetch --depth 1 origin "$OXWM_PIN" && git -C "$build_dir" checkout -q "$OXWM_PIN"
            fi
        fi
        if [[ -n "$OXWM_PIN" ]]; then
            log "oxwm dipin ke komit $OXWM_PIN"
        else
            log "oxwm dari HEAD terbaru ($OXWM_REPO)"
        fi
        (cd "$build_dir" && zig build -Doptimize=ReleaseSmall)
        install -m 0755 "$build_dir/zig-out/bin/oxwm" /usr/local/bin/oxwm
        rm -rf "$build_dir"
        [[ -x /usr/local/bin/oxwm ]] || die "biner oxwm tak ketemu setelah build"
    fi
    tahap "oxwm" "ok" "terpasang di /usr/local/bin/oxwm"
}

build_st() { # terminal st dari source suckless, 3 build bertema + dispatcher `st`
    # Repo distro tak konsisten menyediakan st (Arch bahkan tak punya), jadi
    # bangun dari source. Pola sed sama dengan modul Nix
    # (config.def.h: komentar dulu baru kembaran polosnya — urutan penting).
    local build_dir="/tmp/st-build" repo="https://git.suckless.org/st"
    if [[ "$REBUILD" -eq 0 && -x /usr/local/bin/st-tokyonight && -x /usr/local/bin/st-gruvbox && -x /usr/local/bin/st-catppuccin ]]; then
        log "st 3 tema sudah terpasang, lewati (pakai --rebuild untuk bangun ulang)"
        return 0
    fi
    local jobs; jobs="$(nproc 2>/dev/null || echo 1)"
    local theme fg bg cur c0 c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 c15
    log "bangun & pasang st 3 tema dari source ($repo)..."
    tahap "st" "mulai" "make 3 tema"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati clone + build st"
        return 0
    fi
    rm -rf "$build_dir"
    if [[ -n "${SUDO_USER:-}" ]]; then
        su "$SUDO_USER" -c "git clone --depth 1 '$repo' '$build_dir'"
    else
        git clone --depth 1 "$repo" "$build_dir"
    fi
    # Simpan config murni sekali: reset via git rapuh bila root membangun di
    # repo milik user lain (dubious ownership) sehingga varian ikut tercemar.
    cp "$build_dir/config.def.h" /tmp/st-config.def.h.orig
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
            cp /tmp/st-config.def.h.orig config.def.h
            rm -f config.h
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
            make -j"$jobs"
            install -m 0755 st "/usr/local/bin/st-${theme}"
            make clean >/dev/null 2>&1 || true
        ) || die "build st-$theme gagal"
    done
    # Verifikasi fail-loud: tiga varian harus benar-benar berbeda binernya.
    if [[ $(md5sum /usr/local/bin/st-tokyonight /usr/local/bin/st-gruvbox /usr/local/bin/st-catppuccin | awk '{print $1}' | sort -u | wc -l) -ne 3 ]]; then
        die "build st gagal: tiga varian biner identik (palet tercemar)"
    fi
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
    tahap "st" "ok" "st-{tokyonight,gruvbox,catppuccin} + dispatcher terpasang"
}

install_helpers() { # perintah pendamping (oxwm-theme, dmenu, dunst bertema) ke /usr/local/bin
    log "pasang perintah pendamping..."
    tahap "helpers" "mulai" "bin/*"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) tulis /usr/local/bin dari $REPO_DIR/bin/*"
    else
        local f
        for f in "$REPO_DIR"/bin/*; do
            [[ -f "$f" ]] || continue
            install -m 0755 "$f" "/usr/local/bin/$(basename "$f")"
        done
    fi
    tahap "helpers" "ok" "perintah pendamping terpasang"
}

deploy_dotfiles() { # salin config standar bila pengguna belum punya
    local src_dir="$REPO_DIR/dotfiles"
    local dest_home="${TARGET_HOME:-$HOME}"
    local owner="${SUDO_USER:-$(whoami)}"
    log "deploy dotfiles $src_dir -> $dest_home"
    tahap "dotfiles" "mulai" "$src_dir"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati penyalinan dotfiles"
        return 0
    fi
    local backup
    backup="$dest_home/.config-backup-$(date +%F-%H%M%S)"
    local n=0
    while [[ -e "$backup" ]]; do  # jalan 2x di detik yang sama pun tak menimpa
        n=$((n + 1))
        backup="$dest_home/.config-backup-$(date +%F-%H%M%S)-$n"
    done
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
    tahap "dotfiles" "ok" "backup: $backup"
}

enable_services() { # tanpa display manager: autologin getty di tty1 + startx otomatis
    local owner="${SUDO_USER:-$(whoami)}"
    valid_user "$owner" || die "nama user tidak valid: '$owner'"
    log "siapkan autologin konsol tty1 + startx otomatis untuk $owner..."
    tahap "layanan" "mulai" "getty tty1 + startx"
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
    # DM lama (bila ada) dimatikan agar tak berebut VT. Tampung dulu:
    # grep -q langsung di pipa rawan SIGPIPE (daftar unit panjang).
    local dm units
    units="$(systemctl list-unit-files --no-legend 2>/dev/null)" || units=""
    for dm in lightdm gdm gdm3 sddm; do
        if grep -q "^$dm.service" <<<"$units"; then
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
    tahap "layanan" "ok" "autologin tty1 aktif"
}

nerd_terpasang() { # $1=owner -> 0 bila fc-list user itu melihat JetBrainsMono Nerd
    # HARUS dalam konteks owner: fc-list root tak memindai ~/.local/share/fonts user.
    # Tanpa su bila owner == user aktif (agar dry-run non-root tak meminta password).
    # Pakai hitungan (-c), BUKAN -q: grep -q keluar lebih awal -> penulis kena
    # SIGPIPE -> pipefail menandakan gagal walau font sebenarnya ada!
    local n=0
    if [[ "$1" == "$(whoami)" ]]; then
        n="$(fc-list 2>/dev/null | grep -ci "JetBrainsMono Nerd")" || true
    else
        n="$(su "$1" -c "fc-list" 2>/dev/null | grep -ci "JetBrainsMono Nerd")" || true
    fi
    [[ "${n:-0}" -gt 0 ]]
}

ensure_nerdfont() { # ikon topbar butuh JetBrainsMono Nerd Font; unduh bila tak ada
    local owner="${SUDO_USER:-$(whoami)}"
    valid_user "$owner" || die "nama user tidak valid: '$owner'"
    if nerd_terpasang "$owner"; then
        log "font JetBrainsMono Nerd sudah ada"
        return 0
    fi
    local target
    target="$(user_home "$owner")/.local/share/fonts"
    local arsip=/tmp/JetBrainsMono.tar.xz
    log "font Nerd belum ada -> unduh JetBrainsMono terbaru ke $target"
    tahap "font" "mulai" "JetBrainsMono terbaru (tar.xz)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati unduhan font"
    else
        mkdir -p "$target"
        curl -fL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" \
            -o "$arsip" || die "unduhan font gagal"
        tar -xJf "$arsip" -C "$target" || die "ekstraksi font gagal"
        rm -f "$arsip"
        compgen -G "$target/*.ttf" >/dev/null || die "tak ada .ttf di $target setelah ekstraksi"
        fc-cache -f "$target" >/dev/null 2>&1 || true
        chown -R "$owner:$owner" "$target" 2>/dev/null || true
        nerd_terpasang "$owner" \
            || die "font Nerd tak terdeteksi setelah dipasang"
    fi
    tahap "font" "ok" "font Nerd terpasang"
}

finish() {
    log "selesai. reboot: login konsol otomatis di tty1 lalu startx jalan sendiri ke OXWM."
    log "log lengkap: $LOG_FILE"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --yes) ASSUME_YES=1; shift ;;
            --rebuild) REBUILD=1; shift ;;
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
    init_log
    log "========== oxwm-installer mulai (dry-run=$DRY_RUN) =========="
    check_root
    detect_distro
    tahap "mulai" "ok" "instalasi OXWM dimulai (distro=$DISTRO dry-run=$DRY_RUN)"
    confirm
    resolve_repo_dir
    system_update
    install_packages
    ensure_fastfetch
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
# BASH_SOURCE kosong saat script masuk via pipe (set -u!) -> tetap jalan.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
