#!/usr/bin/env bash
#
# oxwm-installer - instalasi otomatis window manager OXWM.
# Didukung: Arch Linux (pacman), Debian/Ubuntu (apt), Fedora (dnf).
# Cara pakai: sudo ./install.sh [--dry-run] [--yes] [--rebuild] [--theme NAMA] [--help]
#
# Alur: siapkan log -> cek root -> deteksi distro -> konfirmasi ->
#       update sistem -> instal paket (nama dipetakan per distro) ->
#       pastikan fastfetch/zig/font Nerd -> bangun & pasang OXWM dari source ->
#       bangun st 3 tema -> pasang perintah pendamping ->
#       deploy dotfiles (topbar, keybind, tema, dmenu/dunst bertema,
#       skrip status, khal) -> sesi OXWM (pakai display manager bila ada,
#       autologin getty tty1 + startx bila tidak) -> selesai.
#
# Display manager (bila terdeteksi) dipakai apa adanya + entri sesi OXWM;
# tanpa display manager: login konsol otomatis di tty1 lalu startx.
set -Eeuo pipefail

LOG_FILE="install.log"  # ditimpa init_log() ke path tetap bila bisa ditulis
VERSION="1.2.0"
DRY_RUN=0
ASSUME_YES=0
REBUILD=0
LATEST=0            # --latest: OXWM dari HEAD terbaru (default: pin teruji)
NO_UPDATE=0         # --no-update: lewati upgrade sistem
UNINSTALL=0         # --uninstall: hapus yang dipasang installer
SELF_UPDATE=0       # --self-update: bangun ulang hanya komponen outdated (oxu)
CHECK_ONLY=0        # --check: laporkan versi komponen, tanpa mengubah apa pun
SESSION_REQ="auto"  # auto|autologin|manual|dm:NAMA
SESSION_SET=0       # 1 bila sesi ditentukan via flag
TERMINAL="st"       # terminal bawaan (st|alacritty|kitty|ghostty)
TERMINAL_SET=0      # 1 bila --terminal eksplisit
OLD_DM=""           # DM terdeteksi sebelum diubah (untuk disable yang lama)
FORCE_AUTOLOGIN=0   # --force-autologin: autologin tty1 walau ada display manager
NO_AUTOLOGIN=0      # --no-autologin: jangan sentuh getty/startx (DM/manual saja)
THEME="tokyonight"
THEME_SET=0
DISTRO=""
SESSION_MODE=""     # diisi enable_services(): dm:<nama> | autologin | manual
DM_CANDIDATES=(lightdm gdm gdm3 sddm lxdm slim xdm ly greetd emptty lemurs)
ZIG_VERSION="0.16.0"          # TERPIN: oxwm HEAD butuh zig 0.16.x (build.zig pakai b.args yang dihapus di zig 0.17)
ZIG_SHA256="70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00" # sha256 zig-x86_64-linux-0.16.0.tar.xz resmi (terverifikasi dari unduhan langsung)
FASTFETCH_VERSION="2.70.0"      # TERPIN: fallback .deb untuk Debian/Ubuntu lama tanpa paket resmi
FASTFETCH_SHA256="06e9a1be9a863dc815f8a31a6b1abec7b29967be30084ffcc29c1bca072d801b" # sha256 fastfetch-linux-amd64.deb 2.70.0 (terverifikasi dari unduhan langsung)
NERDFONT_VERSION="v3.5.1"       # TERPIN: arsip font tidak berversi di URL latest - pin eksplisit
NERDFONT_SHA256="04d5e8f903693f9dd13e16f867e994834e681eb3c72c0d337a770dcda09010cf" # sha256 JetBrainsMono.tar.xz v3.5.1 (terverifikasi dari unduhan langsung)
# Catatan pin: hanya untuk unduhan upstream. Paket repo distro (apt/dnf/pacman)
# selalu latest dari repo saat instalasi berjalan - pin tak mengubah itu.
OXWM_REPO="https://github.com/tonybanters/oxwm"
OXWM_PIN_DEFAULT="472c76753fed1e1430014328237da1db053bbb64" # komit teruji 2026-10-07 (merge PR #258)
# Default reproduksibel (pin); HEAD terbaru hanya bila: --latest, OXWM_PIN=""
# eksplisit, atau OXWM_PIN=<40-heksa lain>. Bedakan "tak diset" (-) dari
# "dikosongkan" (:-) agar override kosong tetap berarti HEAD.
OXWM_PIN="${OXWM_PIN-$OXWM_PIN_DEFAULT}"
TMPDIRS=()              # diisi new_tmpdir(); dibersihkan trap di main()
REPO_SLUG="itah-btw/oxwm-installer"
REF="${OXWM_REF:-main}"         # timpa untuk coba cabang lain: OXWM_REF=dev ... | bash
REPO_DIR=""                     # diisi resolve_repo_dir(); jangan diakses langsung

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }
# shellcheck disable=SC2329 # dipanggil via trap ERR di main()
on_err() { # $1=kode $2=perintah $3=baris - catat kegagalan tak terduga (set -e)
    log "ERROR: keluar kode $1 di baris ${3:-?}: ${2:-?}"
}
tahap() { # $1=tahap $2=status $3=pesan - riwayat tahap ke berkas log
    # Status "ok" untuk langkah yang dilewati (dry-run) adalah dusta.
    if [[ "$DRY_RUN" -eq 1 && "$2" == "ok" ]]; then
        log "(dry-run) [$1] dilewati: $3"
    else
        log "[$1] $2: $3"
    fi
}
valid_user() { [[ "${1:-}" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; } # nama user Linux yang waras

# SC2120 non-isu: argumen opsional memang untuk unit-test (check_arch aarch64);
# produksi memanggil tanpa argumen (-> uname).
# shellcheck disable=SC2120
check_arch() { # [$1=arsitektur, default uname] - tarball zig + .deb fastfetch hanya x86_64
    local a="${1:-$(uname -m)}"
    if [[ "$a" != "x86_64" && -z "${OXWM_ALLOW_ARCH:-}" ]]; then
        die "arsitektur tak didukung: $a (butuh x86_64; timpa darurat via OXWM_ALLOW_ARCH=1)"
    fi
}

# Direktori sementara unik per run (bukan /tmp/nama-tetap yang tabrakan).
new_tmpdir() {
    local d
    d="$(mktemp -d)" || die "gagal buat direktori sementara"
    TMPDIRS+=("$d")
    printf '%s' "$d"
}
cleanup_tmpdirs() {
    if [[ "${#TMPDIRS[@]}" -gt 0 ]]; then
        rm -rf "${TMPDIRS[@]}" 2>/dev/null || true
    fi
}

# Tolak instalasi paralel (dua terminal/dua sesi tabrakan di
# /usr/local/bin, drop-in getty, dst). Non-blokir: langsung gagal.
acquire_lock() {
    local lock="${OXWM_LOCK_FILE:-/var/lock/oxwm-installer.lock}"
    exec 9>"$lock" || die "gagal membuka lockfile $lock"
    flock -n 9 || die "installer sedang berjalan di sesi lain (lock: $lock)"
    log "lock terkunci: $lock"
}

pipe_grace() { # jeda persetujuan di mode pipe tanpa --yes (batal via Ctrl-C)
    local grace="${OXWM_PIPE_GRACE:-5}"
    [[ "$grace" =~ ^[0-9]+$ ]] || grace=5
    [[ "$grace" -eq 0 ]] && return 0
    echo "Mode pipe tanpa --yes: lanjut otomatis dalam $grace detik (Ctrl-C untuk batal)..." >&2
    local i
    for ((i = grace; i > 0; i--)); do
        echo "  lanjut dalam $i..." >&2
        sleep 1
    done
}

# --- Log: path tetap, bukan cwd acak tempat sudo dijalankan ---
init_log() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        return 0
    fi
    local dir="${OXWM_LOG_DIR:-/var/log/oxwm-installer}"
    if mkdir -p "$dir" 2>/dev/null && touch "$dir/install.log" 2>/dev/null; then
        LOG_FILE="$dir/install.log"
    else
        LOG_FILE="install.log"
        log "peringatan: $dir tak bisa ditulis, log ke $LOG_FILE"
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
    tmp="$(mktemp -d)" || die "gagal buat direktori sementara"
    TMPDIRS+=("$tmp")
    log "unduh repo $REPO_SLUG@$REF ke $tmp..."
    curl -fsSL --retry 3 --retry-delay 2 --proto '=https' --proto-redir '=https' \
        "https://github.com/$REPO_SLUG/archive/refs/heads/$REF.tar.gz" -o "$tmp/repo.tar.gz" \
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

Satu baris (cukup ini saja - semua tema ikut terpasang; tanpa flag tema pun
tokyonight/gruvbox/catppuccin semuanya terinstal, tinggal ganti kapan saja
dengan `oxwm-theme` setelah login):
  curl -fsSL https://raw.githubusercontent.com/itah-btw/oxwm-installer/main/install.sh | sudo bash

Distro didukung: Arch Linux, Debian/Ubuntu, Fedora (terdeteksi otomatis).

Sesi OXWM (otomatis): bila display manager terdeteksi (lightdm/gdm/sddm/
lxdm/slim/xdm/ly/greetd/dll) maka DM dipakai + OXWM didaftarkan sebagai
sesi; bila tidak ada DM maka autologin getty di tty1 + startx otomatis.

  --dry-run   simulasi saja: tampilkan rencana tanpa mengubah sistem
              (tidak butuh sudo)
  --yes       lewati konfirmasi (untuk otomatisasi; di mode pipe gantikan
              masa tenggang 5 detik)
  --rebuild   bangun ulang oxwm + st walau binernya sudah ada
  --latest    bangun OXWM dari HEAD terbaru. Default: pin ke komit teruji
              472c7675 (reproduksibel; timpa via OXWM_PIN=<40-heksa>/"" )
  --no-update lewati upgrade sistem (langsung instal paket)
  --uninstall hapus biner + oxu + sesi buatan installer (dotfiles dibiarkan)
  --self-update
              bangun ulang hanya komponen yang outdated (perintah: oxu).
              Tanpa upgrade sistem/paket dan tanpa utak-atik sesi
  --check     laporkan versi komponen vs pin/HEAD, tanpa mengubah apa pun
  --session auto|autologin
              sesi login (default: otomatis bila ada DM, tanya bila belum ada)
  --dm sddm|gdm|lightdm
              pasang DM itu + jadikan pintu login (DM lama dimatikan)
  --terminal st|alacritty|kitty|ghostty
              terminal bawaan (default: st 3 tema; lainnya dari repo)
  --force-autologin
              paksa autologin tty1 + startx walau ada display manager
  --no-autologin
              jangan sentuh getty/startx (untuk login manual atau
              display manager yang dipasang belakangan)
  --theme NAMA
              tema aktif awal: tokyonight (bawaan) | gruvbox | catppuccin.
              Ketiga tema SELALU dipasang (st 3 varian, palet, wallpaper,
              dunstrc per tema); flag ini hanya memilih mana yang aktif.
              Tanpa flag ini file tema yang sudah ada tidak diubah.
              Bentuk --theme=gruvbox juga diterima.
  --version   tampilkan versi installer
  --help      tampilkan bantuan ini

Contoh:
  ./install.sh --dry-run   # lihat rencana dulu (aman)
  sudo ./install.sh        # instalasi penuh (semua tema ikut)
  sudo ./install.sh --no-update --yes  # tanpa upgrade sistem
  sudo ./install.sh --uninstall --yes  # hapus instalasi
  oxu                    # perbarui komponen yang outdated (butuh instal ulang sekali agar oxu ada)
  oxu --check            # cek saja, tanpa root pun bisa
  oxwm-theme gruvbox       # ganti tema kapan saja, tanpa instal ulang
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
    [audio]="pipewire|pipewire|pipewire"
    [pulse]="pipewire-pulse|pipewire-pulse|pipewire-pulseaudio"
    [alsacompat]="pipewire-alsa|pipewire-alsa|pipewire-alsa"
    [powerprof]="power-profiles-daemon|power-profiles-daemon|power-profiles-daemon"
    [netcli]="networkmanager|network-manager|NetworkManager"
    [bluetooth]="bluez-utils|bluez|bluez"
    [mediakeys]="playerctl|playerctl|playerctl"
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
    local id=""
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        id="$(set -a; . /etc/os-release 2>/dev/null; set +a; printf '%s' "${ID:-}")"
    fi
    case "$id" in
        arch|artix|manjaro|endeavouros|cachyos)
            DISTRO="arch" ;;
        debian|ubuntu|linuxmint|pop|elementary|zorin)
            DISTRO="debian" ;;
        fedora|rhel|centos|rocky|almalinux)
            DISTRO="fedora" ;;
        "")
            if [[ -f /etc/arch-release ]] || command -v pacman >/dev/null; then
                DISTRO="arch"
            elif command -v apt-get >/dev/null; then
                DISTRO="debian"
            elif command -v dnf >/dev/null; then
                DISTRO="fedora"
            else
                die "distro tidak didukung (butuh pacman/apt/dnf)"
            fi ;;
        *)
            die "distro tidak didukung: $id (butuh Arch/Debian/Fedora)" ;;
    esac
    case "$DISTRO" in
        arch)   UPDATE=(pacman -Syu --noconfirm); INSTALL=(pacman -S --needed --noconfirm) ;;
        debian) UPDATE=(apt-get update); UPDATE2=(apt-get upgrade -y); INSTALL=(apt-get install -y) ;;
        fedora) UPDATE=(dnf upgrade -y --refresh); INSTALL=(dnf install -y) ;;
    esac
    # Cegah prompt interaktif (needrestart/confold) di tengah apt upgrade/install.
    [[ "$DISTRO" == "debian" ]] && export DEBIAN_FRONTEND=noninteractive
    log "distro: $DISTRO"
}

