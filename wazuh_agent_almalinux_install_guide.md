# PANDUAN LENGKAP: INSTALASI & KONFIGURASI WAZUH AGENT (CLIENT) - ALMALINUX 10 (LAVENDER LION / EL10)

Dokumen ini adalah panduan teknis operasional terpisah untuk instalasi, registrasi
(enrollment), konfigurasi modul keamanan (FIM, Log Collection, SCA, Active Response),
dan troubleshooting Wazuh Agent pada endpoint klien berbasis AlmaLinux 10.x 
(Platform EL10) yang terhubung ke Wazuh Server.

### INFORMASI SPESIFIKASI KLIEN TARGET

- OS Target         : AlmaLinux 10.2 (Lavender Lion) / Platform: el10
- Arsitektur        : x86_64 / aarch64
- Package Manager   : DNF 5 (`dnf`)
- Init System       : Systemd (cgroups v2)
- Keamanan Default  : SELinux Enforcing, Firewalld Active
- Kompatibilitas    : Wazuh Agent v4.x (Aturan: Versi Agent <= Versi Server)

## DAFTAR ISI

1.  Arsitektur & Alur Pendaftaran (Enrollment) Agent-ke-Server
2.  Aturan Kompatibilitas Versi Mutlak (The Golden Rule)
3.  Prasyarat Jaringan, Firewall Outbound & Matriks Port
4.  Konfigurasi Repository Resmi Wazuh di AlmaLinux 10
5.  Metode 1: Instalasi & Registrasi Otomatis (Auto-Enrollment via DNF)
    - 5.1 Satu Perintah Instalasi dengan Environment Variables
    - 5.2 Mengaktifkan dan Menjalankan Service Agent
6.  Metode 2: Instalasi Manual & Registrasi Interaktif CLI (`agent-auth`)
    - 6.1 Instalasi Paket Binary `wazuh-agent`
    - 6.2 Registrasi Manual Menggunakan Tool `agent-auth`
    - 6.3 Verifikasi Kunci Kriptografi (`client.keys`)
7.  Penanganan Karakteristik Khusus AlmaLinux 10 (EL10)
    - 7.1 SELinux Policy & Validasi Audit
    - 7.2 Integrasi Log: Systemd Journald vs Auditd vs `/var/log/secure`
    - 7.3 Batasan Resource Agent via Systemd CGroups v2 (CPU & RAM Capping)
8.  Konfigurasi Lanjutan Modul Keamanan Endpoint (`/var/ossec/etc/ossec.conf`)
    - 8.1 File Integrity Monitoring (FIM / syscheck) Real-time & Whodata
    - 8.2 Security Configuration Assessment (SCA) & CIS Benchmark
    - 8.3 Pengumpulan Log Sistem & Aplikasi (Auditd, Secure, Webserver)
    - 8.4 Active Response (Auto-Block Serangan via Firewalld)
9.  Verifikasi Status Koneksi & Health Check (Client & Server Side)
10. Skrip Otomasi Deployment Massal (Bash Script / Cloud-Init / Ansible)
11. Troubleshooting Masalah Koneksi Agent di AlmaLinux 10
12. Cheat Sheet Perintah Penting & Lokasi Direktori Kunci

## 1. ARSITEKTUR & ALUR PENDAFTARAN (ENROLLMENT) AGENT-KE-SERVER

Wazuh Agent adalah service background ringan (daemon `wazuh-agentd`) yang bertugas
mengumpulkan data telemetri keamanan lokal dan mengirimkannya ke Wazuh Server.

Alur Kerja Pendaftaran & Komunikasi:
1. Tahap 1: Registrasi (Port 1515 TCP - Authd Service)
   - Agent menghubungi endpoint `authd` pada Wazuh Server.
   - Agent mengirim nama hostname/identitas dan registration password (jika diaktifkan).
   - Server memvalidasi request, memberikan ID unik (misal: `002`), dan menghasilkan
     kunci kriptografi 128-bit simetris.
   - Kunci tersebut disimpan di klien pada: `/var/ossec/etc/client.keys`.

