# PANDUAN LENGKAP: INSTALASI & KONFIGURASI WAZUH SERVER (ALL-IN-ONE) - ALMALINUX 10 (LAVENDER LION / EL10)

Dokumen ini adalah panduan teknis operasional lengkap untuk instalasi, konfigurasi,
pengerasan (hardening), dan pemeliharaan Wazuh Server (Wazuh Indexer, Wazuh Manager,
Filebeat, dan Wazuh Dashboard) rilis terbaru pada sistem operasi AlmaLinux 10.x 
(Platform EL10) baik di lingkungan Bare-Metal, On-Premise Hypervisor, maupun Cloud 
(seperti Oracle Cloud Infrastructure / OCI, AWS EC2, GCP, dll).

### INFORMASI SPESIFIKASI SISTEM TARGET

- OS Target         : AlmaLinux 10.2 (Lavender Lion) / Platform: el10
- Arsitektur        : x86_64 / aarch64
- Hostname Contoh   : trees-wazuh-prod ([opc@trees-wazuh-prod ~]$)
- Package Manager   : DNF 5 (`dnf`)
- Init System       : Systemd (cgroups v2)
- Keamanan Default  : SELinux Enforcing, Firewalld Active
- Versi Wazuh Target: Wazuh Server v4.14.x (Rilis Stabil v4.x Terbaru, misal 4.14)

## DAFTAR ISI

1.  Arsitektur Wazuh All-in-One & Alur Data Log
2.  Rekomendasi Spesifikasi Hardware & Storage AlmaLinux 10
3.  Persiapan Sistem Operasi: Kernel Sysctl, Limits & SELinux
4.  Konfigurasi Jaringan, Firewall (Firewalld) & Cloud Security Rules
5.  Metode 1: Instalasi Otomatis (Wazuh Installation Assistant - Disarankan)
    - 5.1 Download Assistant Script Terbaru
    - 5.2 Eksekusi Instalasi All-in-One (`-a`)
    - 5.3 Ekstraksi & Pengamanan Kredensial (`wazuh-passwords.txt`)
6.  Metode 2: Instalasi Terbimbing / Custom Config (`config.yml`)
    - 6.1 Download Konfigurasi & Inisialisasi Certs
    - 6.2 Modifikasi Konfigurasi Node (`config.yml`)
    - 6.3 Eksekusi Step-by-Step Per Komponen
7.  Akses & Manajemen Awal Wazuh Dashboard Web UI
8.  Konfigurasi Registrasi Agent di Sisi Manager (`authd`)
    - 8.1 Setup Password Authd (`/var/ossec/etc/authd.pass`)
    - 8.2 Konfigurasi Opsi Force Reconnect & Overwrite Duplikat
9.  Pemeriksaan Status Layanan & Health Check Sistem (Verifikasi Mandiri)
10. Pemeliharaan, Manajemen Indeks (ISM) & Backup Data
11. Troubleshooting Komprehensif Masalah di AlmaLinux 10
12. Cheat Sheet Perintah Penting & Lokasi File / Log Utama

## 1. ARSITEKTUR WAZUH ALL-IN-ONE & ALUR DATA LOG

Dalam konfigurasi All-in-One, seluruh komponen Wazuh dijalankan pada satu host 
AlmaLinux 10:

| HOST: AlmaLinux 10 (trees-wazuh-prod) |  |  |  |
| :--- | :--- | :--- | :--- |
| [ Wazuh Agent Client ] --(Port 1514 TCP: Events)------------------>+ |  |  |  |
| [ Wazuh Agent Client ] --(Port 1515 TCP: Enrollment/Authd)--------> |  |  |  |
|  | 1. WAZUH MANAGER / SERVER |  |  |
|  | - Menerima log & event dari agent | <-+ |  |
|  | - Melakukan decoding & rule analysis |  |  |
|  | - Menulis alert ke /var/ossec/logs/alerts/alerts.json |  |  |
|  | - RESTful API (Port 55000 TCP) |  |  |
| v (membaca file alert lokal) |  |  |  |
|  | 2. FILEBEAT |  |  |
|  | - Mengirim alerts.json ke Indexer secara terenkripsi TLS |  |  |
| v (Port 9200 TCP TLS) |  |  |  |
|  | 3. WAZUH INDEXER (OpenSearch Engine) |  |  |
|  | - Search & Analytics NoSQL Database |  |  |
|  | - Menyimpan data indeks secara terkompresi & terenkripsi |  |  |
| ^ |  |  |  |
|  | (Query data) |  |  |
|  | 4. WAZUH DASHBOARD |  |  |
|  | - Web Interface Visualization & Management |  |  |
|  | - Diakses oleh Admin/SOC via HTTPS (Port 443 TCP) |  |  |