confirm() {
    if [[ "$DRY_RUN" -eq 1 || "$ASSUME_YES" -eq 1 ]]; then
        log "konfirmasi dilewati (dry-run/--yes)"
        return 0
    fi
    # Mode pipe (curl ... | sudo bash): stdin adalah scriptnya, tak bisa
    # ditanya - tampilkan ringkasan + masa tenggang sebelum lanjut.
    if [[ ! -t 0 ]]; then
        echo "Ringkasan: instal OXWM (build dari source) + aplikasi pendukung + dotfiles standar (topbar, keybind, SEMUA tema: tokyonight/gruvbox/catppuccin + dmenu/dunst bertema; tema aktif: $THEME, bisa diganti kapan saja via oxwm-theme) di $DISTRO. Sesi: $SESSION_REQ. Terminal: $TERMINAL." >&2
        pipe_grace
        ASSUME_YES=1
        log "mode pipe: lanjut setelah masa tenggang"
        return 0
    fi
    echo "Ringkasan: instal OXWM (build dari source) + aplikasi pendukung + dotfiles standar (topbar, keybind, SEMUA tema: tokyonight/gruvbox/catppuccin + dmenu/dunst bertema; tema aktif: $THEME, bisa diganti kapan saja via oxwm-theme) di $DISTRO. Sesi: $SESSION_REQ. Terminal: $TERMINAL."
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
    if [[ "$NO_UPDATE" -eq 1 ]]; then
        log "update sistem dilewati (--no-update)"
        tahap "update" "dilewati" "--no-update"
        return 0
    fi
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
                bright monitor fetch calendar ocr mixer audio pulse alsacompat powerprof netcli bluetooth mediakeys)
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