2. Tahap 2: Pengiriman Event & Monitoring (Port 1514 TCP - Remoted Service)
   - Setelah kunci tersimpan, agent membuka koneksi terenkripsi dua arah dengan
     server melalui Port 1514 TCP.
   - Agent mengirimkan deteksi integritas file, audit log sistem, scan kerentanan,
     dan heartbeats secara berkala.

## 2. ATURAN KOMPATIBILITAS VERSI MUTLAK (THE GOLDEN RULE)

Dalam arsitektur Wazuh berlaku aturan mutlak:
   "VERSI WAZUH AGENT HARUS LEBIH RENDAH ATAU SAMA DENGAN VERSI WAZUH SERVER"
   (Agent Version <= Manager Version)

Contoh Kondisi:
- Server: v4.14.7  |  Agent: v4.14.7  --> VALID (Direkomendasikan)
- Server: v4.14.7  |  Agent: v4.9.2   --> VALID (Backward compatible)
- Server: v4.9.2   |  Agent: v4.14.7  --> GAGAL / DITOLAK!

PENTING:
Jika server Anda belum di-upgrade dan agent diinstall versi yang lebih tinggi, 
server akan menolak registrasi dengan pesan error:
"ERROR: Agent version must be lower or equal to manager version"
Pastikan versi server Anda diperbarui terlebih dahulu, atau pasang agent dengan versi 
yang sesuai dengan server Anda.

## 3. PRASYARAT JARINGAN, FIREWALL OUTBOUND & MATRIKS PORT

Dari sisi client AlmaLinux 10, Anda HANYA perlu memastikan lalu lintas KELUAR 
(Egress / Outbound) ke arah Wazuh Server diizinkan:

| PORT / PROTOKOL | ARAH TRAFIK | TUJUAN | KEPERLUAN |
| :--- | :--- | :--- | :--- |
| 1514 / TCP | Outbound | IP Wazuh Server | Pengiriman Event & Alert Keamanan |
| 1515 / TCP | Outbound | IP Wazuh Server | Pendaftaran Agent Baru (Authd) |

### 3.1 Tes Konektivitas Port dari Client AlmaLinux 10

Sebelum menginstall, uji keterjangkauan port server dari terminal client:

# Menggunakan tool nc (netcat) atau bash TCP test:
nc -zvw3 <IP_WAZUH_SERVER> 1514
nc -zvw3 <IP_WAZUH_SERVER> 1515