## 2. REKOMENDASI SPESIFIKASI HARDWARE & STORAGE ALMALINUX 10

Komponen Wazuh Indexer berbasis Java OpenSearch membutuhkan kapasitas RAM dan IOPS 
yang memadai agar terhindar dari crash Out-Of-Memory (OOM).

Skala Deployment & Rekomendasi Resource:

| Beban / Jumlah Agent | CPU Cores | RAM Min (Disarankan) | Tipe Storage & Disk |
| :--- | :--- | :--- | :--- |
| Small (1 - 25 Agent) | 4 vCPU | 8 GB (16 GB) | 100 GB SSD / NVMe |
| Medium (25-100 Agent) | 8 vCPU | 16 GB (32 GB) | 300+ GB SSD (IOPS tinggi) |
| Large (> 100 Agent) | Multi-Node Distributed Setup Disarankan (Pisah Server) |  |  |

Catatan Khusus Storage:
- Disarankan membuat mount point terpisah atau partisi luas untuk:
  * `/var/ossec/` (Database manager, binary, rules)
  * `/var/lib/wazuh-indexer/` (Tempat penyimpanan data log terindeks OpenSearch)

## 3. PERSIAPAN SISTEM OPERASI: KERNEL SYSCTL, LIMITS & SELINUX

Jalankan perintah berikut dengan user `root` atau menggunakan `sudo`:

### 3.1 Update Sistem AlmaLinux 10

sudo dnf clean all
sudo dnf update -y
sudo dnf install -y curl tar unzip gzip sed coreutils procps-ng jq libcap

### 3.2 Konfigurasi Kernel Virtual Memory (vm.max_map_count)

Wazuh Indexer membutuhkan batas memori mmap minimal 262144. Jika nilai ini 
terlalu kecil, Indexer akan gagal start!

# Cek nilai saat ini
sysctl vm.max_map_count

# Set nilai baru secara permanen
sudo bash -c 'cat << EOF > /etc/sysctl.d/99-wazuh-indexer.conf
vm.max_map_count=262144
vm.swappiness=1
net.core.somaxconn=1024
EOF'

# Terapkan perubahan segera
sudo sysctl --system

### 3.3 Konfigurasi File Limits & Resource Descriptors

sudo bash -c 'cat << EOF > /etc/security/limits.d/99-wazuh.conf
wazuh-indexer soft nofile 65536
wazuh-indexer hard nofile 65536
wazuh-indexer soft nproc 4096
wazuh-indexer hard nproc 4096
wazuh-indexer soft memlock unlimited
wazuh-indexer hard memlock unlimited
wazuh soft nofile 65536
wazuh hard nofile 65536
EOF'

### 3.4 Penanganan SELinux di AlmaLinux 10

AlmaLinux 10 mengaktifkan SELinux secara default (`Enforcing`).
Wazuh resmi mendukung SELinux dengan policy modul otomatis. Namun pada fase 
instalasi awal, pastikan tidak ada blocking policy yang memutus koneksi:

# Verifikasi status SELinux
sestatus

# Jika ingin memastikan tidak terhalang selama proses instalasi:
# sudo setenforce 0  # (Opsional: Permissive sementara selama setup)
# Note: Installer Wazuh modern telah menyertakan paket SELinux policy untuk EL10.

## 4. KONFIGURASI JARINGAN, FIREWALL (FIREWALLD) & CLOUD SECURITY RULES

Wazuh Server membutuhkan port terbuka berikut:

| PORT / PROTOKOL | ARAH TRAFIK | SUMBER / TUJUAN | FUNGSI |
| :--- | :--- | :--- | :--- |
| 1514 / TCP | Inbound | Semua Wazuh Agent | Komunikasi Data & Event Agent |
| 1515 / TCP | Inbound | Semua Wazuh Agent | Pendaftaran Agent (Authd) |
| 55000 / TCP | Inbound | Dashboard / API CLI | RESTful API Wazuh Manager |
| 443 / TCP | Inbound | Admin / SOC Browser | Akses HTTPS Wazuh Dashboard |
| 9200 / TCP | Localhost | Internal / Manager | Wazuh Indexer OpenSearch API |
| 9300-9400 / TCP | Internal | Antar-Node Indexer | Komunikasi Cluster (Multi-node) |

### 4.1 Konfigurasi Firewalld di AlmaLinux 10

sudo systemctl enable --now firewalld

# Buka port yang dibutuhkan untuk akses luar / agent
sudo firewall-cmd --permanent --add-port=1514/tcp
sudo firewall-cmd --permanent --add-port=1515/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=55000/tcp

# Reload aturan firewall
sudo firewall-cmd --reload

# Verifikasi port yang aktif
sudo firewall-cmd --list-ports

### 4.2 Catatan Khusus Oracle Cloud (OCI) & Cloud Security Lists / Groups

Jika VM AlmaLinux 10 Anda berada di Oracle Cloud (user `opc`) atau AWS/GCP:
1. Pastikan Ingress Rule pada VCN Security List / Network Security Group (NSG) 
```text
mengizinkan:
```

   - Port 443 TCP dari IP Public Administrator / Kantor
   - Port 1514 TCP dari seluruh Subnet/IP Agent Client
   - Port 1515 TCP dari seluruh Subnet/IP Agent Client
2. OCI Image terkadang memiliki aturan default `iptables` tambahan. Pastikan 
   chain INPUT tidak memblokir port tersebut:
```bash
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 1514 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 1515 -j ACCEPT
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
```

## 5. METODE 1: INSTALASI OTOMATIS (WAZUH ASSISTANT - REKOMENDASI UTAMA)

#### Metode ini adalah cara paling stabil, cepat, dan direkomendasikan langsung oleh

dokumentasi resmi Wazuh untuk instalasi single-host All-in-One.

### 5.1 Unduh Skrip Installer Terbaru

Pindah ke direktori home atau working directory:
cd ~

# CATATAN PENTING:
# Jangan gunakan URL path generic '4.x' (packages.wazuh.com/4.x/wazuh-install.sh).
# AWS S3 / CloudFront Wazuh tidak mendukung path '4.x' untuk script installer, dan
# akan mengembalikan file XML '<Error><Code>AccessDenied</Code></Error>'.
# Wajib sebutkan versi minor rilis target (misal: 4.14 untuk v4.14.x stabil terbaru):

# Hapus file corrupted / XML jika sebelumnya pernah mencoba unduh via 4.x:
rm -f wazuh-install.sh

# Unduh skrip installer Wazuh v4.14:
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh

# Verifikasi integritas file script (harus diawali '#!/bin/bash'):
head -n 5 wazuh-install.sh

### 5.2 Eksekusi Instalasi All-in-One

Jalankan skrip instalasi dengan opsi `-a` (All-in-One: Indexer, Manager, Dashboard):
sudo bash ./wazuh-install.sh -a

Catatan Proses Instalasi:
- Skrip akan mendeteksi arsitektur dan sistem operasi AlmaLinux 10.
- Skrip akan mengunduh paket RPM resmi Wazuh, menghasilkan sertifikat SSL/TLS lokal,
  mengkonfigurasi internal users, menginstal Wazuh Indexer, Wazuh Server, Filebeat,
  dan Wazuh Dashboard.
- Durasi proses berkisar antara 5 hingga 15 menit tergantung kecepatan internet & CPU.

Output Sukses:
Pada akhir proses, installer akan menampilkan informasi penting:
## --- Summary --- - - Wazuh indexer installation finished. - - Wazuh server installation finished. - - Wazuh dashboard installation finished. - The password for 'admin' user is: <GENERATED_PASSWORD_DISINI>

### 5.3 Ekstraksi & Pengamanan File Password (`wazuh-passwords.txt`)

Installer membuat file arsip `wazuh-install-files.tar` yang berisi seluruh sertifikat 
dan file kredensial penting `wazuh-passwords.txt`.

# Ekstrak file password
sudo tar -O -xvf wazuh-install-files.tar wazuh-passwords.txt > wazuh-passwords.txt