ensure_fastfetch() { # semua distro; Debian lama tanpa paket resmi -> fallback .deb upstream
    if [[ "$DISTRO" != "debian" ]]; then
        # Non-Debian: paket repo penuh. Dipasang bila hilang agar oxu bisa
        # memperbaiki fastfetch yang terhapus (check_updates menandainya).
        if ! command -v fastfetch >/dev/null 2>&1; then
            tahap "fastfetch" "mulai" "instal dari repo"
            if [[ "$DRY_RUN" -eq 1 ]]; then
                log "(dry-run) lewati fastfetch (repo)"
            else
                retry 3 "${INSTALL[@]}" fastfetch || die "pemasangan fastfetch gagal"
                command -v fastfetch >/dev/null || die "fastfetch tak ketemu setelah dipasang"
            fi
            tahap "fastfetch" "ok" "terpasang (repo)"
        fi
        return 0
    fi
    if command -v fastfetch >/dev/null; then
        local rec inst
        rec="$(read_state fastfetch.version)"
        if [[ "$rec" == "$FASTFETCH_VERSION" ]]; then
            log "fastfetch sudah mutakhir (.deb $rec)"
            return 0
        fi
        # Bandingkan versi dpkg agar repo yang sudah menyusul pin tak di-downgrade.
        inst="$(dpkg-query -W -f='${Version}' fastfetch 2>/dev/null)" || inst=""
        if [[ -n "$inst" ]] && dpkg --compare-versions "$inst" ge "$FASTFETCH_VERSION" 2>/dev/null; then
            log "fastfetch $inst >= pin $FASTFETCH_VERSION (repo), dibiarkan"
            return 0
        fi
        log "fastfetch ${inst:-tak-dikenal} < pin $FASTFETCH_VERSION -> cek repo"
    fi
    tahap "fastfetch" "mulai" "cek repo / fallback .deb upstream"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati fastfetch (.deb upstream bila repo tak punya)"
        return 0
    fi
    # Tampung dulu stdout-nya: grep -q langsung di pipa rawan SIGPIPE
    # (penulis mati lebih dulu -> pipefail gagal -> cabang salah).
    local tmp deb policy now
    tmp="$(new_tmpdir)"
    policy="$(apt-cache policy fastfetch 2>/dev/null)" || die "gagal baca info paket fastfetch"
    if grep -q "Candidate: (none)" <<<"$policy"; then
        log "fastfetch tak ada di repo -> unduh .deb upstream $FASTFETCH_VERSION (terpin)"
        deb="$tmp/fastfetch-${FASTFETCH_VERSION}-linux-amd64.deb"
        curl -fSL --retry 3 --retry-delay 2 --proto '=https' --proto-redir '=https' \
            "https://github.com/fastfetch-cli/fastfetch/releases/download/${FASTFETCH_VERSION}/fastfetch-linux-amd64.deb" \
            -o "$deb" || die "unduhan fastfetch gagal"
        log "verifikasi sha256 .deb fastfetch..."
        echo "${FASTFETCH_SHA256}  ${deb}" | sha256sum -c - \
            || die "checksum fastfetch tak cocok (unduhan rusak/disusupi?)"
        dpkg -i "$deb" || apt-get install -f -y || die "pemasangan fastfetch .deb gagal"
        rm -f "$deb"
        record_state fastfetch.version "$FASTFETCH_VERSION"
    else
        apt-get install -y fastfetch || die "pemasangan fastfetch gagal"
        rm -f "$(state_dir)/fastfetch.version" 2>/dev/null || true # kini milik repo
        now="$(dpkg-query -W -f='${Version}' fastfetch 2>/dev/null)" || now=""
        log "fastfetch ikut repo sistem (${now:-terpasang}); pin hanya untuk repo tanpa paket"
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
    local arsip tmp
    tmp="$(new_tmpdir)"
    arsip="$tmp/zig.tar.xz"
    curl -fSL --retry 3 --retry-delay 2 --proto '=https' --proto-redir '=https' \
        "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" \
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

# Biner OXWM resmi per distro (kosong = belum ada yang mengemas -> build source).
# Update 2026-10: Arch extra/Debian/Fedora belum ada; AUR hanya oxwm-git
# (tetap mengompilasi + butuh helper, jadi bukan jalan pintas). Isi nama paket
# di sini bila kelak tersedia - installer otomatis memakainya tanpa compile.
declare -A OXWM_BINPKG=(
    [arch]=""
    [debian]=""
    [fedora]=""
)

install_oxwm_binary() { # 0 bila biner repo terpasang; 1 bila tak tersedia
    local pkg="${OXWM_BINPKG[$DISTRO]:-}"
    [[ -n "$pkg" ]] || return 1
    if [[ "$REBUILD" -eq 0 ]] && command -v oxwm >/dev/null; then
        log "oxwm sudah ada, lewati"
        return 0
    fi
    tahap "oxwm" "mulai" "biner repo $pkg"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) ${INSTALL[*]} $pkg"
        return 0
    fi
    retry 3 "${INSTALL[@]}" "$pkg" || return 1
    command -v oxwm >/dev/null || return 1
    log "oxwm terpasang dari repo ($pkg) - tanpa compile"
    record_state oxwm.commit "repo:$pkg"
    tahap "oxwm" "ok" "biner repo $pkg"
}

install_oxwm() { # biner repo bila ada (cepat), fallback: bangun dari source
    if [[ "$REBUILD" -eq 0 && -x /usr/local/bin/oxwm ]]; then
        log "oxwm sudah terpasang, lewati (pakai --rebuild untuk bangun ulang)"
        return 0
    fi
    # OXWM_PIN bisa ditimpa via environment (--latest atau OXWM_PIN="" = HEAD
    # terbaru): validasi sebelum dipakai di dalam `su -c "..."` (injeksi shell
    # berjalan sebagai user target). Default: pin teruji (reproduksibel).
    if [[ -n "$OXWM_PIN" ]]; then
        [[ "$OXWM_PIN" =~ ^[0-9a-f]{40}$ ]] || die "OXWM_PIN tidak valid (harus SHA-1 40 digit heksa; kosongkan untuk HEAD terbaru)"
    fi
    [[ "$OXWM_REPO" != *"'"* ]] || die "repo mengandung kutip tunggal"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ -n "${OXWM_BINPKG[$DISTRO]:-}" ]]; then
            log "(dry-run) coba biner repo dulu, fallback build source"
        else
            log "(dry-run) lewati clone + build oxwm (pin ${OXWM_PIN:-HEAD})"
        fi
        tahap "oxwm" "ok" "terpasang di /usr/local/bin/oxwm"
        return 0
    fi
    # Jalur cepat: biner resmi (sekaligus lewati zig - hanya perlu untuk build).
    if install_oxwm_binary; then
        return 0
    fi
    log "bangun & pasang OXWM dari source ($OXWM_REPO)..."
    tahap "oxwm" "mulai" "zig build dari source (pin ${OXWM_PIN:-HEAD})"
    ensure_zig # compiler hanya dibutuhkan di jalur source
    local tmp build_dir
    tmp="$(new_tmpdir)"
    build_dir="$tmp/oxwm-build"
    [[ "$build_dir" != *"'"* ]] || die "path sementara mengandung kutip tunggal"
    # Pin ke komit teruji agar hasil dapat diulang; kosong = HEAD terbaru.
    # Clone sebagai pemilik repo agar tak kena dubious ownership bila
    # SUDO_USER terlibat.
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
    [[ -x /usr/local/bin/oxwm ]] || die "biner oxwm tak ketemu setelah build"
    local built
    built="$(git -C "$build_dir" rev-parse HEAD 2>/dev/null)" || built=""
    [[ -n "$built" ]] && record_state oxwm.commit "$built"
    rm -rf "$build_dir"
    tahap "oxwm" "ok" "terpasang di /usr/local/bin/oxwm"
}

# Warna bawaan suckless yang harus sudah terganti oleh sed tema. Bila
# upstream merombak config.def.h, sed meleset diam-diam - tangkap di sini.
ST_ORIG_COLORS=('"gray90"' '"black"' '"red3"' '"green3"' '"yellow3"' '"blue2"'
    '"magenta3"' '"cyan3"' '"gray50"' '"red"' '"green"' '"yellow"'
    '"#5c5cff"' '"magenta"' '"cyan"' '"white"' '"#cccccc"' '"#555555"')

check_st_theme() { # $1=config.def.h hasil sed, $2=tema, sisanya palet harapan (fg bg cur c0..c15)
    local f="$1" theme="$2"
    shift 2
    local block p
    block="$(awk '/static const char \*colorname/,/^\};/' "$f")" \
        || die "st-$theme: blok colorname tak ketemu (upstream merombak config.def.h?)"
    [[ -n "$block" ]] || die "st-$theme: blok colorname kosong (upstream merombak config.def.h?)"
    for p in "${ST_ORIG_COLORS[@]}"; do
        if grep -qF -- "$p" <<<"$block"; then
            die "st-$theme: pola bawaan $p masih ada setelah sed (upstream berubah?)"
        fi
    done
    local want
    for want in "$@"; do
        if ! grep -qF -- "$want" <<<"$block"; then
            die "st-$theme: warna harapan $want tak ketemu setelah sed"
        fi
    done
    grep -q "JetBrainsMono Nerd Font" "$f" \
        || die "st-$theme: font tak terganti (upstream berubah?)"
}

build_st() { # terminal st dari source suckless, 3 build bertema + dispatcher `st`
    # Repo distro tak konsisten menyediakan st (Arch bahkan tak punya), jadi
    # bangun dari source. Pola sed sama dengan modul Nix
    # (config.def.h: komentar dulu baru kembaran polosnya - urutan penting).
    # Sengaja TIDAK pakai biner repo (fedora:st, debian:stterm): st vanilla
    # tak bisa ganti warna saat runtime, jadi 3 varian tema mustahil;
    # build-nya pun hanya hitungan detik (satu file C, -j paralel).
    local repo="https://git.suckless.org/st"
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
    local tmp build_dir orig
    tmp="$(new_tmpdir)"
    build_dir="$tmp/st-build"
    if [[ -n "${SUDO_USER:-}" ]]; then
        su "$SUDO_USER" -c "git clone --depth 1 '$repo' '$build_dir'"
    else
        git clone --depth 1 "$repo" "$build_dir"
    fi
    # Simpan config murni sekali: reset via git rapuh bila root membangun di
    # repo milik user lain (dubious ownership) sehingga varian ikut tercemar.
    orig="$tmp/st-config.def.h.orig"
    cp "$build_dir/config.def.h" "$orig"
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
            cp "$orig" config.def.h
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
            # Gagal keras bila sed meleset (mis. upstream merombak config.def.h).
            check_st_theme config.def.h "$theme" "$fg" "$bg" "$cur" \
                "$c0" "$c1" "$c2" "$c3" "$c4" "$c5" "$c6" "$c7" \
                "$c8" "$c9" "$c10" "$c11" "$c12" "$c13" "$c14" "$c15"
            make -j"$jobs"
            install -m 0755 st "/usr/local/bin/st-${theme}"
            make clean >/dev/null 2>&1 || true
        ) || die "build st-$theme gagal"
    done
    # Verifikasi fail-loud: tiga varian harus benar-benar berbeda binernya.
    if [[ $(md5sum /usr/local/bin/st-tokyonight /usr/local/bin/st-gruvbox /usr/local/bin/st-catppuccin | awk '{print $1}' | sort -u | wc -l) -ne 3 ]]; then
        die "build st gagal: tiga varian biner identik (palet tercemar)"
    fi
    local st_built
    st_built="$(git -C "$build_dir" rev-parse HEAD 2>/dev/null)" || st_built=""
    [[ -n "$st_built" ]] && record_state st.commit "$st_built"
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

