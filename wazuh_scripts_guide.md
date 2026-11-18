# PANDUAN PENGGUNAAN SKRIP OTOMASI WAZUH v4.14 (SERVER & AGENT)

Panduan ini menjelaskan cara penggunaan skrip otomasi Bash untuk instalasi dan konfigurasi **Wazuh Server v4.14** (All-in-One) serta **Wazuh Agent v4.14** pada berbagai platform Linux enterprise.

---

## 📁 Daftar Skrip yang Disediakan

| Nama Skrip | Fungsi | Komponen yang Dipasang |
| :--- | :--- | :--- |
| [`install_wazuh_server.sh`](install_wazuh_server.sh) | Instalasi Server All-in-One | Wazuh Indexer, Wazuh Manager, Filebeat, Wazuh Dashboard |
| [`install_wazuh_agent.sh`](install_wazuh_agent.sh) | Instalasi & Pendaftaran Agent | Wazuh Agent (Koleksi log, FIM, SCA, Active Response) |

---

## 🖥️ Matriks Dukungan Sistem Operasi (OS Matrix)

Kedua skrip secara otomatis mendeteksi distribusi Linux, arsitektur CPU (`x86_64` / `aarch64`), dan package manager yang sesuai:

| Keluarga Distribusi | Distribusi & Versi yang Didukung | Package Manager |
| :--- | :--- | :--- |
| **Debian / Ubuntu** | - Ubuntu 18.04 LTS (Bionic)<br>- Ubuntu 20.04 LTS (Focal)<br>- Ubuntu 22.04 LTS (Jammy)<br>- Ubuntu 24.04 LTS (Noble / Latest)<br>- Debian 10 (Buster), 11 (Bullseye), 12 (Bookworm) | `apt-get` |
| **RHEL / Clone** | - Red Hat Enterprise Linux (RHEL) 7, 8, 9, 10<br>- AlmaLinux 8, 9, 10<br>- Rocky Linux 8, 9<br>- CentOS Linux 7, CentOS Stream 8 & 9 | `dnf` / `yum` |
| **Oracle Linux** | - Oracle Linux 7, 8, 9 (UEK & RHCK) | `dnf` / `yum` |
| **Amazon Web Services** | - Amazon Linux 2 (AL2)<br>- Amazon Linux 2023 (AL2023) | `yum` (AL2) / `dnf` (AL2023) |

---

## 1. PANDUAN WAZUH SERVER (`install_wazuh_server.sh`)

Skrip ini menjalankan instalasi lengkap **All-in-One** (Indexer, Manager, Filebeat, Dashboard) versi **4.14.x** (rilis stabil terbaru seperti 4.14.10) menggunakan asisten resmi Wazuh yang diperkuat dengan pre-flight checks dan system tuning otomatis.

### 1.1 Fitur Otomatisasi Skrip Server
1. **Pre-flight Check Hardware**:
   - Memeriksa kapasitas RAM (minimal 4 GB, direkomendasikan 8 GB+).
   - Memeriksa jumlah core CPU (minimal 2 vCPU).
   - Memeriksa sisa kapasitas storage (minimal 10 GB free).
2. **System & Kernel Parameter Tuning (Wajib untuk Indexer/OpenSearch)**:
   - Mengatur `vm.max_map_count=262144` secara permanen di `/etc/sysctl.d/99-wazuh-indexer.conf` dan menerapkannya langsung.
   - Mengatur `vm.swappiness=1`.
   - Mengatur limit file descriptor & proses di `/etc/security/limits.d/99-wazuh.conf` (`nofile 65536`, `nproc 4096`, `memlock unlimited`).
3. **Instalasi Dependensi Sistem**:
   - Menyiapkan `curl`, `tar`, `gzip`, `unzip`, `jq`, `coreutils`, `procps-ng`, `libcap`.
4. **Konfigurasi Firewall Lokal Otomatis (Opsional)**:
   - Mendeteksi `firewalld` atau `ufw` dan membuka port:
     * `1514/TCP` : Komunikasi event dari Agent
     * `1515/TCP` : Layanan pendaftaran Agent (Authd)
     * `443/TCP`  : Akses HTTPS Wazuh Dashboard Web UI
     * `55000/TCP`: Wazuh RESTful API