# Berikan hak akses ketat (Hanya root / admin)
sudo chmod 600 wazuh-passwords.txt

# Lihat password admin dan user internal lainnya
cat wazuh-passwords.txt

PENTING:
Simpan file `wazuh-passwords.txt` dan `wazuh-install-files.tar` di tempat yang 
aman (misal password vault). Arsip ini diperlukan di masa mendatang jika Anda 
ingin menambah node cluster atau melakukan regenerasi sertifikat!

## 6. METODE 2: INSTALASI TERBIMBING / CUSTOM CONFIG (`config.yml`)

Jika Anda ingin menentukan IP privat/publik spesifik, custom password, atau nama 
node sebelum instalasi berjalan, gunakan opsi custom config:

### 6.1 Unduh Konfigurasi Awal

curl -sO https://packages.wazuh.com/4.14/config.yml
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh

### 6.2 Modifikasi `config.yml` Sesuai IP AlmaLinux 10

Buka file `config.yml`:
nano config.yml

Sesuaikan bagian node:
nodes:
```text
indexer:
```

    - name: node-1
```text
    ip: "<IP_SERVER_ALMALINUX_ANDA>"
server:
```

    - name: wazuh-1
```text
    ip: "<IP_SERVER_ALMALINUX_ANDA>"
dashboard:
```

    - name: dashboard
```text
ip: "<IP_SERVER_ALMALINUX_ANDA>"
```

### 6.3 Generate File Konfigurasi & Sertifikat

bash wazuh-install.sh --generate-config-files

### 6.4 Instal Komponen Secara Bertahap

# 1. Install Wazuh Indexer
sudo bash wazuh-install.sh --wazuh-indexer node-1
sudo bash wazuh-install.sh --start-cluster

# 2. Install Wazuh Server & Filebeat
sudo bash wazuh-install.sh --wazuh-server wazuh-1

# 3. Install Wazuh Dashboard
sudo bash wazuh-install.sh --wazuh-dashboard dashboard

## 7. AKSES & MANAJEMEN AWAL WAZUH DASHBOARD WEB UI

Setelah instalasi selesai:

1. Buka web browser dari komputer Anda:
```text
https://<IP_PUBLIC_ATAU_DOMAIN_SERVER_ALMALINUX>
```

