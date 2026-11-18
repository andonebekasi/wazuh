# Panduan Lengkap: Mengganti Hostname dan Konfigurasi NTP Indonesia di Semua Distro Linux

Panduan ini berisi langkah-langkah terstruktur dan komprehensif untuk mengubah **Hostname** dan menyinkronkan waktu sistem ke **NTP Pool Indonesia** pada berbagai distribusi Linux (Debian/Ubuntu, RHEL/CentOS/AlmaLinux/Rocky Linux, Amazon Linux, openSUSE, Arch Linux, hingga Alpine Linux).

---

## Daftar Isi
1. [Informasi Dasar (Pool NTP & Timezone Indonesia)](#1-informasi-dasar)
2. [Panduan Mengganti Hostname](#2-panduan-mengganti-hostname)
   - [A. Distro Modern berbasis Systemd (Universal)](#a-distro-modern-berbasis-systemd-universal)
   - [B. Distro Minimal / Non-Systemd (Alpine Linux)](#b-distro-minimal--non-systemd-alpine-linux)
   - [C. Pencegahan Reset Hostname pada Cloud VPS (AWS/OCI/GCP/Azure)](#c-pencegahan-reset-hostname-pada-cloud-vps)
3. [Panduan Mengganti Waktu & Timezone Indonesia via CLI](#3-panduan-mengganti-waktu--timezone-indonesia-via-cli)
   - [A. Mengatur Timezone Indonesia (WIB, WITA, WIT)](#a-mengatur-timezone-indonesia-wib-wita-wit)
   - [B. Mengatur Jam & Tanggal secara Manual (CLI)](#b-mengatur-jam--tanggal-secara-manual-cli)
   - [C. Sinkronisasi Jam ke Hardware Clock (BIOS/RTC)](#c-sinkronisasi-jam-ke-hardware-clock-biosrtc)
   - [D. Sinkronisasi Jam Instan Sekali Jalan (Force Sync)](#d-sinkronisasi-jam-instan-sekali-jalan-force-sync)
4. [Panduan Konfigurasi NTP Indonesia (Daemon Otomatis)](#4-panduan-konfigurasi-ntp-indonesia-daemon-otomatis)
   - [A. Metode 1: Chrony (Sangat Direkomendasikan untuk Server & RHEL/CentOS/Ubuntu)](#a-metode-1-chrony-sangat-direkomendasikan)
   - [B. Metode 2: systemd-timesyncd (Default Ringan Ubuntu/Debian)](#b-metode-2-systemd-timesyncd-bawaan-ubuntudebian)
   - [C. Metode 3: NTP Classic / ntpd (Legacy Server)](#c-metode-3-ntp-classic--ntpd-legacy)
   - [D. Metode 4: Alpine Linux (OpenRC)](#d-metode-4-alpine-linux-openrc)
5. [Tabel Ringkasan Cepat (Cheat Sheet)](#5-tabel-ringkasan-cepat-cheat-sheet)
6. [Skrip Otomatisasi (Universal Bash Script)](#6-skrip-otomatisasi-universal-bash-script)

---

## 1. Informasi Dasar

### A. Alamat Pool NTP Indonesia
NTP Pool Project menyediakan server waktu khusus untuk zona Indonesia:
- `0.id.pool.ntp.org`
- `1.id.pool.ntp.org`
- `2.id.pool.ntp.org`
- `3.id.pool.ntp.org`

Alternatif lokal (Lembaga Resmi):
- `ntp.bmkg.go.id` (Badan Meteorologi, Klimatologi, dan Geofisika)
- `id.pool.ntp.org` (Zona pool umum)

### B. Zona Waktu Indonesia (Timezone)
- **WIB (Waktu Indonesia Barat / UTC+7)**: `Asia/Jakarta` atau `Asia/Pontianak`
- **WITA (Waktu Indonesia Tengah / UTC+8)**: `Asia/Makassar`
- **WIT (Waktu Indonesia Timur / UTC+9)**: `Asia/Jayapura`

---

## 2. Panduan Mengganti Hostname

### A. Distro Modern berbasis Systemd (Universal)
Berlaku untuk: **Ubuntu, Debian, AlmaLinux, Rocky Linux, RHEL, CentOS 7/8/9, Fedora, Amazon Linux 2/2023, openSUSE, Arch Linux**.

#### 1. Ubah Hostname dengan `hostnamectl`
Jalankan perintah berikut (ganti `server-prod-01` dengan nama yang diinginkan):
```bash
sudo hostnamectl set-hostname server-prod-01
```

#### 2. Perbarui `/etc/hosts`
Sangat penting memperbarui berkas `/etc/hosts` agar perintah seperti `sudo` atau aplikasi lokal (termasuk Wazuh Agent) tidak mengalami *lookup timeout* / resolusi lambat.

Buka berkas:
```bash
sudo nano /etc/hosts
```
Sesuaikan baris `127.0.0.1` atau `127.0.1.1`:
```text
127.0.0.1   localhost server-prod-01
::1         localhost ip6-localhost ip6-loopback
```
*(Atau jika ada IP privat server, petakan: `<IP_SERVER> server-prod-01`)*

#### 3. Verifikasi
```bash
hostnamectl
# atau
hostname -f
```

---

### B. Distro Minimal / Non-Systemd (Alpine Linux)

Alpine Linux menggunakan **OpenRC**, bukan systemd.

#### 1. Mengubah Hostname
Edit file `/etc/hostname`:
```sh
echo "server-prod-01" | sudo tee /etc/hostname
```

Ubah juga `/etc/hosts`:
```sh
sudo nano /etc/hosts
```
Tambahkan:
```text
127.0.0.1   localhost server-prod-01
```

#### 2. Terapkan langsung tanpa reboot:
```sh
sudo hostname -F /etc/hostname
sudo rc-service hostname restart
```

---

### C. Pencegahan Reset Hostname pada Cloud VPS
Pada cloud provider (AWS EC2, Oracle Cloud Infrastructure, Google Cloud, Azure, DigitalOcean), hostname sering di-overwrite kembali ke nama default saat instance di-reboot karena adanya service **`cloud-init`**.

Agar perubahan hostname permanen di Cloud VPS:

1. Buka konfigurasi cloud-init:
   ```bash
   sudo nano /etc/cloud/cloud.cfg
   ```
2. Cari baris `preserve_hostname:` dan ubah nilainya menjadi `true`:
   ```yaml
   preserve_hostname: true
   ```
   *(Jika baris tersebut belum ada, tambahkan baris `preserve_hostname: true` di bagian paling atas file).*

---

## 3. Panduan Mengganti Waktu & Timezone Indonesia via CLI

Bagian ini membahas cara melihat, mengubah zona waktu, serta mengatur jam dan tanggal secara manual atau sinkronisasi instan melalui Command Line Interface (CLI).

### A. Mengatur Timezone Indonesia (WIB, WITA, WIT)

Pilihan zona waktu resmi di Indonesia:
- **WIB (UTC+7)**: `Asia/Jakarta` atau `Asia/Pontianak`
- **WITA (UTC+8)**: `Asia/Makassar`
- **WIT (UTC+9)**: `Asia/Jayapura`

#### 1. Cara Standar Modern (Distro berbasis Systemd)
Berlaku untuk: Ubuntu, Debian, RHEL, CentOS, AlmaLinux, Rocky, Amazon Linux, Fedora, openSUSE, Arch Linux.

```bash
# Cek timezone saat ini
timedatectl

# Lihat daftar timezone Indonesia yang tersedia
timedatectl list-timezones | grep Asia/

# Ubah ke WIB (Jakarta)
sudo timedatectl set-timezone Asia/Jakarta

# Atau ke WITA (Makassar)
sudo timedatectl set-timezone Asia/Makassar

# Atau ke WIT (Jayapura)
sudo timedatectl set-timezone Asia/Jayapura
```

#### 2. Menu Interaktif TUI (Wizard CLI)
Jika lebih menyukai tampilan menu interaktif di terminal:
- **Ubuntu / Debian**:
  ```bash
  sudo dpkg-reconfigure tzdata
  ```
  *(Pilih `Asia` -> `Jakarta`)*
- **RHEL / CentOS / Alma / Rocky**:
  ```bash
  tzselect
  ```

#### 3. Cara Universal / Non-Systemd (Alpine Linux, Slackware, Container Docker)
Menggunakan symlink berkas zona waktu:
```bash
# Pastikan tzdata terpasang (khusus Alpine: sudo apk add tzdata)
sudo ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
echo "Asia/Jakarta" | sudo tee /etc/timezone
```

---

### B. Mengatur Jam & Tanggal secara Manual (CLI)

> [!NOTE]
> Jika servis NTP aktif, sistem operasi biasanya menolak perubahan waktu manual. Matikan sementara NTP sebelum mengubah waktu secara manual.

#### 1. Menggunakan `timedatectl` (Systemd)
```bash
# 1. Nonaktifkan sinkronisasi NTP sementara
sudo timedatectl set-ntp false

# 2. Atur tanggal dan jam sekaligus (Format: YYYY-MM-DD HH:MM:SS)
sudo timedatectl set-time "2026-11-18 13:30:00"

# Atur jam saja (HH:MM:SS)
sudo timedatectl set-time "13:30:00"

# Atur tanggal saja (YYYY-MM-DD)
sudo timedatectl set-time "2026-11-18"

# 3. Aktifkan kembali NTP jika ingin waktu otomatis sinkron kembali
sudo timedatectl set-ntp true
```

#### 2. Menggunakan Perintah `date` (Universal di Semua Distro Linux)
Perintah `date` bekerja di semua varian Linux, termasuk Alpine Linux dan BusyBox.

```bash
# Format: date -s "YYYY-MM-DD HH:MM:SS"
sudo date -s "2026-11-18 13:30:00"

# Ubah jam saja (HH:MM:SS)
sudo date +%T -s "13:30:00"

# Format cepat: MMDDhhmmYYYY.ss (Bulan Tanggal Jam Menit Tahun.Detik)
sudo date 111813302026.00
```

---

### C. Sinkronisasi Jam ke Hardware Clock (BIOS/RTC)

Setelah mengubah waktu sistem, sangat disarankan untuk menyimpannya ke **RTC (Real-Time Clock / Jam Hardware)** agar waktu tidak kembali ke semula saat mesin di-reboot.

```bash
# 1. Simpan waktu sistem (OS) ke Jam Hardware (BIOS/RTC)
sudo hwclock --systohc

# 2. Cek waktu yang tersimpan di Jam Hardware
sudo hwclock --show

# 3. Salin waktu dari Jam Hardware ke sistem OS (kebalikan)
sudo hwclock --hctosys

# 4. Pastikan RTC disetel ke UTC (Standar terbaik Linux untuk menghindari konflik)
sudo timedatectl set-local-rtc 0
```

---

### D. Sinkronisasi Jam Instan Sekali Jalan (Force Sync)

Jika waktu server melenceng jauh dan Anda ingin langsung melompatkan (*step*) jam ke waktu Indonesia yang presisi tanpa menunggu daemon perlahan mengoreksi:

#### 1. Menggunakan Chrony:
```bash
# Jika service chronyd sedang berjalan:
sudo chronyc makestep

# Jika service belum berjalan (sinkronisasi sekali jalan lalu keluar):
sudo chronyd -q 'server 0.id.pool.ntp.org iburst'
```

#### 2. Menggunakan `systemd-timesyncd`:
```bash
sudo systemctl restart systemd-timesyncd
sudo timedatectl timesync-status
```

#### 3. Menggunakan `ntpdate` (Legacy):
```bash
# Pasang jika belum ada (Ubuntu: apt install ntpdate | RHEL: dnf install ntpdate)
sudo ntpdate -u 0.id.pool.ntp.org
```

---

## 4. Panduan Konfigurasi NTP Indonesia (Daemon Otomatis)

### A. Metode 1: Chrony (Sangat Direkomendasikan)
`chrony` adalah standar modern pengganti `ntpd`. Sinkronisasi lebih cepat, akurat, dan stabil pada mesin virtual maupun bare-metal.

#### 1. Instalasi Chrony
- **Ubuntu / Debian**:
  ```bash
  sudo apt update && sudo apt install -y chrony
  ```
- **RHEL / AlmaLinux / Rocky Linux / CentOS / Fedora / Amazon Linux**:
  ```bash
  sudo dnf install -y chrony
  # (Untuk CentOS 7 / Amazon Linux 2 gunakan: sudo yum install -y chrony)
  ```
- **openSUSE / SLES**:
  ```bash
  sudo zypper install -y chrony
  ```
- **Arch Linux**:
  ```bash
  sudo pacman -S chrony
  ```

#### 2. Atur Timezone ke WIB (Asia/Jakarta)
```bash
sudo timedatectl set-timezone Asia/Jakarta
```
*(Gunakan `Asia/Makassar` untuk WITA atau `Asia/Jayapura` untuk WIT)*.

#### 3. Konfigurasi Pool NTP Indonesia
Lokasi file konfigurasi:
- Ubuntu/Debian: `/etc/chrony/chrony.conf`
- RHEL/AlmaLinux/Rocky/Amazon Linux/CentOS: `/etc/chrony.conf`

Buka file konfigurasi:
```bash
# Ubuntu/Debian
sudo nano /etc/chrony/chrony.conf

# RHEL/Alma/CentOS/Amazon Linux
sudo nano /etc/chrony.conf
```

Komentari baris `pool ...` atau `server ...` bawaan, lalu tambahkan pool Indonesia:
```text
server 0.id.pool.ntp.org iburst
server 1.id.pool.ntp.org iburst
server 2.id.pool.ntp.org iburst
server 3.id.pool.ntp.org iburst
server ntp.bmkg.go.id iburst
```

#### 4. Restart dan Enable Service Chrony
- **Ubuntu / Debian**:
  ```bash
  sudo systemctl restart chrony
  sudo systemctl enable chrony
  ```
- **RHEL / Alma / Rocky / Amazon Linux**:
  ```bash
  sudo systemctl restart chronyd
  sudo systemctl enable chronyd
  ```

#### 5. Verifikasi Sinkronisasi
Periksa apakah server NTP Indonesia sudah terhubung:
```bash
chronyc sources -v
```
Periksa tracking offset dan status waktu:
```bash
chronyc tracking
```
*(Tanda `*` di depan salah satu server menandakan sumber waktu yang saat ini aktif digunakan).*

---

### B. Metode 2: systemd-timesyncd (Bawaan Ubuntu/Debian)
Cocok untuk instance Ubuntu/Debian standar jika tidak ingin menginstal paket tambahan seperti chrony.

#### 1. Atur Timezone
```bash
sudo timedatectl set-timezone Asia/Jakarta
```

#### 2. Edit Konfigurasi timesyncd
```bash
sudo nano /etc/systemd/timesyncd.conf
```
Ubah atau tambahkan baris berikut di bawah blok `[Time]`:
```ini
[Time]
NTP=0.id.pool.ntp.org 1.id.pool.ntp.org 2.id.pool.ntp.org 3.id.pool.ntp.org
FallbackNTP=ntp.bmkg.go.id id.pool.ntp.org
```

#### 3. Aktifkan dan Restart Service
```bash
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
```

#### 4. Verifikasi Status
```bash
timedatectl timesync-status
# atau
timedatectl status
```

---

### C. Metode 3: NTP Classic / ntpd (Legacy)
Biasa digunakan pada server lama (CentOS 6, Debian versi lama, atau infrastruktur khusus).

#### 1. Instalasi
- **Debian / Ubuntu**: `sudo apt install ntp`
- **CentOS / RHEL**: `sudo yum install ntp`

#### 2. Edit `/etc/ntp.conf`
```bash
sudo nano /etc/ntp.conf
```
Ganti baris server dengan:
```text
server 0.id.pool.ntp.org iburst
server 1.id.pool.ntp.org iburst
server 2.id.pool.ntp.org iburst
server 3.id.pool.ntp.org iburst
server ntp.bmkg.go.id iburst
```

#### 3. Restart Service
```bash
# Ubuntu/Debian
sudo systemctl restart ntp

# CentOS/RHEL
sudo systemctl restart ntpd
sudo systemctl enable ntpd
```

#### 4. Verifikasi
```bash
ntpq -p
```

---

### D. Metode 4: Alpine Linux (OpenRC)

#### 1. Pasang Timezone
```sh
sudo apk update
sudo apk add tzdata
sudo cp /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
echo "Asia/Jakarta" | sudo tee /etc/timezone
```

#### 2. Pasang & Konfigurasi Chrony
```sh
sudo apk add chrony
```
Edit `/etc/chrony/chrony.conf`:
```text
server 0.id.pool.ntp.org iburst
server 1.id.pool.ntp.org iburst
server 2.id.pool.ntp.org iburst
server 3.id.pool.ntp.org iburst
```

#### 3. Jalankan Service di Boot
```sh
sudo rc-update add chronyd default
sudo rc-service chronyd restart
```

#### 4. Cek Status
```sh
chronyc sources -v
```

---

## 5. Tabel Ringkasan Cepat (Cheat Sheet)

| Distro Linux | Perintah Ganti Hostname | Set Timezone / Waktu ID | Paket NTP Rekomendasi | File Konfigurasi NTP | Nama Service NTP |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Ubuntu / Debian** | `hostnamectl set-hostname <nama>` | `timedatectl set-timezone Asia/Jakarta` | `chrony` atau `systemd-timesyncd` | `/etc/chrony/chrony.conf` atau `/etc/systemd/timesyncd.conf` | `chrony` / `systemd-timesyncd` |
| **AlmaLinux / Rocky / RHEL** | `hostnamectl set-hostname <nama>` | `timedatectl set-timezone Asia/Jakarta` | `chrony` | `/etc/chrony.conf` | `chronyd` |
| **Amazon Linux 2 / 2023** | `hostnamectl set-hostname <nama>` | `timedatectl set-timezone Asia/Jakarta` | `chrony` | `/etc/chrony.conf` | `chronyd` |
| **CentOS 7 / 8 / 9 Stream** | `hostnamectl set-hostname <nama>` | `timedatectl set-timezone Asia/Jakarta` | `chrony` | `/etc/chrony.conf` | `chronyd` |
| **openSUSE / SLES** | `hostnamectl set-hostname <nama>` | `timedatectl set-timezone Asia/Jakarta` | `chrony` | `/etc/chrony.conf` | `chronyd` |
| **Arch Linux** | `hostnamectl set-hostname <nama>` | `timedatectl set-timezone Asia/Jakarta` | `chrony` | `/etc/chrony.conf` | `chronyd` |
| **Alpine Linux** | `echo "<nama>" > /etc/hostname` | `ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime` | `chrony` | `/etc/chrony/chrony.conf` | `chronyd` (OpenRC) |

---

## 6. Skrip Otomatisasi (Universal Bash Script)

Skrip berikut mendeteksi package manager secara otomatis, mengubah hostname, mengatur timezone ke **Asia/Jakarta**, memasang **Chrony**, dan mengonfigurasi pool **NTP Indonesia**.

Simpan kode berikut sebagai `setup_hostname_ntp_id.sh`:

```bash
#!/usr/bin/env bash
# ==============================================================================
# Script: setup_hostname_ntp_id.sh
# Deskripsi: Setup otomatis Hostname dan NTP Indonesia (Chrony) di Linux
# ==============================================================================

set -euo pipefail

NEW_HOSTNAME="${1:-}"

if [ -z "$NEW_HOSTNAME" ]; then
    echo "Penggunaan: sudo bash $0 <hostname-baru>"
    echo "Contoh    : sudo bash $0 wazuh-agent-web01"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] Skrip ini harus dijalankan dengan hak akses root (sudo)."
    exit 1
fi

echo "=========================================================="
echo " 1. Mengubah Hostname menjadi: $NEW_HOSTNAME"
echo "=========================================================="
if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
else
    echo "$NEW_HOSTNAME" > /etc/hostname
    hostname "$NEW_HOSTNAME" || true
fi

# Update /etc/hosts
if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$NEW_HOSTNAME/g" /etc/hosts
elif ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
    echo "127.0.0.1   $NEW_HOSTNAME" >> /etc/hosts
fi

# Pencegahan overwrite cloud-init jika ada
if [ -f /etc/cloud/cloud.cfg ]; then
    sed -i 's/^preserve_hostname:.*/preserve_hostname: true/' /etc/cloud/cloud.cfg
    if ! grep -q "^preserve_hostname: true" /etc/cloud/cloud.cfg; then
        echo "preserve_hostname: true" >> /etc/cloud/cloud.cfg
    fi
    echo "[OK] cloud-init preserve_hostname diatur ke true."
fi

echo "=========================================================="
echo " 2. Mengatur Timezone ke Asia/Jakarta"
echo "=========================================================="
if command -v timedatectl >/dev/null 2>&1; then
    timedatectl set-timezone Asia/Jakarta
elif [ -f /usr/share/zoneinfo/Asia/Jakarta ]; then
    ln -sf /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
    echo "Asia/Jakarta" > /etc/timezone
fi

echo "=========================================================="
echo " 3. Menginstal dan Mengonfigurasi Chrony (NTP Indonesia)"
echo "=========================================================="
CHRONY_CONF=""
SERVICE_NAME="chronyd"

if command -v dnf >/dev/null 2>&1; then
    dnf install -y chrony
    CHRONY_CONF="/etc/chrony.conf"
    SERVICE_NAME="chronyd"
elif command -v yum >/dev/null 2>&1; then
    yum install -y chrony
    CHRONY_CONF="/etc/chrony.conf"
    SERVICE_NAME="chronyd"
elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y chrony
    CHRONY_CONF="/etc/chrony/chrony.conf"
    SERVICE_NAME="chrony"
elif command -v zypper >/dev/null 2>&1; then
    zypper install -y chrony
    CHRONY_CONF="/etc/chrony.conf"
    SERVICE_NAME="chronyd"
elif command -v apk >/dev/null 2>&1; then
    apk add chrony tzdata
    CHRONY_CONF="/etc/chrony/chrony.conf"
    SERVICE_NAME="chronyd"
fi

if [ -n "$CHRONY_CONF" ] && [ -f "$CHRONY_CONF" ]; then
    # Backup config lama
    cp "$CHRONY_CONF" "${CHRONY_CONF}.bak_$(date +%Y%m%d%H%M%S)"
    
    # Nonaktifkan pool/server lama
    sed -i -E 's/^(pool|server)[[:space:]]/#\1 /' "$CHRONY_CONF"
    
    # Tambahkan NTP Pool Indonesia
    cat <<EOF >> "$CHRONY_CONF"

# NTP Servers Indonesia (Ditambahkan otomatis)
server 0.id.pool.ntp.org iburst
server 1.id.pool.ntp.org iburst
server 2.id.pool.ntp.org iburst
server 3.id.pool.ntp.org iburst
server ntp.bmkg.go.id iburst
EOF
fi

echo "=========================================================="
echo " 4. Merestart Service NTP"
echo "=========================================================="
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "$SERVICE_NAME"
    systemctl enable "$SERVICE_NAME"
elif command -v rc-service >/dev/null 2>&1; then
    rc-update add "$SERVICE_NAME" default || true
    rc-service "$SERVICE_NAME" restart
fi

# Simpan waktu ke Hardware Clock (BIOS/RTC)
if command -v hwclock >/dev/null 2>&1; then
    hwclock --systohc || true
fi

echo "=========================================================="
echo " [SELESAI] Konfigurasi Hostname dan NTP Berhasil!"
echo " Hostname saat ini : $(hostname)"
echo " Waktu saat ini    : $(date)"
echo "=========================================================="
chronyc sources -v || true
```

### Cara Menjalankan Skrip:
```bash
chmod +x setup_hostname_ntp_id.sh
sudo ./setup_hostname_ntp_id.sh nama-server-baru
```