5. **Verifikasi & Ekstraksi Kredensial**:
   - Menjalankan health check seluruh systemd service (`wazuh-indexer`, `wazuh-manager`, `filebeat`, `wazuh-dashboard`).
   - Menyalin file kredensial `wazuh-passwords.txt` ke `/root/wazuh-passwords.txt` dengan izin aman (`chmod 600`).
   - Menampilkan kredensial user `admin` dan URL akses dashboard di akhir instalasi.

### 1.2 Cara Menjalankan Skrip Server

```bash
# Berikan hak eksekusi
chmod +x install_wazuh_server.sh

# 1. Instalasi Standar (All-in-One):
sudo ./install_wazuh_server.sh

# 2. Instalasi dengan pembukaan port firewall lokal otomatis:
sudo ./install_wazuh_server.sh --open-firewall

# 3. Instalasi pada VM lab/testing dengan RAM terbatas (< 4 GB):
sudo ./install_wazuh_server.sh --force --open-firewall

# 4. Hanya menjalankan pengecekan kompatibilitas & tuning tanpa install:
sudo ./install_wazuh_server.sh --check-only
```

### 1.3 Opsi CLI Flag Server

| Flag | Deskripsi |
| :--- | :--- |
| `-f`, `--force` | Mengabaikan peringatan spesifikasi hardware (RAM < 4 GB / CPU < 2). |
| `-o`, `--open-firewall` | Membuka port 1514, 1515, 443, 55000 pada firewall lokal (`firewalld` / `ufw`). |
| `-c`, `--check-only` | Menjalankan pre-flight check sistem tanpa mengunduh/menginstal paket. |
| `-h`, `--help` | Menampilkan menu bantuan perintah. |

---

## 2. PANDUAN WAZUH AGENT (`install_wazuh_agent.sh`)

Skrip ini memasang **Wazuh Agent v4.14** pada endpoint client dan langsung mendaftarkannya (auto-enrollment) ke Wazuh Manager.

### 2.1 Fitur Otomatisasi Skrip Agent
1. **Pre-flight Connectivity Test**:
   - Menguji keterjangkauan Port 1515 TCP (Authd enrollment) dan Port 1514 TCP (Event communication) ke arah Wazuh Manager menggunakan native socket Linux sebelum instalasi.
   - Memberikan peringatan dini jika firewall/Security Group masih memblokir koneksi.
2. **Setup Repository & GPG Key Otomatis**:
   - Menambahkan repository resmi Wazuh 4.x sesuai OS target.
   - Menangani kompatibilitas GPG keyring modern (`/usr/share/keyrings/wazuh.gpg`) maupun fallback legacy (`apt-key`) untuk Ubuntu 18.04.
   - Menangani repository RPM untuk RHEL, CentOS, AlmaLinux, Oracle Linux, Amazon Linux 2, dan Amazon Linux 2023.
3. **Auto-Enrollment & Injeksi Parameter**:
   - Mendukung parameter nama agent (`-n`), grup agent (`-g`), protokol (`-P`), dan registration password (`-p`).
4. **Verifikasi Konfigurasi & Service**:
   - Memeriksa `/var/ossec/etc/ossec.conf` untuk memastikan tag `<address>` mengarah ke Manager yang benar.
   - Mengaktifkan dan merestart service `wazuh-agent`.
   - Menunggu dan memverifikasi pertukaran kunci kriptografi pada `/var/ossec/etc/client.keys`.

### 2.2 Cara Menjalankan Skrip Agent

```bash
# Berikan hak eksekusi
chmod +x install_wazuh_agent.sh

# 1. Instalasi Cepat (Otomatis menggunakan hostname server & grup 'default'):
sudo ./install_wazuh_agent.sh -m <IP_WAZUH_MANAGER>

# Contoh:
sudo ./install_wazuh_agent.sh -m 172.31.10.50

# 2. Instalasi dengan Nama Kustom & Multi-Grup:
sudo ./install_wazuh_agent.sh -m 172.31.10.50 -n "web-prod-01" -g "production,web,dmz"

# 3. Instalasi dengan Registration Password (authd.pass):
sudo ./install_wazuh_agent.sh -m 172.31.10.50 -n "db-oracle-01" -g "production,database" -p "PasswordRahasia123"

# 4. Mode Non-Interaktif (Cocok untuk Scripting / Cloud-Init / AWS SSM):
sudo ./install_wazuh_agent.sh -m 172.31.10.50 -y
```

### 2.3 Opsi CLI Flag Agent