template_config_terminal() { # $1=config.lua $2=terminal - ganti referensi st + verifikasi keras
    local cfg="$1" term="$2" wiremix
    case "$term" in
        alacritty) wiremix="alacritty --class wiremix -e wiremix" ;;
        kitty)     wiremix="kitty --class wiremix wiremix" ;;
        ghostty)   wiremix="ghostty --x11-instance-name=wiremix -e wiremix" ;;
        *) die "templating terminal: terminal tak dikenal '$term'" ;;
    esac
    sed -i "s/^local terminal = \"st\"/local terminal = \"$term\"/" "$cfg"
    # wiremix harus jadi instance/class "wiremix" agar rule floating kena.
    sed -i "s/st -n wiremix -c wiremix -e wiremix/$wiremix/" "$cfg"
    if [[ "$term" == "kitty" ]]; then
        # kitty tak lagi punya opsi -e: program ditulis sebagai argumen posisional.
        sed -i "s/\bst -e /kitty /g" "$cfg"
    else
        sed -i "s/\bst -e /$term -e /g" "$cfg"
    fi
    grep -q "^local terminal = \"$term\"" "$cfg" \
        || die "templating $term: baris 'local terminal' tak terganti di $cfg"
    if grep -qE '(^|[^[:alnum:]_-])st -' "$cfg"; then
        die "templating $term: masih ada referensi perintah 'st' di $cfg (pola config.lua berubah?)"
    fi
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
    local fresh_config=0
    if [[ ! -f "$dest_home/.config/oxwm/config.lua" ]]; then
        cp "$src_dir/oxwm/config.lua" "$dest_home/.config/oxwm/config.lua"
        fresh_config=1
    fi
    [[ -f "$dest_home/.xinitrc" ]] || cp "$src_dir/xinitrc" "$dest_home/.xinitrc"
    mkdir -p "$dest_home/.config/oxwm/colors" "$dest_home/.config/oxwm/wallpapers" "$dest_home/.config/khal" "$dest_home/.config/fastfetch" "$dest_home/.calendars"
    local f
    for f in "$src_dir"/oxwm/colors/*.lua "$src_dir"/oxwm/wallpapers/* "$src_dir"/oxwm/*-status.sh "$src_dir"/oxwm/dunstrc-*; do
        [[ -f "$f" ]] || continue
        local rel="${f#"${src_dir}"/oxwm/}"
        # dunstrc + skrip status selalu disegarkan agar ikut tema/perbaikan;
        # sisanya hanya bila pengguna belum punya.
        case "$rel" in
            dunstrc-*|*-status.sh) cp "$f" "$dest_home/.config/oxwm/$rel" ;;
            *) [[ -f "$dest_home/.config/oxwm/$rel" ]] || cp "$f" "$dest_home/.config/oxwm/$rel" ;;
        esac
    done
    [[ -f "$dest_home/.config/khal/config" ]] || cp "$src_dir/khal/config" "$dest_home/.config/khal/config"
    [[ -f "$dest_home/.config/fastfetch/config.jsonc" ]] || cp "$src_dir/fastfetch/config.jsonc" "$dest_home/.config/fastfetch/config.jsonc"
    # Templat tema terminal selalu disegarkan (dipakai oxt); config live hanya
    # bila pengguna belum punya (edit manual tak ditimpa).
    local tf live live_theme=""
    for tf in "$src_dir"/alacritty/alacritty-*.toml "$src_dir"/kitty/kitty-*.conf "$src_dir"/ghostty/config-*; do
        [[ -f "$tf" ]] || continue
        cp "$tf" "$dest_home/.config/oxwm/$(basename "$tf")"
    done
    if [[ -f "$dest_home/.config/oxwm/theme" ]]; then
        live_theme="$(tr -d '[:space:]' < "$dest_home/.config/oxwm/theme" 2>/dev/null)"
    fi
    live_theme="${live_theme:-$THEME}"
    case "$TERMINAL" in
        alacritty) live="$dest_home/.config/alacritty/alacritty.toml"; tf="$dest_home/.config/oxwm/alacritty-$live_theme.toml" ;;
        kitty) live="$dest_home/.config/kitty/kitty.conf"; tf="$dest_home/.config/oxwm/kitty-$live_theme.conf" ;;
        ghostty) live="$dest_home/.config/ghostty/config"; tf="$dest_home/.config/oxwm/config-$live_theme" ;;
        *) live=""; tf="" ;;
    esac
    if [[ -n "$live" && ! -f "$live" && -f "$tf" ]]; then
        mkdir -p "$(dirname "$live")"
        cp "$tf" "$live"
        log "config $TERMINAL awal: tema $live_theme"
    fi
    if [[ "$THEME_SET" -eq 1 || ! -f "$dest_home/.config/oxwm/theme" ]]; then
        echo "$THEME" > "$dest_home/.config/oxwm/theme"
        log "tema aktif: $THEME (semua tema terpasang: tokyonight gruvbox catppuccin - ganti kapan saja via oxwm-theme)"
    else
        log "tema yang ada dipertahankan: $(cat "$dest_home/.config/oxwm/theme") (semua tema tetap terpasang)"
    fi
    # Templat terminal hanya untuk config baru (config lama tak pernah ditimpa).
    if [[ "$fresh_config" -eq 1 && "$TERMINAL" != "st" ]]; then
        template_config_terminal "$dest_home/.config/oxwm/config.lua" "$TERMINAL"
        log "config.lua ditemplat untuk terminal $TERMINAL"
    elif [[ "$fresh_config" -eq 0 && "$TERMINAL" != "st" ]]; then
        log "config lama dipertahankan (masih st); ubah manual baris 'local terminal' bila ingin $TERMINAL"
    fi
    # Semua yang ditulis root di home user harus dikembalikan ke pemiliknya
    # (dulu hanya oxwm + .xinitrc; khal/fastfetch/.calendars tertinggal root).
    local p
    for p in "$dest_home/.config/oxwm" "$dest_home/.config/khal" \
             "$dest_home/.config/fastfetch" "$dest_home/.config/alacritty" \
             "$dest_home/.config/kitty" "$dest_home/.config/ghostty" \
             "$dest_home/.calendars" \
             "$dest_home/.xinitrc" "$backup"; do
        [[ -e "$p" ]] && chown -R "$owner:$owner" "$p" 2>/dev/null || true
    done
    tahap "dotfiles" "ok" "backup: $backup"
}

# --- Pilihan interaktif (menu bernomor + deskripsi singkat) ---
# Semua menu punya default aman = perilaku lama; mode pipe/dry-run/--yes
# otomatis pakai default tanpa bertanya (stdin bukan tty).
match_choice() { # $1=jawaban $2=default, sisanya "value|..." -> echo value / gagal
    local ans="${1,,}" def="$2"
    shift 2
    ans="${ans//[[:space:]]/}"
    if [[ -z "$ans" ]]; then
        printf '%s' "$def"
        return 0
    fi
    local i=1 o val
    for o in "$@"; do
        val="${o%%|*}"
        if [[ "$ans" == "$i" || "$ans" == "${val,,}" ]]; then
            printf '%s' "$val"
            return 0
        fi
        i=$((i + 1))
    done
    return 1
}
prompt_choice() { # $1=judul $2=default, sisanya "value|Label|deskripsi" -> echo value
    local title="$1" def="$2"
    shift 2
    # Jangan pernah blok: dry-run/--yes/otomatis/pipe langsung default.
    if [[ "$DRY_RUN" -eq 1 || "$ASSUME_YES" -eq 1 || "${OXWM_MENU_AUTO:-0}" -eq 1 ]] || [[ ! -t 0 ]]; then
        echo "(otomatis) $title -> $def" >&2
        printf '%s' "$def"
        return 0
    fi
    local i=1 o val lab desc ans picked
    {
        echo "$title:"
        for o in "$@"; do
            val="${o%%|*}"; lab="${o#*|}"; lab="${lab%%|*}"; desc="${o#*|*|}"
            if [[ "$val" == "$def" ]]; then
                echo "  $i) $lab (bawaan)"
            else
                echo "  $i) $lab"
            fi
            [[ -n "$desc" && "$desc" != "$o" ]] && echo "     $desc"
            i=$((i + 1))
        done
    } >&2
    while true; do
        read -rp "Pilihan [$def]: " ans >&2 || ans=""
        if picked="$(match_choice "$ans" "$def" "$@")"; then
            printf '%s' "$picked"
            return 0
        fi
        echo "tidak valid - isi nomor atau nama opsi." >&2
    done
}

# --- Sesi OXWM: pakai display manager bila ada, autologin tty1 bila tidak ---
# Selalu berdampingan dengan DE/WM yang sudah ada (tak ada opsi hapus).
repo_has_pkg() { # $1=paket -> 0 bila ada di repo (read-only; best-effort)
    case "$DISTRO" in
        arch) pacman -Si "$1" >/dev/null 2>&1 ;;
        debian) apt-cache show "$1" >/dev/null 2>&1 ;;
        fedora) dnf info "$1" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}
# Display manager populer (nama paket sama semua distro kecuali gdm Debian).
DM_KNOWN=(sddm gdm lightdm)
dm_pkg() { # $1=nama DM -> paket distro aktif
    if [[ "$1" == "gdm" && "$DISTRO" == "debian" ]]; then printf 'gdm3'; else printf '%s' "$1"; fi
}
dm_unit() { # $1=nama DM -> nama unit systemd
    if [[ "$1" == "gdm" && "$DISTRO" == "debian" ]]; then printf 'gdm3'; else printf '%s' "$1"; fi
}
TERM_KNOWN=(st alacritty kitty ghostty)
systemd_running() { [[ -d /run/systemd/system ]]; }

xsession_file() { printf '%s' "${OXWM_XSESSION_DIR:-/usr/share/xsessions}/oxwm.desktop"; }
getty_dropin_path() { printf '%s' "${OXWM_GETTY_DROPIN:-/etc/systemd/system/getty@tty1.service.d/autologin.conf}"; }

dm_from_units() { # $1=teks `systemctl list-unit-files` -> nama DM atau "" (murni, untuk tes)
    local units="${1:-}" cand line state
    # Pass 1: yang enabled (termasuk enabled-runtime) didahulukan -
    # DM terpasang-tapi-disabled tidak boleh mengalahkan yang aktif.
    for cand in "${DM_CANDIDATES[@]}"; do
        while IFS= read -r line; do
            [[ "$line" == "${cand}.service "* || "$line" == "${cand}.service	"* ]] || continue
            state="${line#"${cand}".service}"
            if [[ "$state" == *enabled* ]]; then
                printf '%s' "$cand"
                return 0
            fi
        done <<<"$units"
    done
    # Pass 2: terpasang dalam keadaan apa pun (disabled/static/alias/dll).
    for cand in "${DM_CANDIDATES[@]}"; do
        while IFS= read -r line; do
            [[ "$line" == "${cand}.service "* || "$line" == "${cand}.service	"* ]] || continue
            printf '%s' "$cand"
            return 0
        done <<<"$units"
    done
    return 0
}

# SC2120 non-isu: argumen opsional memang untuk unit-test (path palsu);
# produksi memanggil tanpa argumen (-> path sistem).
# shellcheck disable=SC2120
dm_from_symlink() { # [$1=path display-manager.service] -> nama DM atau "" (tak pernah gagal)
    local link="${1:-/etc/systemd/system/display-manager.service}" target base cand
    [[ -L "$link" ]] || return 0
    target="$(readlink "$link" 2>/dev/null)" || return 0
    [[ -n "$target" ]] || return 0
    base="$(basename "$target")"
    base="${base%.service}"
    [[ -n "$base" && "$base" != "$target" ]] || return 0
    for cand in "${DM_CANDIDATES[@]}"; do
        if [[ "$base" == "$cand" ]]; then
            printf '%s' "$cand"
            return 0
        fi
    done
    # Symlink menunjuk DM di luar daftar (mis. cosmic-greeter): tetap
    # dianggap "ada DM" agar tak ditimpa autologin.
    printf '%s' "$base"
}

detect_dm() { # cetak nama DM atau "" - hanya baca, aman untuk --dry-run; tak pernah gagal
    # Override untuk tes/otomatisasi: OXWM_DM diset (bahkan kosong = paksa "tak ada DM").
    if [[ "${OXWM_DM+set}" == "set" ]]; then
        printf '%s' "$OXWM_DM"
        return 0
    fi
    local dm="" cand units=""
    dm="$(dm_from_symlink)" || true
    if [[ -n "$dm" ]]; then
        printf '%s' "$dm"
        return 0
    fi
    if command -v systemctl >/dev/null 2>&1; then
        for cand in "${DM_CANDIDATES[@]}"; do
            if systemctl is-active --quiet "${cand}.service" 2>/dev/null; then
                printf '%s' "$cand"
                return 0
            fi
        done
        units="$(systemctl list-unit-files --no-legend 2>/dev/null)" || units=""
        if [[ -n "$units" ]]; then
            dm="$(dm_from_units "$units")" || true
            if [[ -n "$dm" ]]; then
                printf '%s' "$dm"
                return 0
            fi
        fi
    fi
    # Fallback tanpa systemd (container/chroot): biner DM terpasang?
    for cand in "${DM_CANDIDATES[@]}"; do
        if [[ "$cand" == "gdm3" ]]; then
            if command -v gdm3 >/dev/null 2>&1; then printf '%s' gdm3; return 0; fi
        elif command -v "$cand" >/dev/null 2>&1; then
            printf '%s' "$cand"
            return 0
        fi
    done
    return 0
}

install_xsession_entry() { # daftarkan OXWM agar bisa dipilih di DM mana pun
    local f
    f="$(xsession_file)"
    mkdir -p "$(dirname "$f")"
    cat > "$f" <<'EOF'
[Desktop Entry]
Name=OXWM
Comment=Dynamic tiling window manager (OXWM)
Exec=/usr/local/bin/oxwm
TryExec=/usr/local/bin/oxwm
Type=Application
DesktopNames=OXWM
EOF
    chmod 0644 "$f"
}

enable_hw_services() { # $1=owner - layanan audio/bt/jaringan/daya + grup perangkat
    local owner="$1" svc g
    for svc in bluetooth NetworkManager power-profiles-daemon; do
        systemctl enable --now "$svc" 2>/dev/null || log "peringatan: enable $svc gagal"
    done
    systemctl --global enable pipewire.socket pipewire-pulse.socket 2>/dev/null || true
    for g in audio video input bluetooth; do
        getent group "$g" >/dev/null 2>&1 && usermod -aG "$g" "$owner" 2>/dev/null || true
    done
}

setup_autologin() { # $1=owner - drop-in getty berpenanda (aman dihapus bila pindah ke DM)
    local owner="$1" dropin
    dropin="$(getty_dropin_path)"
    mkdir -p "$(dirname "$dropin")"
    cat > "$dropin" <<EOF
# oxwm-installer: autologin $owner di tty1 (dihapus otomatis bila pindah ke display manager)
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $owner --noclear %I \$TERM
EOF
    if systemd_running; then
        systemctl daemon-reload 2>/dev/null || log "peringatan: daemon-reload gagal (lanjut tanpa reload)"
    else
        log "peringatan: systemd tak jalan (container/chroot?) - drop-in tertulis, aktif saat boot normal"
    fi
}

remove_autologin() { # hapus drop-in HANYA bila buatan kita (berpenanda); config user tak disentuh
    local dropin
    dropin="$(getty_dropin_path)"
    [[ -f "$dropin" ]] || return 0
    if grep -q "oxwm-installer" "$dropin" 2>/dev/null; then
        rm -f "$dropin"
        log "autologin tty1 buatan installer dihapus ($dropin)"
        if systemd_running; then
            systemctl daemon-reload 2>/dev/null || true
        fi
    else
        log "peringatan: $dropin bukan buatan installer - dibiarkan"
    fi
}

ensure_startx_block() { # $1=profile - tambah blok startx bila belum ada (idempoten)
    local profile="$1"
    touch "$profile" 2>/dev/null || return 0
    if ! grep -q "oxwm-installer: startx otomatis" "$profile" 2>/dev/null; then
        cat >> "$profile" <<'EOF'

# oxwm-installer: startx otomatis di tty1
if [ -z "$DISPLAY" ] && [ "$(tty)" = /dev/tty1 ]; then
    exec startx
fi
EOF
    fi
}

remove_startx_block() { # $1=profile - buang blok startx buatan kita (pindah ke DM)
    local profile="$1"
    [[ -f "$profile" ]] || return 0
    grep -q "oxwm-installer: startx otomatis" "$profile" 2>/dev/null || return 0
    sed -i '/# oxwm-installer: startx otomatis/,/^fi$/d' "$profile" 2>/dev/null || true
    log "blok startx otomatis dihapus dari $profile (kini via display manager)"
}

resolve_choices() { # tentukan SESSION_REQ/TERMINAL via flag atau menu
    OLD_DM="$(detect_dm)" || true
    tahap "pilihan" "mulai" "sesi/terminal"

    # Sesi login: flag menang; menu hanya bila BELUM ada display manager
    # (bila DM sudah ada, pakai itu - perilaku lama, tanpa bertanya).
    if [[ "${SESSION_SET:-0}" -eq 1 ]]; then
        log "sesi: $SESSION_REQ (flag)"
    elif [[ -n "$OLD_DM" ]]; then
        SESSION_REQ="auto"
        log "DM terdeteksi ($OLD_DM): pakai DM, tanpa menu sesi"
    else
        local opts=("autologin|Autologin tty1|Tanpa display manager: konsol otomatis + startx.") dm
        for dm in "${DM_KNOWN[@]}"; do
            if repo_has_pkg "$(dm_pkg "$dm")"; then
                opts+=("dm:$dm|DM $dm|Pasang $dm dari repo, jadikan pintu login.")
            else
                log "DM $dm tak ada di repo $DISTRO - disembunyikan"
            fi
        done
        SESSION_REQ="$(prompt_choice "Belum ada display manager. Sesi login OXWM" autologin "${opts[@]}")"
    fi
    if [[ "$TERMINAL_SET" -eq 1 ]]; then
        log "terminal: $TERMINAL (flag)"
    else
        local topts=("st|st|Build dari source, super ringan; 3 varian warna ikut tema (oxt).") t
        for t in alacritty kitty ghostty; do
            if repo_has_pkg "$t"; then
                case "$t" in
                    alacritty) topts+=("alacritty|alacritty|GPU-accelerated, cepat; warna ikut tema (oxt), terminal baru.") ;;
                    kitty) topts+=("kitty|kitty|GPU, fitur kaya (tab, gambar); warna ikut tema (oxt), reload otomatis.") ;;
                    ghostty) topts+=("ghostty|ghostty|GPU modern, default bagus; warna ikut tema (oxt), reload otomatis.") ;;
                esac
            else
                log "terminal $t tak ada di repo $DISTRO - disembunyikan"
            fi
        done
        TERMINAL="$(prompt_choice "Terminal bawaan" st "${topts[@]}")"
    fi
    tahap "pilihan" "ok" "sesi=$SESSION_REQ terminal=$TERMINAL"
}
disable_old_dm() { # $1=unit baru/"" - matikan DM lama (tanpa --now: aman sesi jalan)
    local newunit="${1:-}" oldunit=""
    [[ -n "$OLD_DM" ]] && oldunit="$OLD_DM"
    [[ -n "$oldunit" && "$oldunit" != "$newunit" ]] || return 0
    log "matikan DM lama ($oldunit) - berlaku setelah reboot"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) systemctl disable $oldunit"
    else
        systemctl disable "$oldunit" 2>/dev/null || log "peringatan: disable $oldunit gagal"
    fi
}
install_session_stack() { # pasang DM pilihan + enable; matikan yang lama
    local kind="${SESSION_REQ%%:*}" name="${SESSION_REQ#*:}" unit=""
    case "$kind" in
        dm)
            unit="$(dm_unit "$name")"
            tahap "sesi-pilih" "mulai" "DM $name"
            if [[ "$DRY_RUN" -eq 1 ]]; then
                log "(dry-run) pasang + enable DM $name"
            else
                retry 3 "${INSTALL[@]}" "$(dm_pkg "$name")" \
                    || die "DM $name tak tersedia di repo $DISTRO"
                systemctl enable "$unit" 2>/dev/null || log "peringatan: enable $unit gagal"
            fi
            disable_old_dm "$unit"
            tahap "sesi-pilih" "ok" "DM $name" ;;
        autologin)
            disable_old_dm ""
            log "sesi: autologin (DM lama dimatikan bila ada)" ;;
        *) log "sesi: $SESSION_REQ (otomatis, tak ada yang dipasang)" ;;
    esac
}
install_terminal_choice() { # pasang terminal pilihan (st = build 3 tema)
    tahap "terminal" "mulai" "$TERMINAL"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ "$TERMINAL" == "st" ]]; then
            log "(dry-run) build st 3 tema dari source"
        else
            log "(dry-run) ${INSTALL[*]} $TERMINAL"
        fi
        return 0
    fi
    if [[ "$TERMINAL" == "st" ]]; then
        build_st
    else
        if command -v "$TERMINAL" >/dev/null 2>&1; then
            log "$TERMINAL sudah terpasang"
        else
            retry 3 "${INSTALL[@]}" "$TERMINAL" \
                || die "terminal $TERMINAL tak tersedia di repo $DISTRO"
            command -v "$TERMINAL" >/dev/null 2>&1 \
                || die "terminal $TERMINAL tak ketemu setelah dipasang"
        fi
    fi
    record_state terminal "$TERMINAL"
    tahap "terminal" "ok" "$TERMINAL"
}
enable_services() { # jalankan OXWM: via DM bila ada, atau autologin tty1+startx bila tak ada
    local owner="${SUDO_USER:-$(whoami)}"
    valid_user "$owner" || die "nama user tidak valid: '$owner'"
    local profile
    profile="$(user_home "$owner")/.bash_profile"
    log "siapkan sesi OXWM untuk $owner..."
    tahap "layanan" "mulai" "sesi OXWM"
    local dm=""
    dm="$(detect_dm)" || true
    if [[ "$FORCE_AUTOLOGIN" -eq 1 ]]; then
        [[ -n "$dm" ]] && log "--force-autologin: abaikan DM terdeteksi ($dm)"
        dm=""
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) pasang $(xsession_file)"
        if [[ -n "$dm" ]]; then
            log "(dry-run) DM terdeteksi ($dm): pakai DM, tanpa autologin"
        elif [[ "$NO_AUTOLOGIN" -eq 1 ]]; then
            log "(dry-run) tanpa DM + --no-autologin: lewati getty/startx (login manual)"
        else
            log "(dry-run) tanpa DM: autologin tty1 + startx otomatis"
        fi
        return 0
    fi

    install_xsession_entry

    if [[ -n "$dm" ]]; then
        log "display manager terdeteksi ($dm): pakai DM, OXWM tersedia sebagai sesi"
        if systemd_running; then
            systemctl enable "${dm}.service" 2>/dev/null \
                || log "peringatan: enable $dm gagal (mungkin sudah enabled via display-manager.service)"
        fi
        enable_hw_services "$owner"
        remove_autologin
        remove_startx_block "$profile"
        chown "$owner:$owner" "$profile" 2>/dev/null || true
        SESSION_MODE="dm:$dm"
        tahap "layanan" "ok" "sesi DM: $dm"
        return 0
    fi

    if [[ "$NO_AUTOLOGIN" -eq 1 ]]; then
        log "tanpa display manager + --no-autologin: lewati autologin (login manual, lalu startx)"
        enable_hw_services "$owner"
        SESSION_MODE="manual"
        tahap "layanan" "ok" "tanpa autologin (manual)"
        return 0
    fi

    # Tanpa display manager: autologin getty di tty1 + startx otomatis.
    log "tanpa display manager: autologin konsol tty1 + startx otomatis"
    setup_autologin "$owner"
    enable_hw_services "$owner"
    ensure_startx_block "$profile"
    chown "$owner:$owner" "$profile" 2>/dev/null || true
    SESSION_MODE="autologin"
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
    if nerd_terpasang "$owner" && [[ "$(read_state nerdfont.version)" == "$NERDFONT_VERSION" ]]; then
        log "font JetBrainsMono Nerd sudah mutakhir ($NERDFONT_VERSION)"
        return 0
    fi
    local target arsip tmp
    target="$(user_home "$owner")/.local/share/fonts"
    log "font Nerd belum ada -> unduh JetBrainsMono $NERDFONT_VERSION (terpin) ke $target"
    tahap "font" "mulai" "JetBrainsMono $NERDFONT_VERSION (tar.xz)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati unduhan font"
    else
        tmp="$(new_tmpdir)"
        arsip="$tmp/JetBrainsMono.tar.xz"
        mkdir -p "$target"
        curl -fSL --retry 3 --retry-delay 2 --proto '=https' --proto-redir '=https' \
            "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERDFONT_VERSION}/JetBrainsMono.tar.xz" \
            -o "$arsip" || die "unduhan font gagal"
        log "verifikasi sha256 arsip font..."
        echo "${NERDFONT_SHA256}  ${arsip}" | sha256sum -c - \
            || die "checksum font tak cocok (unduhan rusak/disusupi?)"
        tar -xJf "$arsip" -C "$target" || die "ekstraksi font gagal"
        rm -f "$arsip"
        compgen -G "$target/*.ttf" >/dev/null || die "tak ada .ttf di $target setelah ekstraksi"
        fc-cache -f "$target" >/dev/null 2>&1 || true
        chown -R "$owner:$owner" "$target" 2>/dev/null || true
        nerd_terpasang "$owner" \
            || die "font Nerd tak terdeteksi setelah dipasang"
        record_state nerdfont.version "$NERDFONT_VERSION"
    fi
    tahap "font" "ok" "font Nerd terpasang"
}

# --- Pembaruan mandiri (oxu / oxwm-update) ---
# Installer mengingat versi terpasang di state dir; update = bandingkan
# dengan pin/HEAD terbaru, bangun ulang hanya yang outdated.
state_dir() { printf '%s' "${OXWM_STATE_DIR:-/var/lib/oxwm-installer}"; }
record_state() { # $1=nama $2=nilai - catat versi terpasang (lewati saat dry-run)
    [[ "$DRY_RUN" -eq 1 ]] && return 0
    local d
    d="$(state_dir)"
    mkdir -p "$d" 2>/dev/null || return 0
    printf '%s\n' "$2" > "$d/$1" 2>/dev/null || true
}
read_state() { # $1=nama -> nilai tanpa spasi, atau "" (tak pernah gagal)
    local f
    f="$(state_dir)/$1"
    [[ -f "$f" ]] || return 0
    tr -d '[:space:]' < "$f" 2>/dev/null || true
}
staleness() { # $1=terpasang $2=tersedia -> 0 bila sama persis dan tak kosong
    [[ -n "${1:-}" && "${1:-}" == "${2:-}" ]]
}
report_line() { # $1=nama $2=terpasang $3=tersedia -> "nama|a|b|status"
    if [[ -z "${2:-}" || -z "${3:-}" ]]; then
        printf '%s|%s|%s|tak-diketahui\n' "$1" "${2:-?}" "${3:-?}"
    elif staleness "$2" "$3"; then
        printf '%s|%s|%s|mutakhir\n' "$1" "$2" "$3"
    else
        printf '%s|%s|%s|outdated\n' "$1" "$2" "$3"
    fi
}
update_needed() { # $1=nama $2=laporan check_updates -> 0 bila outdated/tak-diketahui
    local st
    st="$(awk -F'|' -v n="$1" '$1==n{print $4}' <<<"$2")"
    [[ "$st" == "outdated" || "$st" == "tak-diketahui" ]]
}
upstream_head() { # $1=url repo git -> SHA HEAD atau "" (butuh git + jaringan)
    git ls-remote "$1" HEAD 2>/dev/null | awk '{print $1}'
}
check_updates() { # laporan "nama|terpasang|tersedia|status" per baris (butuh jaringan)
    local inst avail zv
    # oxwm: pin installer, atau HEAD bila --latest.
    inst="$(read_state oxwm.commit)"
    if [[ "$inst" == repo:* ]]; then
        printf 'oxwm|%s|repo-sistem|repo-sistem\n' "$inst"
    else
        if [[ "$LATEST" -eq 1 ]]; then avail="$(upstream_head "$OXWM_REPO")"; else avail="$OXWM_PIN"; fi
        report_line oxwm "$inst" "$avail"
    fi
    # st: suckless tanpa tag - satu-satunya acuan adalah HEAD.
    report_line st "$(read_state st.commit)" "$(upstream_head "https://git.suckless.org/st")"
    # zig: versi live (milik repo distro yang lebih baru dari pin pun terdeteksi).
    if command -v zig >/dev/null 2>&1; then zv="$(zig version 2>/dev/null || true)"; else zv=""; fi
    report_line zig "${zv:-}" "$ZIG_VERSION"
    # font + fastfetch: hanya yang dipasang via fallback pin yang bisa dilacak.
    report_line nerdfont "$(read_state nerdfont.version)" "$NERDFONT_VERSION"
    inst="$(read_state fastfetch.version)"
    if [[ -z "$inst" ]]; then
        if command -v fastfetch >/dev/null 2>&1; then
            printf 'fastfetch|repo-sistem|repo-sistem|repo-sistem\n'
        else
            printf 'fastfetch|?|%s|tak-diketahui\n' "$FASTFETCH_VERSION"
        fi
    else
        report_line fastfetch "$inst" "$FASTFETCH_VERSION"
    fi
}
print_updates() { # $1=laporan -> baris manusiawi "nama: status (a -> b)"
    local name a b st
    while IFS='|' read -r name a b st; do
        [[ -n "$name" ]] || continue
        printf '%-10s %-13s (%s -> %s)\n' "$name" "$st" "$a" "$b"
    done <<<"$1"
    return 0
}
do_self_update() { # bangun ulang hanya komponen outdated (state vs pin/HEAD)
    log "cek pembaruan komponen..."
    tahap "self-update" "mulai" "cek"
    local report n_tindakan=0
    report="$(check_updates)"
    print_updates "$report" | while IFS= read -r line; do log "  $line"; done || true
    local name _a _b st
    while IFS='|' read -r name _a _b st; do
        [[ -n "$name" ]] || continue
        if [[ "$st" == "outdated" || "$st" == "tak-diketahui" ]]; then
            n_tindakan=$((n_tindakan + 1))
        fi
    done <<<"$report"
    if [[ "$n_tindakan" -eq 0 ]]; then
        log "semua komponen mutakhir"
        tahap "self-update" "ok" "mutakhir"
        return 0
    fi
    if [[ "$DRY_RUN" -eq 0 && "$ASSUME_YES" -eq 0 ]]; then
        if [[ ! -t 0 ]]; then
            echo "Ringkasan: $n_tindakan komponen outdated/tak-dikenal, bangun ulang yang itu saja." >&2
            pipe_grace
        else
            echo "$report" | print_updates
            read -rp "Terapkan $n_tindakan pembaruan? [y/N] " jawab
            [[ "$jawab" == "y" || "$jawab" == "Y" ]] || die "dibatalkan pengguna"
        fi
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) lewati penerapan $n_tindakan pembaruan"
        return 0
    fi
    REBUILD=1 # di titik ini semua yang dibangun memang perlu dibangun ulang
    # Terminal ikut state (bawaan st untuk instalasi lama); --terminal menimpa.
    if [[ "$TERMINAL_SET" -eq 0 ]]; then
        local st_rec
        st_rec="$(read_state terminal)"
        TERMINAL="${st_rec:-st}"
    fi
    update_needed oxwm "$report" && install_oxwm
    if [[ "$TERMINAL" == "st" ]]; then
        update_needed st "$report" && build_st
    else
        install_terminal_choice
    fi
    update_needed nerdfont "$report" && ensure_nerdfont
    update_needed fastfetch "$report" && ensure_fastfetch
    update_needed zig "$report" && ensure_zig
    # Helper + skrip status/dunstrc selalu disegarkan (murah dan aman).
    install_helpers
    deploy_dotfiles
    tahap "self-update" "ok" "$n_tindakan komponen diperbarui"
}

remove_if_ours() { # $1=file $2=penanda -> hapus hanya bila buatan installer
    local f="$1" mark="$2"
    [[ -e "$f" || -L "$f" ]] || { log "tak ada: $f"; return 0; }
    if grep -qF -- "$mark" "$f" 2>/dev/null; then
        run_or_dry rm -f "$f"
    else
        log "peringatan: $f bukan buatan installer - dibiarkan"
    fi
}

do_uninstall() { # hapus biner + sesi buatan installer; dotfiles user dibiarkan
    local owner="${SUDO_USER:-$(whoami)}"
    valid_user "$owner" || die "nama user tidak valid: '$owner'"
    local home profile
    home="${TARGET_HOME:-$(user_home "$owner")}"
    profile="$home/.bash_profile"
    log "hapus instalasi OXWM..."
    tahap "uninstall" "mulai" "bersih-bersih"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "(dry-run) hapus biner oxwm/st/helpers + oxu + state pembaruan + sesi (dotfiles dibiarkan)"
        return 0
    fi
    # Bindir + lokasi zig bisa di-override (uji fungsi memakai dir temp agar
    # tak pernah menyentuh /usr/local/bin + /opt sungguhan).
    local bindir="${OXWM_BIN_DIR:-/usr/local/bin}" zigdir="${OXWM_ZIG_DIR:-/opt/zig}"
    # Biner bernama unik buatan installer (tak dipakai paket distro).
    local f
    for f in "$bindir"/oxwm \
             "$bindir"/st-tokyonight "$bindir"/st-gruvbox "$bindir"/st-catppuccin \
             "$bindir"/oxt "$bindir"/oxu "$bindir"/oxwm-update \
             "$bindir"/oxwm-theme "$bindir"/dmenu-themed; do
        run_or_dry rm -f "$f"
    done
    # Nama yang menimpa biner sistem: hanya bila wrapper buatan kita,
    # agar dmenu/dunst/st asli kembali dipakai setelahnya.
    remove_if_ours "$bindir/st" "Dispatcher tema st"
    remove_if_ours "$bindir/dmenu_run" "bertema oxwm"
    remove_if_ours "$bindir/dunst" "bertema oxwm"
    # zig tarball buatan kita (symlink -> /opt/zig): kembalikan bila begitu.
    if [[ "$(readlink "$bindir/zig" 2>/dev/null)" == "$zigdir/zig" ]]; then
        run_or_dry rm -f "$bindir/zig"
        run_or_dry rm -rf "$zigdir"
    else
        log "zig dibiarkan (bukan tarball installer)"
    fi
    # State pembaruan (dibaca oxu: commit/versi terpasang) ikut dibuang.
    run_or_dry rm -rf "$(state_dir)"
    run_or_dry rm -f "$(xsession_file)"
    remove_autologin
    remove_startx_block "$profile"
    chown "$owner:$owner" "$profile" 2>/dev/null || true
    log "dotfiles dibiarkan: $home/.config/oxwm (hapus manual bila tak perlu)"
    tahap "uninstall" "ok" "selesai"
}

finish() {
    case "$SESSION_MODE" in
        dm:*) log "selesai. reboot: pilih sesi OXWM di display manager (${SESSION_MODE#dm:}), lalu login." ;;
        manual) log "selesai. login manual, lalu jalankan startx untuk masuk OXWM." ;;
        *) log "selesai. reboot: login konsol otomatis di tty1 lalu startx jalan sendiri ke OXWM." ;;
    esac
    log "log lengkap: $LOG_FILE"
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1; shift ;;
            --yes) ASSUME_YES=1; shift ;;
            --rebuild) REBUILD=1; shift ;;
            --latest) LATEST=1; shift ;;
            --no-update) NO_UPDATE=1; shift ;;
            --uninstall) UNINSTALL=1; shift ;;
            --self-update) SELF_UPDATE=1; shift ;;
            --check) CHECK_ONLY=1; shift ;;
            --session)
                [[ -n "${2:-}" ]] || { echo "opsi --session butuh nilai (auto|autologin)"; exit 2; }
                [[ "$SESSION_SET" -eq 0 ]] || { echo "opsi sesi ganda (--dm/--session/--force-autologin/--no-autologin)" >&2; exit 2; }
                case "$2" in
                    auto|autologin) SESSION_REQ="$2" ;;
                    *) echo "sesi tidak dikenal: $2 (pilih: auto|autologin; DM via --dm)"; exit 2 ;;
                esac
                SESSION_SET=1; shift 2 ;;
            --dm)
                [[ -n "${2:-}" ]] || { echo "opsi --dm butuh nilai (sddm|gdm|lightdm)"; exit 2; }
                [[ "$SESSION_SET" -eq 0 ]] || { echo "opsi sesi ganda (--dm/--session/--force-autologin/--no-autologin)" >&2; exit 2; }
                [[ " ${DM_KNOWN[*]} " == *" $2 "* ]] || { echo "DM tidak dikenal: $2 (pilih: ${DM_KNOWN[*]})"; exit 2; }
                SESSION_REQ="dm:$2"; SESSION_SET=1; shift 2 ;;
            --terminal)
                [[ -n "${2:-}" ]] || { echo "opsi --terminal butuh nilai (st|alacritty|kitty|ghostty)"; exit 2; }
                [[ " ${TERM_KNOWN[*]} " == *" $2 "* ]] || { echo "terminal tidak dikenal: $2 (pilih: ${TERM_KNOWN[*]})"; exit 2; }
                TERMINAL="$2"; TERMINAL_SET=1; shift 2 ;;
            --force-autologin) FORCE_AUTOLOGIN=1; shift ;;
            --no-autologin) NO_AUTOLOGIN=1; shift ;;
            --theme=*) THEME="${1#--theme=}"; THEME_SET=1; shift ;;
            --theme)
                [[ -n "${2:-}" ]] || { echo "opsi --theme butuh nilai (tokyonight|gruvbox|catppuccin)"; exit 2; }
                THEME="$2"; THEME_SET=1; shift 2 ;;
            --version) echo "oxwm-installer $VERSION"; exit 0 ;;
            --help) usage; exit 0 ;;
            *) echo "opsi tidak dikenal: $1 (lihat --help)"; exit 2 ;;
        esac
    done
    if [[ "$FORCE_AUTOLOGIN" -eq 1 && "$NO_AUTOLOGIN" -eq 1 ]]; then
        echo "--force-autologin dan --no-autologin saling bertentangan" >&2
        exit 2
    fi
    # Flag lama dipetakan ke sesi baru (tetap didukung).
    if [[ "$FORCE_AUTOLOGIN" -eq 1 ]]; then
        [[ "$SESSION_SET" -eq 0 ]] || { echo "opsi sesi ganda (--dm/--session/--force-autologin/--no-autologin)" >&2; exit 2; }
        SESSION_REQ="autologin"; SESSION_SET=1
    fi
    if [[ "$NO_AUTOLOGIN" -eq 1 ]]; then
        [[ "$SESSION_SET" -eq 0 ]] || { echo "opsi sesi ganda (--dm/--session/--force-autologin/--no-autologin)" >&2; exit 2; }
        SESSION_REQ="manual"; SESSION_SET=1
    fi
    if [[ "$UNINSTALL" -eq 1 && ( "$SELF_UPDATE" -eq 1 || "$CHECK_ONLY" -eq 1 ) ]]; then
        echo "--uninstall tidak bisa digabung --self-update/--check" >&2
        exit 2
    fi
    case "$THEME" in
        t|tokyonight) THEME=tokyonight ;;
        g|gruvbox) THEME=gruvbox ;;
        c|catppuccin) THEME=catppuccin ;;
        *) echo "tema tidak dikenal: $THEME (pilih: t/g/c)"; exit 2 ;;
    esac
    [[ "$REF" =~ ^[A-Za-z0-9._/-]+$ ]] || die "OXWM_REF tidak valid: '$REF'"
    [[ "$REF" != *..* ]] || die "OXWM_REF tidak boleh mengandung '..': '$REF'"
    [[ -z "${OXWM_LOG_DIR:-}" || "$OXWM_LOG_DIR" == /* ]] || die "OXWM_LOG_DIR harus path absolut"
    check_arch
    if [[ "$LATEST" -eq 1 ]]; then
        OXWM_PIN=""
    fi
    if [[ -n "$OXWM_PIN" ]]; then
        [[ "$OXWM_PIN" =~ ^[0-9a-f]{40}$ ]] || die "OXWM_PIN tidak valid (harus SHA-1 40 digit heksa; kosongkan untuk HEAD terbaru)"
    fi
    if [[ "$CHECK_ONLY" -eq 1 ]]; then
        # Cek versi tanpa root/distro: state lokal + ls-remote (butuh jaringan).
        print_updates "$(check_updates)"
        return 0
    fi
    init_log
    trap cleanup_tmpdirs EXIT
    trap 'on_err "$?" "$BASH_COMMAND" "${BASH_LINENO[0]}"' ERR
    log "========== oxwm-installer mulai (dry-run=$DRY_RUN) =========="
    if [[ "$LATEST" -eq 1 ]]; then
        log "catatan: --latest, OXWM dibangun dari HEAD terbaru (tak reproduksibel)"
    fi
    check_root
    if [[ "$DRY_RUN" -eq 0 ]]; then
        acquire_lock
    fi
    if [[ "$UNINSTALL" -eq 1 ]]; then
        if [[ "$DRY_RUN" -eq 0 && "$ASSUME_YES" -eq 0 ]]; then
            if [[ ! -t 0 ]]; then
                echo "Ringkasan: hapus biner + sesi OXWM buatan installer (dotfiles dibiarkan)." >&2
                pipe_grace
            else
                read -rp "Hapus instalasi OXWM? [y/N] " jawab
                [[ "$jawab" == "y" || "$jawab" == "Y" ]] || die "dibatalkan pengguna"
            fi
        fi
        do_uninstall
        log "log lengkap: $LOG_FILE"
        return 0
    fi
    detect_distro
    if [[ "$SELF_UPDATE" -eq 1 ]]; then
        # Pembaruan selektif: tanpa upgrade sistem/paket, tanpa utak-atik sesi.
        resolve_repo_dir
        do_self_update
        log "log lengkap: $LOG_FILE"
        return 0
    fi
    tahap "mulai" "ok" "instalasi OXWM dimulai (distro=$DISTRO dry-run=$DRY_RUN)"
    resolve_choices
    confirm
    resolve_repo_dir
    system_update
    install_packages
    install_session_stack
    install_terminal_choice
    ensure_fastfetch
    ensure_nerdfont
    install_oxwm # biner repo bila ada; zig dipastikan di dalam bila build source
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