2. Peringatan SSL/TLS Browser (Self-Signed Certificate):
   Karena menggunakan sertifikat yang dibuat secara lokal oleh assistant, browser 
   akan memunculkan peringatan "Your connection is not private".
   Klik "Advanced" -> "Proceed to ... (unsafe)".
   (Untuk produksi publik, Anda dapat mengintegrasikan Let's Encrypt atau AWS ALB).

3. Login Kredensial:
   - Username : `admin`
   - Password : <Password yang tertera pada wazuh-passwords.txt>

4. Halaman Dashboard:
   Wazuh Web Console akan memuat modul pengawasan, grafik keamanan, matriks MITRE 
   ATT&CK, status agent, dan alert keamanan secara real-time.

## 8. KONFIGURASI REGISTRASI AGENT DI SISI MANAGER (`authd`)

Agar agent client AlmaLinux 10 dapat mendaftarkan diri secara aman ke server:

### 8.1 Konfigurasi Password Registrasi (authd.pass)

Sangat disarankan menggunakan authentication password untuk mencegah endpoint tidak 
dikenal mendaftar ke server Anda:

# Buat file authd.pass
echo "KunciRahasiaPendaftaranWazuh2026!" | sudo tee /var/ossec/etc/authd.pass

# Set permission file agar hanya terbaca oleh wazuh
sudo chown root:wazuh /var/ossec/etc/authd.pass
sudo chmod 640 /var/ossec/etc/authd.pass

### 8.2 Optimasi Konfigurasi Authd di `/var/ossec/etc/ossec.conf`

Buka konfigurasi Wazuh Manager:
sudo nano /var/ossec/etc/ossec.conf

Cari blok `<auth>` dan sesuaikan parameter berikut:
  <auth>
    <disabled>no</disabled>
    <port>1515</port>
    <use_source_ip>no</use_source_ip>
    <purge>yes</purge>
    <use_password>yes</use_password>
    <limit_maxagents>yes</limit_maxagents>
    <ciphers>HIGH:!ADH:!EXP:!MD5:!RC4:!3DES:!CAMELLIA:@STRENGTH</ciphers>
    <!-- Izinkan replace IP/ID jika ada agent re-install dengan nama yang sama -->
    <force_insert>yes</force_insert>
    <force_time>0</force_time>
  </auth>

Restart Wazuh Manager setelah mengubah konfigurasi:
sudo systemctl restart wazuh-manager

## 9. PEMERIKSAAN STATUS LAYANAN & HEALTH CHECK SISTEM

Lakukan serangkaian pengujian berikut di AlmaLinux 10 untuk memastikan semua 
komponen bekerja normal:

### 9.1 Periksa Status Systemd Semua Komponen

sudo systemctl status wazuh-indexer --no-pager
sudo systemctl status wazuh-manager --no-pager
sudo systemctl status filebeat --no-pager
sudo systemctl status wazuh-dashboard --no-pager

Pastikan keempat service berstatus: `active (running)`.

### 9.2 Pengujian Endpoint OpenSearch / Wazuh Indexer

# Ekstrak password kadmin / admin dari wazuh-passwords.txt
INDEXER_PASS=$(sudo grep -oP "(?<=indexer_admin': ')[^']*" wazuh-passwords.txt 2>/dev/null || sudo grep "admin" wazuh-passwords.txt | awk '{print $NF}' | head -n 1)

# Uji query cluster health
curl -k -u admin:${INDEXER_PASS} https://127.0.0.1:9200/_cluster/health?pretty

Respon normal:
{
  "cluster_name" : "wazuh-cluster",
  "status" : "green",   <-- atau "yellow" jika single-node
  "number_of_nodes" : 1,
  ...
}

### 9.3 Pengujian RESTful API Wazuh Manager (Port 55000)

curl -k -X GET https://127.0.0.1:55000/
# Output harus merespon pesan JSON Wazuh API.

### 9.4 Periksa Port Listening di Kernel

sudo ss -tulpn | grep -E '1514|1515|55000|9200|443'

## 10. PEMELIHARAAN, MANAJEMEN INDEKS (ISM) & BACKUP DATA

### 10.1 Manajemen Retensi Log (Index State Management - ISM)

Secara default, Wazuh mengindeks alert ke dalam format harian:
`wazuh-alerts-4.x-YYYY.MM.DD`
Untuk mencegah disk penuh di server AlmaLinux 10:
- Buka Wazuh Dashboard -> Menu Hamburger (Kiri Atas) -> Index Management -> State Management Policies.
- Atur rollover policy (misalnya simpan log selama 90 hari, lalu otomatis hapus/delete).

### 10.2 Backup Rutin Komponen Kunci

File dan folder yang wajib di-backup secara berkala:
1. Konfigurasi & Kunci Enkripsi Agent:
   - `/var/ossec/etc/` (termasuk `client.keys`, `ossec.conf`, `rules/`, `decoders/`)
2. Sertifikat TLS:
   - `/etc/wazuh-indexer/certs/`
   - `/etc/wazuh-dashboard/certs/`
   - `/etc/filebeat/certs/`
3. Kredensial:
   - `wazuh-passwords.txt`

Contoh Skrip Backup Cepat:
sudo tar -czvf /backup/wazuh-backup-$(date +%F).tar.gz \
```text
/var/ossec/etc \
```

    /etc/filebeat/filebeat.yml \
    /etc/wazuh-dashboard/opensearch_dashboards.yml \
    /etc/wazuh-indexer/opensearch.yml

## 11. TROUBLESHOOTING KOMPREHENSIF MASALAH DI ALMALINUX 10

Kasus 1: Wazuh Indexer Gagal Start (`Active: failed` atau Crash Saat Boot)
Penyebab: 
Nilai `vm.max_map_count` di bawah 262144 atau alokasi RAM Java Heap terlalu besar.
Solusi:
1. Pastikan kernel sysctl telah di-set:
```bash
sudo sysctl -w vm.max_map_count=262144
```

2. Cek alokasi RAM heap di `/etc/wazuh-indexer/jvm.options`:
```bash
sudo nano /etc/wazuh-indexer/jvm.options
```

   Pastikan `-Xms` dan `-Xmx` diset setengah dari total RAM server (misal server 8GB -> `-Xms4g` dan `-Xmx4g`).
3. Cek log error lengkap:
```bash
sudo cat /var/log/wazuh-indexer/wazuh-cluster.log | tail -n 50
```

Kasus 2: Wazuh Dashboard Menampilkan Pesan "Wazuh server is not active"
Penyebab:
Kredensial API antara Dashboard dan Wazuh Manager tidak sinkron, atau port 55000 terblokir.
Solusi:
1. Cek status API service di server:
```bash
sudo systemctl status wazuh-manager
```

2. Verifikasi konfigurasi `/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml`.
3. Restart dashboard:
```bash
sudo systemctl restart wazuh-dashboard
```

Kasus 3: Agent Client Tidak Bisa Mendaftar (Connection Timed Out / Refused)
Penyebab:
Firewalld di AlmaLinux 10 atau Security Group Cloud belum membuka port 1514 dan 1515 TCP.
Solusi:
1. Cek port di server:
```bash
sudo ss -tulpn | grep -E '1514|1515'
```

2. Uji dari client dengan perintah:
```text
nc -zvw3 <IP_SERVER> 1514
nc -zvw3 <IP_SERVER> 1515
```

3. Pastikan firewalld mengizinkan trafik:
```bash
sudo firewall-cmd --list-ports
```

Kasus 4: Reset Password Admin Wazuh Dashboard / Indexer
Jika password admin hilang atau lupa:
1. Jalankan skrip securityadmin bawaan Wazuh Indexer:
```bash
cd /usr/share/wazuh-indexer/plugins/opensearch-security/tools/
export JAVA_HOME=/usr/share/wazuh-indexer/jdk/
sudo ./wazuh-passwords-tool.sh --change-password --user admin -p "PasswordBaruAnda123!"
```

Kasus 5: File wazuh-install.sh Berisi Error "<Error><Code>AccessDenied</Code></Error>"
Gejala:
File `wazuh-install.sh` hanya berukuran 111 byte dan berisi file XML error:
<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>
Penyebab:
Menggunakan URL '4.x' (contoh: https://packages.wazuh.com/4.x/wazuh-install.sh). Di AWS S3 / CloudFront milik repositori Wazuh, direktori alias generic '4.x' tidak disediakan untuk file script installer dan listing direktori dinonaktifkan, sehingga Amazon S3 mereturn pesan AccessDenied bukannya file script.
Solusi:
1. Hapus file error XML tersebut:
```text
rm -f wazuh-install.sh
```

2. Unduh kembali dengan menyertakan versi minor spesifik (misal: 4.14):
```bash
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh
```

3. Verifikasi dengan head (wajib menampilkan baris '#!/bin/bash'):
```text
head -n 5 wazuh-install.sh
```

4. Jalankan kembali instalasi:
```bash
sudo bash ./wazuh-install.sh -a
```

## 12. CHEAT SHEET PERINTAH PENTING & LOKASI FILE / LOG UTAMA

Direktori & File Konfigurasi Kunci:

| Komponen | Lokasi Konfigurasi | Lokasi Log |
| :--- | :--- | :--- |
| Wazuh Manager | /var/ossec/etc/ossec.conf | /var/ossec/logs/ossec.log |
| Kunci Agent | /var/ossec/etc/client.keys | - |
| Aturan/Rules | /var/ossec/etc/rules/local_rules.xml | - |
| Wazuh Indexer | /etc/wazuh-indexer/opensearch.yml | /var/log/wazuh-indexer/ |
| Wazuh Dashboard | /etc/wazuh-dashboard/opensearch_dashboards.yml | /usr/share/wazuh-dashboard/logs/ |
| Filebeat | /etc/filebeat/filebeat.yml | /var/log/filebeat/ |

Perintah Manajemen Layanan (Systemd):

---

# Start / Stop / Restart Seluruh Ekosistem:
sudo systemctl restart wazuh-indexer wazuh-manager filebeat wazuh-dashboard

# Cek Status:
sudo systemctl status wazuh-indexer wazuh-manager filebeat wazuh-dashboard

# Cek Agent yang Terdaftar via CLI Server:
sudo /var/ossec/bin/manage_agents -l

# Cek Monitoring Agent Aktif Real-Time:
sudo /var/ossec/bin/agent_control -l
## SELESAI - PANDUAN WAZUH SERVER ALMALINUX 10
