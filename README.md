# oxwm-installer

Script instalasi otomatis window manager **OXWM** untuk **Arch Linux, Fedora, dan Debian/Ubuntu** — cukup satu perintah, desktop siap pakai.

OXWM adalah *dynamic window manager* untuk X11 (gaya dwm, konfigurasi Lua dengan hot-reload). Sumber: https://github.com/tonybanters/oxwm — script membangunnya dari source.

## Cuplikan

![OXWM di Fedora (wallpaper)](screenshots/oxwm-fedora-wallpaper.png)

![OXWM tag 2](screenshots/oxwm-test-tag2-1.png)

![OXWM tag 2 (varian)](screenshots/oxwm-test-tag2-2.png)

## Distro yang didukung

| Distro | Package manager | Catatan |
|---|---|---|
| Arch Linux | pacman | Semua dependensi dari repo resmi |
| Debian / Ubuntu | apt | `zig` tidak ada di repo → tarball stabil terbaru otomatis; `fastfetch` di rilis lama → `.deb` upstream |
| Fedora | dnf | Semua dependensi dari repo resmi |

## Yang dipasang script ini

- Xorg + dependensi build OXWM (`zig`, `libx11`, `libxft`, `freetype`, `fontconfig`, `libxinerama` — nama paket dipetakan otomatis per distro)
- OXWM dibangun dari source HEAD terbaru (`zig build`), terpasang di `/usr/local/bin/oxwm` + perintah pendamping (`oxwm-theme`, `dmenu_run`/`dmenu-themed`/`dunst` bertema)
- Terminal `st` dibangun dari source suckless dalam 3 tema + dispatcher `st` (ikut file tema oxwm)
- Aplikasi pendukung: `dmenu`, `feh`, `maim`+`slop`, `xdotool`, `dunst`, `xclip`, font JetBrains Mono + Font Awesome (font Nerd diunduh bila tak ada), `btop`, `fastfetch` (Debian 13+/Ubuntu 25.04+; Debian lama ambil `.deb` rilis upstream), `khal`, applet CLI (nmtui, bluetoothctl, wpctl, brightnessctl)
- Tanpa display manager: autologin getty di tty1 + `startx` otomatis (DM lama seperti LightDM/GDM/GDM3/SDDM dimatikan bila ada)
- Dotfiles: `~/.config/oxwm/` (config + topbar, keybind, palet + wallpaper 3 tema, dunst bertema, skrip status cpu/temp/wifi/bt) + `~/.config/khal/` + `~/.xinitrc` (config lama dibackup)
- Log instalasi: `/var/log/oxwm-installer/install.log` (fallback `./install.log` bila direktori itu tak bisa ditulis)

## Kebutuhan

- Salah satu: Arch Linux, Debian/Ubuntu, atau Fedora (disarankan coba di mesin virtual dulu)
- Akses `sudo` + koneksi internet
- Dijalankan sebagai user biasa via `sudo` (jangan langsung sebagai root)

## Cara penggunaan

Satu baris (butuh `curl`; tanpa klon dulu; mode pipe wajib `--yes`):

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/itah-btw/oxwm-installer@main/install.sh | sudo bash -s -- --yes
curl -fsSL https://cdn.jsdelivr.net/gh/itah-btw/oxwm-installer@main/install.sh | sudo bash -s -- --theme gruvbox --yes
```

Atau cara klasik:

```bash
git clone https://github.com/itah-btw/oxwm-installer.git
cd oxwm-installer
chmod +x install.sh

# 1. Simulasi dulu (aman, tanpa sudo, tanpa mengubah sistem)
./install.sh --dry-run

# 2. Instalasi penuh
sudo ./install.sh

