# oxwm-installer

Script instalasi otomatis window manager **OXWM** di **Arch Linux** — cukup satu perintah, desktop siap pakai. Terinspirasi installer komunitas seperti DankLinux.

OXWM adalah *dynamic window manager* untuk X11 (gaya dwm, konfigurasi Lua dengan hot-reload). Sumber: https://github.com/tonybanters/oxwm — di Arch dipasang dari AUR (`oxwm-git`).

## Yang dipasang script ini

- Xorg + dependensi build OXWM (`zig`, `libx11`, `libxft`, `freetype2`, `fontconfig`, `libxinerama`)
- OXWM dari AUR via `yay` (dipasang otomatis bila belum ada)
- Aplikasi pendukung: `alacritty`, `rofi`, `picom`, `feh`, `scrot`, font JetBrains Mono + Font Awesome, applet jaringan & audio
- Display manager `lightdm` (diaktifkan saat boot)
- Dotfiles standar: `~/.config/oxwm/config.lua` + `~/.xinitrc` (hanya bila belum ada; config lama dibackup)
- Riwayat instalasi: `install.log` + basis data `install_history.db` (bila `sqlite3` tersedia)

## Kebutuhan

- Arch Linux fresh (disarankan mesin virtual dulu)
- Akses `sudo` + koneksi internet
- Dijalankan sebagai user biasa via `sudo` (jangan langsung sebagai root)

## Cara penggunaan

```bash
git clone https://github.com/itah-btw/oxwm-installer.git
cd oxwm-installer
chmod +x install.sh

# 1. Simulasi dulu (aman, tanpa sudo, tanpa mengubah sistem)
./install.sh --dry-run

# 2. Instalasi penuh
sudo ./install.sh

# 3. Reboot, pilih sesi OXWM di layar login
sudo reboot
```

Opsi lain:

```bash
./install.sh --help   # bantuan
sudo ./install.sh --yes  # lewati konfirmasi
```

Tanpa display manager: login di TTY lalu jalankan `startx` (memakai `~/.xinitrc`).

## Shortcut dasar OXWM (config bawaan)

| Tombol | Aksi |
|---|---|
| Super + Enter | Buka terminal |
| Super + D | Launcher (rofi) |
| Super + Q | Tutup jendela |
| Super + Shift + Q | Keluar OXWM |
| Super + Shift + R | Reload config |
| Super + H/J/K/L | Pindah fokus |
| Super + 1..9 | Pindah tag |
| Super + Shift + 1..9 | Pindah jendela ke tag |

## Troubleshooting

- **"jalankan dengan sudo"** → pakai `sudo ./install.sh`, bukan sebagai root langsung.
- **"pacman tidak ditemukan"** → script ini khusus Arch Linux.
- **Gagal di satu paket** → baca pesan error + `install.log`, perbaiki (biasanya mirror/koneksi), jalankan ulang (script idempoten).
- **Config lama** → tersimpan di `~/.config-backup-TANGGAL/`, tinggal kembalikan manual.
- **Cek riwayat** → `sqlite3 install_history.db "SELECT * FROM log_tahap;"` atau baca `install.log`.

## Struktur repo

```
oxwm-installer/
├── install.sh              # script utama
├── dotfiles/oxwm/config.lua# config OXWM standar
├── dotfiles/xinitrc        # dipakai startx
├── packages/arch-oxwm.txt  # daftar paket
└── README.md
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