| Flag | Parameter | Deskripsi | Default |
| :--- | :--- | :--- | :--- |
| `-m`, `--manager` | `<IP\|FQDN>` | **(Wajib)** Alamat IP Private/Public atau Domain Wazuh Manager | - |
| `-n`, `--agent-name`| `<NAME>` | Nama unik agent yang muncul pada Dashboard | Hostname sistem |
| `-g`, `--agent-group`| `<GROUP>` | Grup agent di Manager (pisahkan dengan koma jika multi-grup) | `default` |
| `-p`, `--auth-pass` | `<PASS>` | Password registrasi jika Authd Manager diproteksi password | Tidak ada |
| `-P`, `--protocol` | `<tcp\|udp>` | Protokol komunikasi event | `tcp` |
| `-v`, `--version` | `<VER>` | Versi rilis mayor/minor Wazuh | `4.14` |
| `-f`, `--force` | - | Mengabaikan kegagalan uji konektivitas port TCP | `false` |
| `-y`, `--yes` | - | Mode non-interaktif (otomatis konfirmasi) | `false` |
| `-h`, `--help` | - | Menampilkan panduan bantuan | - |

---

## 3. PENGATURAN KEAMANAN REGISTRASI (`authd.pass`) DI SISI SERVER

Secara default, Wazuh Manager menerima pendaftaran dari agent mana pun yang dapat menjangkau port 1515 TCP. Di lingkungan cloud publik, sangat disarankan memasang password registrasi.

### Langkah Setup di Sisi Wazuh Server:
```bash
# 1. Buat file authd.pass berisi password rahasia
echo "KunciRahasiaWazuh2026!" | sudo tee /var/ossec/etc/authd.pass

# 2. Amankan permission file
sudo chmod 640 /var/ossec/etc/authd.pass
sudo chown root:wazuh /var/ossec/etc/authd.pass

# 3. Restart Wazuh Manager
sudo systemctl restart wazuh-manager
```

### Langkah di Sisi Agent:
Jalankan skrip instalasi agent dengan menambahkan flag `-p`:
```bash
sudo ./install_wazuh_agent.sh -m <IP_WAZUH_SERVER> -p "KunciRahasiaWazuh2026!"
```

---

## 4. SKRIP OTOMASI DI CLOUD (AWS USER-DATA / CLOUD-INIT)

Untuk melakukan deployment Wazuh Agent otomatis saat EC2 instance baru diluncurkan (Auto Scaling Group / Launch Template), masukkan skrip berikut ke dalam field **User Data**:

```bash
#!/usr/bin/env bash
set -e

# Download skrip agent dari repository/S3 internal atau wget langsung
curl -sSL -o /tmp/install_wazuh_agent.sh "https://raw.githubusercontent.com/your-repo/wazuh/main/install_wazuh_agent.sh"
chmod +x /tmp/install_wazuh_agent.sh

# Eksekusi secara silent/non-interaktif
/tmp/install_wazuh_agent.sh -m "172.31.10.50" -g "production,aws-ec2" -y
```

---

## 5. DIAGNOSA & PEMECAHAN MASALAH (TROUBLESHOOTING)

### 1. Agent Service Active tapi Belum Muncul di Dashboard
Periksa log komunikasi pada agent:
```bash
sudo tail -n 50 /var/ossec/logs/ossec.log
```
- Jika ada pesan `Unable to connect to ... [1515]`:
  Periksa Inbound Security Group di AWS/Cloud untuk port `1515/TCP`.
- Jika ada pesan `Invalid password`:
  Password registrasi pada flag `-p` tidak sesuai dengan `/var/ossec/etc/authd.pass` di server.

### 2. Memeriksa Status Kunci Kriptografi Agent
```bash
# Di sisi Agent:
sudo cat /var/ossec/etc/client.keys
# Output normal: ID  Nama-Agent  IP-Agent  Key

# Di sisi Server:
sudo /var/ossec/bin/manage_agents -l
```

### 3. Menguji Port Jaringan Antar Host (Tanpa Netcat)
```bash
# Dari sisi Agent ke Server:
(timeout 3 bash -c "</dev/tcp/<IP_SERVER>/1514") && echo "PORT 1514 TERBUKA" || echo "PORT 1514 TERTUTUP"
(timeout 3 bash -c "</dev/tcp/<IP_SERVER>/1515") && echo "PORT 1515 TERBUKA" || echo "PORT 1515 TERTUTUP"
```