# 3. Reboot: login konsol otomatis di tty1, startx jalan sendiri ke OXWM
sudo reboot
```

Opsi lain:

```bash
./install.sh --help            # bantuan
sudo ./install.sh --yes        # lewati konfirmasi
sudo ./install.sh --rebuild    # bangun ulang oxwm + st walau sudah ada
sudo ./install.sh --theme gruvbox --yes  # langsung pakai tema gruvbox
```

Tanpa display manager: login konsol otomatis di tty1, lalu `startx` jalan
sendiri memakai `~/.xinitrc`. TTY lain tetap login manual biasa.

## Shortcut dasar OXWM (config bawaan)

| Tombol | Aksi |
|---|---|
| Super + Enter | Buka terminal (st) |
| Super + D | Launcher (dmenu bertema) |
| Super + V | Riwayat clipboard (butuh `clipmenud` jalan) |
| Super + Y | Kalender (`ikhal`) |
| Super + S | Screenshot area (maim, tersimpan + clipboard) |
| Super + Q | Tutup jendela |
| Super + Shift + Q | Keluar OXWM |
| Super + Shift + R | Reload config |
| Super + J/K | Pindah fokus (tumpukan) |
| Super + H/L | Kecilkan/besarkan area master |
| Super + Shift + Space | Toggle jendela tiling ↔ apung (floating) |
| Super + 1..9 | Pindah tag |
| Super + Shift + 1..9 | Pindah jendela ke tag |

## Tema

Tiga tema bawaan (topbar, border, st/dmenu/dunst, wallpaper): `tokyonight`,
`gruvbox`, `catppuccin`. Palet di `~/.config/oxwm/colors/`, wallpaper di
`~/.config/oxwm/wallpapers/`, pilihan aktif di `~/.config/oxwm/theme`.

```bash
sudo ./install.sh --theme gruvbox   # tema awal saat instalasi
oxwm-theme catppuccin               # ganti kapan saja (wallpaper + dunst + reload ikut)
```

`oxwm-theme` menulis `~/.config/oxwm/theme`, memasang wallpaper tema itu,
me-restart dunst dengan confignya, lalu me-reload oxwm. Tanpa X aktif (atau
tanpa `xdotool`), reload dilakukan manual dengan `Super+Shift+R`. Cara manual
tetap bisa: tulis langsung (`echo gruvbox > ~/.config/oxwm/theme`) lalu reload.

Tanpa `--theme`, instalasi memakai `tokyonight` untuk pengguna baru dan
tidak mengubah file tema yang sudah ada.

## Troubleshooting

- **"jalankan dengan sudo"** → pakai `sudo ./install.sh`, bukan sebagai root langsung.
- **"distro tidak didukung"** → butuh Arch Linux, Debian/Ubuntu, atau Fedora.
- **Gagal di satu paket** → baca pesan error + log (`/var/log/oxwm-installer/install.log`), perbaiki (biasanya mirror/koneksi), jalankan ulang (script idempoten; `--rebuild` bila ingin bangun ulang dari source).
- **Config lama** → tersimpan di `~/.config-backup-TANGGAL-JAM/`, tinggal kembalikan manual.
- **Cek riwayat tahap** → `grep '\[.*\]' /var/log/oxwm-installer/install.log`.

## Struktur repo

```
oxwm-installer/
├── install.sh                       # script utama (--dry-run/--yes/--rebuild/--theme)
├── bin/oxwm-theme                  # perintah ganti tema (terpasang ke /usr/local/bin)
├── bin/dmenu_run, bin/dmenu-themed # dmenu bertema (terpasang ke /usr/local/bin)
├── bin/dunst                       # dunst bertema (terpasang ke /usr/local/bin)
├── dotfiles/oxwm/config.lua         # config OXWM: topbar, keybind (baca ~/.config/oxwm/theme)
├── dotfiles/oxwm/colors/            # palet: tokyonight, gruvbox, catppuccin
├── dotfiles/oxwm/wallpapers/        # wallpaper per tema
├── dotfiles/oxwm/dunstrc-*          # config dunst per tema
├── dotfiles/oxwm/*-status.sh        # skrip blok topbar (cpu/temp/wifi/bt/vol/mic/bright)
├── dotfiles/oxwm/theme              # tema bawaan (tokyonight)
├── dotfiles/khal/config             # kalender lokal minimal (ikhal)
├── dotfiles/fastfetch/config.jsonc  # config fastfetch
├── dotfiles/xinitrc                 # dipakai startx
├── packages/{arch,debian,fedora}-oxwm.txt  # daftar paket
├── screenshots/                     # cuplikan layar untuk README
├── tests/smoke.sh                   # uji asap (sintaks + fungsi murni)
├── .github/workflows/ci.yml         # CI: shellcheck + uji asap
└── README.md
```

Opsional (ada keybind-nya di config, pasang manual bila perlu): `clipmenu`
(riwayat clipboard), `bluetui`/`wiremix` (audio), `yazi`, kalender Google via
`vdirsyncer`.

## Aplikasi opsional per distro

Keybind-nya sudah ada di config, tinggal pasang programnya:

| Aplikasi (keybind) | Arch | Debian/Ubuntu | Fedora |
|---|---|---|---|
| `yazi` (Super+E) | `pacman -S yazi` | repo pihak ketiga, atau `.deb` manual, atau `cargo install` (lihat bawah) | COPR `lihaohong/yazi`, atau Terra |
| `clipmenu` (Super+V) | `pacman -S clipmenu` | build dari source (lihat bawah) | build dari source (lihat bawah) |
| `bluetui` (Super+U) | `cargo install bluetui` | sama | sama |
| `wiremix` (Super+Shift+V) | `cargo install wiremix` | sama | sama |

Debian/Ubuntu `yazi` (tidak ada di repo resmi):

```bash
# via extrepo (Debian) atau tambah manual:
sudo apt install extrepo
sudo extrepo enable griffo  # atau griffo-free
sudo apt update && sudo apt install yazi
# alternatif: unduh .deb dari rilis upstream, lalu sudo dpkg -i yazi-*.deb
```

Fedora `yazi` (tidak ada di repo resmi, COPR ini yang didokumentasikan upstream):

```bash
sudo dnf install dnf-plugins-core
sudo dnf copr enable lihaohong/yazi
sudo dnf install yazi
```

`clipmenu` dari source (Debian/Fedora — butuh header X11 yang sudah
dipasang installer untuk build oxwm, plus `xsel`):

```bash
git clone https://github.com/cdown/clipnotify && cd clipnotify && sudo make install && cd ..
git clone https://github.com/cdown/clipmenu && cd clipmenu && sudo make install
```

`bluetui`/`wiremix` via cargo (semua distro; wiremix butuh header PipeWire
saat build: `libpipewire-0.3-dev` di Debian, `pipewire-devel` di Fedora,
`libpipewire` di Arch):

```bash
cargo install bluetui wiremix
# pastikan ~/.cargo/bin ada di PATH
```

## Upload ke GitHub (dari folder ini)

```bash
git init
git add .
git commit -m "oxwm-installer: instalasi otomatis OXWM di Arch Linux"
git branch -M main
git remote add origin https://github.com/itah-btw/oxwm-installer.git
git push -u origin main
```

Lisensi: MIT.