Contoh Output Sukses:
Connection to <IP_WAZUH_SERVER> 1514 port [tcp/*] succeeded!
Connection to <IP_WAZUH_SERVER> 1515 port [tcp/*] succeeded!

## 4. KONFIGURASI REPOSITORY RESMI WAZUH DI ALMALINUX 10

AlmaLinux 10 menggunakan manajer paket DNF 5. Siapkan repository RPM Wazuh resmi:

### 4.1 Import GPG Key Wazuh

sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

### 4.2 Tambahkan File Konfigurasi Repository

sudo bash -c 'cat << EOF > /etc/yum.repos.d/wazuh.repo
[wazuh]
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
EOF'

### 4.3 Bersihkan Cache & Verifikasi Repo

sudo dnf clean all
sudo dnf makecache
sudo dnf repoquery -i wazuh-agent

## 5. METODE 1: INSTALASI & REGISTRASI OTOMATIS (AUTO-ENROLLMENT VIA DNF)

#### Metode ini adalah cara tercepat dan paling elegan karena langsung melakukan

download, install, konfigurasi manager IP, nama agent, dan enrollment dalam satu langkah.

### 5.1 Eksekusi Perintah Satu Baris

Ganti variabel berikut dengan parameter server Anda:
- `WAZUH_MANAGER`: Alamat IP privat / domain Wazuh Server
- `WAZUH_AGENT_NAME`: Nama hostname pengenal untuk endpoint ini
- `WAZUH_REGISTRATION_PASSWORD`: Password yang diset di server (`/var/ossec/etc/authd.pass`)
- `WAZUH_AGENT_GROUP`: Nama grup di server (default: `default`)

Jalankan:
sudo WAZUH_MANAGER="10.0.1.50" \
```bash
WAZUH_AGENT_NAME="almalinux10-client-01" \
WAZUH_REGISTRATION_PASSWORD="KunciRahasiaPendaftaranWazuh2026!" \
WAZUH_AGENT_GROUP="default" \
dnf install -y wazuh-agent
```

### 5.2 Aktifkan & Jalankan Service Wazuh Agent

sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent

### 5.3 Cek Status Layanan

sudo systemctl status wazuh-agent --no-pager

## 6. METODE 2: INSTALASI MANUAL & REGISTRASI INTERAKTIF CLI (`agent-auth`)

Gunakan metode ini jika Anda ingin melakukan instalasi paket terlebih dahulu, 
kemudian mendaftarkan agent secara manual via tool command line `agent-auth`.

### 6.1 Instal Paket Binary Wazuh Agent

sudo dnf install -y wazuh-agent

### 6.2 Registrasi Manual Menggunakan `agent-auth`

Tool `agent-auth` bertugas berkomunikasi langsung ke port 1515 Wazuh Server:

sudo /var/ossec/bin/agent-auth \
     -m <IP_WAZUH_SERVER> \
     -p 1515 \
     -A "almalinux10-client-01" \
     -P "KunciRahasiaPendaftaranWazuh2026!"

Contoh Output Sukses:
2026/09/11 17:00:00 agent-auth: INFO: Started (pid: 12345).
2026/09/11 17:00:00 agent-auth: INFO: Connected to <IP_WAZUH_SERVER>:1515
2026/09/11 17:00:01 agent-auth: INFO: Using agent name: almalinux10-client-01
2026/09/11 17:00:01 agent-auth: INFO: Valid key received.
2026/09/11 17:00:01 agent-auth: INFO: Connection closed

### 6.3 Verifikasi Pembuatan Kunci Kriptografi

Periksa apakah file `/var/ossec/etc/client.keys` telah terisi:
sudo cat /var/ossec/etc/client.keys

Format isi file:
ID_AGENT NAMA_AGENT IP_AGENT CRYPTOGRAPHIC_KEY
Contoh:
002 almalinux10-client-01 any a1b2c3d4e5f6...

### 6.4 Konfigurasi Alamat Manager pada `ossec.conf`

Buka file `/var/ossec/etc/ossec.conf`:
sudo nano /var/ossec/etc/ossec.conf

Pastikan blok `<client><server>` mengarah ke server Anda:
```text
<client>
  <server>
    <address><IP_WAZUH_SERVER></address>
    <port>1514</port>
    <protocol>tcp</protocol>
  </server>
</client>
```

### 6.5 Start Layanan Agent

sudo systemctl enable --now wazuh-agent

## 7. PENANGANAN KARAKTERISTIK KHUSUS ALMALINUX 10 (EL10)

AlmaLinux 10 membawa perubahan platform Linux enterprise generasi terbaru:

### 7.1 SELinux Policy & Validasi Audit

Secara default, binary `/var/ossec/bin/*` dan service `wazuh-agent` memiliki konteks 
SELinux yang sesuai melalui paket RPM resmi.
Jika Anda menemukan error "Permission Denied" pada log `/var/log/audit/audit.log`:

# Cek apakah ada denial SELinux terkait wazuh
sudo ausearch -m avc -ts recent | grep wazuh

# Izinkan jika diperlukan
sudo setsebool -P nis_enabled 1 2>/dev/null || true

### 7.2 Integrasi Sumber Log Sistem (Systemd Journald & Auditd)

AlmaLinux 10 menggunakan `systemd-journald` dan `auditd`.
Pastikan service auditd aktif agar Wazuh dapat memonitor eksekusi perintah dan login:
sudo systemctl enable --now auditd

### 7.3 Batasan Resource Agent via Systemd CGroups v2 (Resource Capping)

Untuk memastikan proses monitoring agent tidak membebani performa aplikasi utama 
(misal database atau aplikasi Java) di AlmaLinux 10:

sudo mkdir -p /etc/systemd/system/wazuh-agent.service.d/
sudo bash -c 'cat << EOF > /etc/systemd/system/wazuh-agent.service.d/override.conf
[Service]
# Batasi penggunaan CPU maksimal 20% dari 1 Core
CPUQuota=20%
# Batasi alokasi memori RAM maksimal 512 MB
MemoryMax=512M
# Prioritas proses I/O dan CPU rendah
Nice=10
CPUSchedulingPolicy=idle
EOF'

# Terapkan perubahan:
sudo systemctl daemon-reload
sudo systemctl restart wazuh-agent

## 8. KONFIGURASI LANJUTAN MODUL KEAMANAN ENDPOINT (`ossec.conf`)

Edit file `/var/ossec/etc/ossec.conf` untuk menyesuaikan kapabilitas monitoring:

### 8.1 File Integrity Monitoring (FIM / syscheck) Real-time & Whodata

Pantau perubahan file penting (direktori sistem, konfigurasi, SSH keys):
  <syscheck>
    <disabled>no</disabled>
    <frequency>43200</frequency> <!-- Scan berkala setiap 12 jam -->
    <scan_on_start>yes</scan_on_start>

    <!-- Direktori Kritis dengan Pemantauan Real-time -->
    <directories realtime="yes" check_all="yes">/etc,/usr/bin,/usr/sbin</directories>
    <directories realtime="yes" check_all="yes">/root/.ssh,/home/*/.ssh</directories>

    <!-- Direktori Dinamis yang Diabaikan (Whitelist) -->
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/adjtime</ignore>
  </syscheck>

### 8.2 Security Configuration Assessment (SCA) & CIS Benchmark

Modul ini memeriksa apakah konfigurasi OS AlmaLinux 10 Anda mematuhi standar CIS:
  <sca>
    <enabled>yes</enabled>
    <scan_on_start>yes</scan_on_start>
    <interval>12h</interval>
    <skip_nfs>yes</skip_nfs>
  </sca>

### 8.3 Pengumpulan Log Sistem & Aplikasi Lokal

Pantau log autentikasi, log kernel, dan pesan sistem:
```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/secure</location>
</localfile>

<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/messages</location>
</localfile>

<localfile>
  <log_format>audit</log_format>
  <location>/var/log/audit/audit.log</location>
</localfile>
```

### 8.4 Active Response (Auto-Block IP Penyerang via Firewalld)

Pastikan modul Active Response aktif di client agar agent dapat otomatis mengeksekusi 
pemblokiran IP brute force SSH pada Firewalld lokal:
  <active-response>
    <disabled>no</disabled>
  </active-response>

Setelah selesai mengedit, restart agent:
sudo systemctl restart wazuh-agent

## 9. VERIFIKASI STATUS KONEKSI & HEALTH CHECK

### 9.1 Verifikasi di Sisi Client (AlmaLinux 10)

1. Cek status service:
```bash
sudo systemctl status wazuh-agent --no-pager
```

2. Cek log operasional agent:
```bash
sudo tail -n 30 /var/ossec/logs/ossec.log
```

   Log sukses koneksi yang normal:
   ... wazuh-agentd: INFO: (4102): Connected to the server (<IP_WAZUH_SERVER>:1514/tcp).
   ... wazuh-agentd: INFO: Server IP changed or connection reset. Connected to server.

3. Cek koneksi socket aktif:
```bash
sudo ss -tanp | grep 1514
```

### 9.2 Verifikasi di Sisi Wazuh Server (Manager)

Dari server Wazuh (`trees-wazuh-prod`), jalankan:
# List agent yang terdaftar dan status koneksinya:
sudo /var/ossec/bin/agent_control -l

Contoh Output:
Wazuh agent_control. List of available agents:
```text
ID: 000, Name: trees-wazuh-prod (server), IP: 127.0.0.1, Active/Local
ID: 002, Name: almalinux10-client-01, IP: any, Active
```

Status `Active` menandakan agent telah terhubung sempurna dan mengirim telemetri.

## 10. SKRIP OTOMASI DEPLOYMENT MASSAL (CLOUD-INIT / USER DATA)

Jika Anda meluncurkan banyak instance AlmaLinux 10 di Cloud (OCI Compute, AWS EC2, OpenStack), 
gunakan skrip Cloud-Init berikut pada kolom User Data saat peluncuran VM:

#!/usr/bin/env bash
set -e

WAZUH_SERVER_IP="10.0.1.50"
AUTH_PASSWORD="KunciRahasiaPendaftaranWazuh2026!"
AGENT_NAME="alma10-$(hostname -s)-$(date +%s)"

# 1. Setup Repo Wazuh
rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
cat << 'EOF' > /etc/yum.repos.d/wazuh.repo
[wazuh]
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
EOF

# 2. Install & Auto-Register
WAZUH_MANAGER="${WAZUH_SERVER_IP}" \
WAZUH_AGENT_NAME="${AGENT_NAME}" \
WAZUH_REGISTRATION_PASSWORD="${AUTH_PASSWORD}" \
dnf install -y wazuh-agent

# 3. Start Service
systemctl daemon-reload
systemctl enable --now wazuh-agent

## 11. TROUBLESHOOTING MASALAH KONEKSI AGENT DI ALMALINUX 10

Kasus 1: Error "Agent version must be lower or equal to manager version"
Penyebab: 
Versi paket agent yang diinstal di AlmaLinux 10 lebih tinggi daripada versi 
Wazuh Server Anda.
Solusi:
1. Periksa versi manager: `/var/ossec/bin/wazuh-control info` di sisi server.
2. Downgrade versi agent di client ke versi yang sama dengan server:
```bash
sudo dnf downgrade -y wazuh-agent-<VERSI_MANAGER>
sudo systemctl restart wazuh-agent
```

Kasus 2: Error "Connection refused" atau "Unable to connect to manager"
Penyebab:
Firewalld di sisi server, atau Cloud Security List memblokir port 1514 atau 1515 TCP.
Solusi:
1. Uji koneksi dari client:
```text
nc -zvw3 <IP_SERVER> 1514
```

2. Pastikan port 1514 dan 1515 telah diizinkan di Firewalld server:
```bash
sudo firewall-cmd --permanent --add-port=1514/tcp
sudo firewall-cmd --permanent --add-port=1515/tcp
sudo firewall-cmd --reload
```

Kasus 3: Error "Invalid key for server" / Authd Error
Penyebab:
Kunci di `/var/ossec/etc/client.keys` tidak cocok dengan database server (misal ID terhapus).
Solusi:
1. Stop agent:
```bash
sudo systemctl stop wazuh-agent
```

2. Hapus file client.keys lama:
```bash
sudo rm -f /var/ossec/etc/client.keys
```

3. Lakukan registrasi ulang:
```bash
sudo /var/ossec/bin/agent-auth -m <IP_SERVER> -p 1515 -A <NAMA_AGENT> -P "<PASSWORD>"
```

4. Start kembali agent:
```bash
sudo systemctl start wazuh-agent
```

## 12. CHEAT SHEET PERINTAH PENTING & LOKASI DIREKTORI KUNCI

Direktori & File Konfigurasi di AlmaLinux 10:

| Fungsi | Path Lengkap |
| :--- | :--- |
| Konfigurasi Utama Agent | /var/ossec/etc/ossec.conf |
| Kunci Enkripsi (Auth) | /var/ossec/etc/client.keys |
| Log Aktivitas Agent | /var/ossec/logs/ossec.log |
| Binary Eksekusi | /var/ossec/bin/ |
| Modul Active Response | /var/ossec/active-response/bin/ |

Perintah Manajemen Layanan (Systemd):

---

# Start / Stop / Restart Agent:
sudo systemctl start wazuh-agent
sudo systemctl stop wazuh-agent
sudo systemctl restart wazuh-agent

# Cek Status Service & Boot:
sudo systemctl status wazuh-agent
sudo systemctl is-enabled wazuh-agent

# Monitoring Log Real-time:
sudo tail -f /var/ossec/logs/ossec.log
## SELESAI - PANDUAN WAZUH AGENT ALMALINUX 10
