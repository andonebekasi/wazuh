# PANDUAN LENGKAP: INSTALASI & KONFIGURASI WAZUH AGENT DI AMAZON LINUX - (AMAZON LINUX 2 & AMAZON LINUX 2023 - AWS EC2 VPC PRODUCTION)

Dokumen ini adalah panduan teknis operasional terpisah dan menyeluruh untuk melakukan 
instalasi, registrasi (enrollment), pengerasan (hardening), dan troubleshooting 
Wazuh Agent pada dua sistem operasi resmi Amazon Web Services (AWS):

1. TARGET 1: Amazon Linux 2 (AL2)
   - Hostname Contoh : hrptrsapprd ([ec2-user@hrptrsapprd ~]$)
   - Versi OS        : Amazon Linux 2 (cpe:2.3:o:amazon:amazon_linux:2)
   - Basis Sistem    : RHEL / CentOS 7
   - Package Manager : YUM (`yum`)
   - Dukungan Resmi  : Maintenance hingga 30 Juni 2025

2. TARGET 2: Amazon Linux 2023 (AL2023)
   - Hostname Contoh : ip-172-1-12-178 ([ec2-user@ip-172-1-12-178 ~]$)
   - Versi OS        : Amazon Linux 2023 (cpe:2.3:o:amazon:amazon_linux:2023)
   - Basis Sistem    : Fedora Upstream
   - Package Manager : DNF (`dnf`) / Symlinked YUM
   - Arsitektur VPC  : Subnet VPC 172.1.0.0/16
   - Dukungan Resmi  : Long-term Support hingga 30 Juni 2029

## DAFTAR ISI

1. Ringkasan Eksekutif & Aliran Komunikasi Agent-to-Manager di AWS VPC
2. Matriks Perbedaan Fundamental: Amazon Linux 2 vs Amazon Linux 2023
3. Prasyarat Jaringan, AWS Security Group Matrix & Pre-Flight Check
4. Step-by-Step Instalasi Wazuh Agent di Amazon Linux 2 (`hrptrsapprd`)
   - 4.1 Import GPG Key & Konfigurasi Repository Wazuh
   - 4.2 Instalasi & Registrasi Otomatis (Auto-Enrollment via YUM)
   - 4.3 Registrasi dengan Registration Password (authd.pass)
   - 4.4 Menjalankan Service & Verifikasi Awal
5. Step-by-Step Instalasi Wazuh Agent di Amazon Linux 2023 (`ip-172-1-12-178`)
   - 5.1 Karakteristik Khusus AL2023 (DNF, Minimal Packages, Crypto Policies)
   - 5.2 Import GPG Key & Konfigurasi Repository Wazuh
   - 5.3 Instalasi & Registrasi Otomatis (Auto-Enrollment via DNF)
   - 5.4 Penanganan SELinux & CGroups v2 di AL2023
   - 5.5 Menjalankan Service & Verifikasi Awal
6. Konfigurasi Lanjutan Modul Keamanan Endpoint (`/var/ossec/etc/ossec.conf`)
   - 6.1 Pengumpulan Log Sistem AWS (`/var/log/messages`, `/var/log/secure`, `audit.log`)
   - 6.2 File Integrity Monitoring (FIM / syscheck) & Whitelist Folder Dinamis
   - 6.3 Security Configuration Assessment (SCA) & CIS Benchmark AWS
   - 6.4 Active Response & Anti-Flooding Buffer Protection
   - 6.5 Throttling CPU & RAM Agent (Systemd Cgroups Resource Limiting)
7. Skrip Otomasi Deployment Massal di AWS
   - 7.1 EC2 User Data Script (Universal Cloud-Init Auto-Detect AL2 & AL2023)
   - 7.2 AWS Systems Manager (SSM) Run Command Script (Zero SSH Deployment)
   - 7.3 Ansible Playbook Dual-Platform AL2 & AL2023
8. Verifikasi Konektivitas & Status di Sisi Wazuh Manager
9. Troubleshooting Komprehensif Kasus Lapangan (AL2 & AL2023)
10. Quick Command Cheat Sheet Khusus Amazon Linux (AL2 & AL2023)

## 1. RINGKASAN EKSEKUTIF & ALIRAN KOMUNIKASI AGENT-TO-MANAGER DI AWS VPC

Dalam topologi AWS EC2, Wazuh Agent dipasang pada server workload (seperti server HR/Payroll 
`hrptrsapprd` dan server backend `ip-172-1-12-178`). Agent berfungsi sebagai sensor keamanan 
lokal yang mengirimkan log sistem, deteksi integritas file, dan metrik kepatuhan ke 
Wazuh Manager melalui jaringan internal VPC (`172.1.0.0/16`).

Alur Registrasi & Komunikasi:
1. Registrasi Awal (Port 1515 TCP):
   Agent menghubungi endpoint Authd di Wazuh Manager untuk mendaftarkan nama host, 
   menerima ID unik (contoh: ID `001`), dan men-generate key enkripsi 128-bit simetris 
   yang disimpan pada file `/var/ossec/etc/client.keys`.
2. Pengiriman Log & Heartbeat (Port 1514 TCP):
   Setelah terdaftar, komunikasi beralih permanen ke Port 1514 TCP. Seluruh data event, 
   alert FIM, dan status kesehatan dikirimkan terenkripsi dua arah.
3. Sinkronisasi Kebijakan Sentral:
   Agent mengunduh konfigurasi grup terpusat (`agent.conf`) dan rootkit signatures 
   langsung dari Manager tanpa intervensi manual.

## 2. MATRIKS PERBEDAAN FUNDAMENTAL: AMAZON LINUX 2 VS AMAZON LINUX 2023

Meskipun keduanya dikembangkan oleh AWS, AL2 dan AL2023 memiliki perbedaan mendasar 
yang memengaruhi cara instalasi dan runtime service:

| KOMPONEN / ASPEK | AMAZON LINUX 2 (AL2) | AMAZON LINUX 2023 (AL2023) |
| :--- | :--- | :--- |
| Host Pengujian | `hrptrsapprd` | `ip-172-1-12-178` |
| Basis Distribusi | RHEL 7 / CentOS 7 | Fedora Upstream |
| Package Manager Utama | `yum` (YUM v3) | `dnf` (DNF v4, yum symlinked) |
| Glibc / System Libraries | glibc 2.26 (Legacy ABI) | glibc 2.34+ (Modern ABI) |
| Crypto Policies | Legacy / Bebas (SHA-1 allowed) | System-wide Policy (`DEFAULT` SHA256+) |
| SELinux | Disabled secara default | Permissive secara default |
| Filesystem Default | XFS / ext4 | XFS Murni (subvolume optimized) |
| Control Groups | CGroups v1 | CGroups v2 murni (`/sys/fs/cgroup`) |
| Paket Bawaan | Full standard utility | Minimal footprint (`curl-minimal`) |
| Repository Releasever | `$releasever` bernilai `2` | `$releasever` bernilai `2023` |
| Akhir Dukungan (EOL) | 30 Juni 2025 | 30 Juni 2029 |

## 3. PRASYARAT JARINGAN, AWS SECURITY GROUP MATRIX & PRE-FLIGHT CHECK

Sebelum mengeksekusi instalasi pada kedua host, pastikan konfigurasi AWS Security Group 
dan routing VPC telah terpenuhi.

### 3.1 ATURAN SECURITY GROUP AWS

#### A. Di Sisi Wazuh Manager (`sg-wazuh-siem`):

   - Port 1515 TCP: Inbound diizinkan dari `172.1.0.0/16` (Registrasi Authd).
   - Port 1514 TCP: Inbound diizinkan dari `172.1.0.0/16` (Komunikasi Agent).
   - All ICMP     : Inbound diizinkan dari `172.1.0.0/16` (Ping Diagnostic).
   - Port 22 TCP  : Inbound diizinkan dari `172.1.0.0/16` (SSH Remote Management).

#### B. Di Sisi Agent EC2 (`sg-agent-nodes` atau SG bawaan host):

   - Outbound Rules: Wajib mengizinkan TCP 1514 dan TCP 1515 menuju IP Wazuh Manager 
     (secara default, AWS Security Group mengizinkan All Outbound `0.0.0.0/0`).

### 3.2 UJI KONEKTIVITAS PRE-FLIGHT DARI TERMINAL INSTANCE

Jalankan uji konektivitas berikut dari masing-masing host:

#### A. Dari terminal `[ec2-user@hrptrsapprd ~]$` (Amazon Linux 2):

```bash
# 1. Tes Ping ICMP
ping -c 3 <IP_WAZUH_MANAGER>

# 2. Tes Port Pendaftaran (1515) & Port Komunikasi (1514) menggunakan nc atau bash socket
# Jika nc belum terpasang: sudo yum install -y nc
nc -zvw3 <IP_WAZUH_MANAGER> 1515
nc -zvw3 <IP_WAZUH_MANAGER> 1514
```

#### B. Dari terminal `[ec2-user@ip-172-1-12-178 ~]$` (Amazon Linux 2023):

```bash
# 1. Tes Ping ICMP
ping -c 3 <IP_WAZUH_MANAGER>

# 2. Tes socket native via bash (tidak memerlukan install netcat tambahan):
```

   (timeout 3 bash -c "</dev/tcp/<IP_WAZUH_MANAGER>/1515") && echo "PORT 1515 TERBUKA" || echo "PORT 1515 DIBLOKIR"
   (timeout 3 bash -c "</dev/tcp/<IP_WAZUH_MANAGER>/1514") && echo "PORT 1514 TERBUKA" || echo "PORT 1514 DIBLOKIR"

Hasil yang diharapkan: Port 1515 dan 1514 terbuka dan berhasil terkoneksi.

## 4. STEP-BY-STEP INSTALASI WAZUH AGENT DI AMAZON LINUX 2 (`hrptrsapprd`)

Target Host: `[ec2-user@hrptrsapprd ~]$`

Langkah 4.1: Import GPG Key Resmi Wazuh
Wazuh menandatangani seluruh paket RPM dengan GPG key resmi. Jalankan:
```bash
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
```

Langkah 4.2: Konfigurasi Repository Wazuh YUM
Buat file repository `/etc/yum.repos.d/wazuh.repo`:
```bash
sudo tee /etc/yum.repos.d/wazuh.repo << 'EOF'
```

[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

Catatan Teknis AL2:
Pada Amazon Linux 2, `$releasever` bernilai `2`. Konfigurasi `baseurl` mengarah langsung 
ke direktori paket YUM 4.x yang kompatibel dengan RHEL/CentOS 7 core pada AL2.

Langkah 4.3: Instalasi Wazuh Agent dengan Auto-Enrollment (Metode Standar)
Ganti `<IP_WAZUH_MANAGER>` dengan IP Private Wazuh Manager Anda (contoh: `172.1.10.50`):

```bash
sudo WAZUH_MANAGER='<IP_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='production,hr-payroll' \
     WAZUH_AGENT_NAME='hrptrsapprd' \
     yum install -y wazuh-agent
```

Keterangan Parameter:
- `WAZUH_MANAGER`: IP Private server Wazuh di dalam VPC 172.1.0.0/16.
- `WAZUH_AGENT_GROUP`: Mengelompokkan host ke grup 'production' dan 'hr-payroll' untuk 
  pemberlakuan aturan sentral (`agent.conf`).
- `WAZUH_AGENT_NAME`: Nama host yang akan muncul di dashboard (disesuaikan dengan `hrptrsapprd`).

Langkah 4.3.B: Opsi Tambahan - Jika Menggunakan Password Registrasi (authd.pass)
Jika Wazuh Manager Anda menerapkan password autentikasi authd:
```bash
sudo WAZUH_MANAGER='<IP_WAZUH_MANAGER>' \
     WAZUH_REGISTRATION_PASSWORD='PasswordRahasiaWazuh123' \
     WAZUH_AGENT_GROUP='production,hr-payroll' \
     WAZUH_AGENT_NAME='hrptrsapprd' \
     yum install -y wazuh-agent
```

Catatan Penting Mengenai WAZUH_REGISTRATION_PASSWORD:
- Nilai 'PasswordRahasiaWazuh123' di atas HANYALAH CONTOH.
- Nilai sebenarnya berasal dari file `/var/ossec/etc/authd.pass` di sisi Wazuh Manager.
- Cara cek di Manager: `sudo cat /var/ossec/etc/authd.pass`
- JIKA output di Manager adalah 'No such file or directory' (default bawaan Wazuh), 
  berarti Manager TIDAK memakai password. Cukup gunakan Langkah 4.3 (Metode Standar) 
  dan HAPUS baris `WAZUH_REGISTRATION_PASSWORD`.
- Penjelasan lengkap dapat dilihat di file 'wazuh_keterangan_tambahan.txt' Bab 13.

Langkah 4.4: Konfigurasi Manual `/var/ossec/etc/ossec.conf` (Opsional/Verifikasi)
Jika Anda menginstal tanpa variabel environment, buka `/var/ossec/etc/ossec.conf` 
dan pastikan blok `<client><server>` berisi:
```bash
sudo sed -i 's/<address>0.0.0.0<\/address>/<address><IP_WAZUH_MANAGER><\/address>/g' /var/ossec/etc/ossec.conf
```

Langkah 4.5: Jalankan dan Aktifkan Service Systemd
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

Langkah 4.6: Verifikasi Status & Log di `hrptrsapprd`
1. Cek status service:
```bash
sudo systemctl status wazuh-agent
```

2. Cek apakah key registrasi berhasil dibuat:
```bash
sudo cat /var/ossec/etc/client.keys
# Output normal menampilkan: <ID> <NAMA_AGENT> <IP> <KEY_HASH>
# Contoh: 001 hrptrsapprd any 7f8a9...
```

3. Pantau log koneksi real-time:
```bash
sudo tail -n 30 -f /var/ossec/logs/ossec.log | grep -E "Connected to the server|Valid key received|Beacon"
```

## 5. STEP-BY-STEP INSTALASI WAZUH AGENT DI AMAZON LINUX 2023 (`ip-172-1-12-178`)

Target Host: `[ec2-user@ip-172-1-12-178 ~]$`

Langkah 5.1: Karakteristik Khusus AL2023 yang Perlu Diperhatikan
1. Package Manager: AL2023 menggunakan `dnf` secara native.
2. Crypto Policies: Kebijakan kriptografi bawaan AL2023 adalah `DEFAULT` (menolak SHA-1 
   dan hanya mengizinkan TLS 1.2+). Repository dan GPG key Wazuh 4.x sudah menggunakan 
   standar SHA-256 modern sehingga kompatibel penuh.
3. Paket Minimal: Image standar AL2023 sangat ramping. Modul dasar seperti `coreutils` 
   sudah tersedia.

Langkah 5.2: Import GPG Key Resmi Wazuh
```bash
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
```

Langkah 5.3: Tambahkan Repository Wazuh DNF/YUM
Buat file repository `/etc/yum.repos.d/wazuh.repo`:
```bash
sudo tee /etc/yum.repos.d/wazuh.repo << 'EOF'
```

[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

Langkah 5.4: Instalasi Wazuh Agent via DNF dengan Auto-Enrollment
Ganti `<IP_WAZUH_MANAGER>` dengan IP Private Wazuh Manager:

```bash
sudo WAZUH_MANAGER='<IP_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='production,backend-vpc' \
     WAZUH_AGENT_NAME='ip-172-1-12-178' \
     dnf install -y wazuh-agent
```

Keterangan:
- Menggunakan perintah modern `dnf install -y wazuh-agent`.
- `WAZUH_AGENT_NAME`: Menggunakan identifier instance `ip-172-1-12-178` atau nama aplikasi 
  yang Anda kehendaki.
- Jika menggunakan password authd, sisipkan: `WAZUH_REGISTRATION_PASSWORD='<PASSWORD>'`.

Langkah 5.5: Verifikasi Status SELinux & CGroups v2 di AL2023
- Cek mode SELinux:
  sestatus
```text
# Pada AL2023, mode standar adalah "permissive". Dalam mode ini, SELinux mencatat 
# audit log tanpa memblokir socket port 1514/1515 Wazuh Agent.
```

- Cek CGroups v2:
  stat -fc %T /sys/fs/cgroup/
```text
# Output: cgroup2fs (Kompatibel penuh dengan isolasi resource systemd Wazuh).
```

Langkah 5.6: Jalankan dan Aktifkan Service Systemd
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

Langkah 5.7: Verifikasi Status & Log di `ip-172-1-12-178`
1. Cek status service:
```bash
sudo systemctl status wazuh-agent
```

2. Cek integritas file `client.keys`:
```bash
sudo cat /var/ossec/etc/client.keys
```

3. Pantau log handshake di `/var/ossec/logs/ossec.log`:
```bash
sudo tail -n 25 /var/ossec/logs/ossec.log | grep -iE "wazuh-agentd|server|connected"
```

## 6. KONFIGURASI LANJUTAN MODUL KEAMANAN ENDPOINT (`/var/ossec/etc/ossec.conf`)

Setelah agent berhasil terkoneksi, sesuaikan konfigurasi `/var/ossec/etc/ossec.conf` 
pada kedua server Amazon Linux agar perlindungan keamanan bekerja optimal:

### 6.1 PENGUMPULAN LOG SISTEM AWS & AUDITD (`<localfile>`)

Secara default di Amazon Linux (AL2 dan AL2023), pastikan entri log berikut aktif 
di dalam tag `<ossec_config>`:

  <!-- Log Sistem Utama Amazon Linux (Syslog / Messages) -->
```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/messages</location>
</localfile>
```

  <!-- Log Autentikasi SSH, Sudo & User Session -->
```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/secure</location>
</localfile>
```

  <!-- Log Linux Audit Daemon (Sangat Kritis untuk PCI-DSS / SOC2) -->
```xml
<localfile>
  <log_format>audit</log_format>
  <location>/var/log/audit/audit.log</location>
</localfile>
```

  <!-- Log Bootstrap Instance AWS EC2 (Cloud-Init) -->
```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/cloud-init.log</location>
</localfile>
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/cloud-init-output.log</location>
</localfile>
```

  <!-- Jika Server Menjalankan Web Server (Nginx / Apache) -->
```xml
<localfile>
  <log_format>apache</log_format>
  <location>/var/log/nginx/access.log</location>
</localfile>
<localfile>
  <log_format>apache</log_format>
  <location>/var/log/nginx/error.log</location>
</localfile>
```

### 6.2 FILE INTEGRITY MONITORING (FIM / SYSCHECK) UNTUK AMAZON LINUX

Konfigurasi pemantauan direktori sistem sensitif dan pengecualian direktori sementara 
agar tidak membebani CPU:

  <syscheck>
    <disabled>no</disabled>
    <frequency>43200</frequency> <!-- Full scan berkala setiap 12 jam -->
    <scan_on_start>yes</scan_on_start>

    <!-- Direktori Kritis yang Dimonitor Realtime -->
    <directories realtime="yes" check_all="yes">/etc,/usr/bin,/usr/sbin</directories>
    <directories realtime="yes" check_all="yes">/bin,/sbin,/boot</directories>
    <directories realtime="yes" check_all="yes">/var/ossec/etc</directories>

    <!-- Direktori Khusus Aplikasi (Contoh: Web App / HR App) -->
    <directories check_all="yes">/var/www/html,/opt</directories>

    <!-- Whitelist Folder Dinamis (Mencegah Flooding Event & High CPU) -->
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/mail/statistics</ignore>
    <ignore>/etc/random-seed</ignore>
    <ignore>/etc/adjtime</ignore>
    <ignore type="sregex">^/tmp</ignore>
    <ignore type="sregex">^/var/tmp</ignore>
    <ignore type="sregex">^/var/log</ignore>
    <ignore type="sregex">^/var/cache</ignore>

    <!-- Pembatasan throughput pembacaan disk (Maksimal 100 EPS) -->
    <max_eps>100</max_eps>
  </syscheck>

### 6.3 SECURITY CONFIGURATION ASSESSMENT (SCA) & CIS BENCHMARK

Wazuh Agent membawa modul SCA untuk mengaudit kepatuhan server terhadap benchmark CIS:
- Pada Amazon Linux 2: Menggunakan policy profile CIS Amazon Linux 2 (`cis_amazon_linux_2.yml`).
- Pada Amazon Linux 2023: Menggunakan policy profile CIS Amazon Linux 2023 / Fedora benchmark.
Pastikan modul SCA aktif:
  <sca>
    <enabled>yes</enabled>
    <scan_on_start>yes</scan_on_start>
    <interval>12h</interval>
    <skip_nfs>yes</skip_nfs>
  </sca>

### 6.4 ANTI-FLOODING BUFFER PROTECTION (PERLINDUNGAN BURST TRAFIK)

Mencegah terputusnya agent akibat lonjakan log aplikasi mendadak:
  <client_buffer>
    <disabled>no</disabled>
    <queue_size>10000</queue_size>
    <events_per_second>500</events_per_second>
  </client_buffer>

### 6.5 PEMBATASAN RESOURCE CPU & RAM AGENT (SYSTEMD CGROUPS SLICE)

Khusus pada instans EC2 tipe Burstable (seperti t3.medium, t3.large, t4g.medium), pasang 
pembatasan konsumsi resource agar agent tidak mengganggu performa aplikasi bisnis:

Jalankan perintah ini di `hrptrsapprd` maupun `ip-172-1-12-178`:
```bash
sudo systemctl set-property wazuh-agent MemoryMax=512M
sudo systemctl set-property wazuh-agent CPUQuota=30%
```

Perintah ini akan membuat drop-in file di `/etc/systemd/system.control/wazuh-agent.service.d/` 
yang membatasi penggunaan RAM maksimal 512 MB dan maksimal 30% dari 1 vCPU core.

## 7. SKRIP OTOMASI DEPLOYMENT MASSAL DI AWS

### 7.1 EC2 USER DATA SCRIPT (CLOUD-INIT AUTO-DETECT UNIVERSAL)

Masukkan skrip bash berikut ke dalam kolom "User data" saat meluncurkan instans EC2 baru. 
Skrip ini secara otomatis mengenali apakah instans adalah Amazon Linux 2 atau Amazon Linux 2023, 
lalu mengeksekusi instalasi wazuh-agent secara silent:

```bash
#!/bin/bash
set -e

# ==============================================================================
# AWS EC2 CLOUD-INIT USER DATA: WAZUH AGENT AUTO-DEPLOYMENT
# Mendukung: Amazon Linux 2 (YUM) & Amazon Linux 2023 (DNF)
# ==============================================================================

WAZUH_MANAGER_IP="172.1.10.50"          # GANTI DENGAN IP PRIVATE WAZUH MANAGER ANDA
WAZUH_GROUP_NAME="aws-ec2-production"   # GANTI DENGAN NAMA GROUP TUJUAN
AGENT_HOSTNAME=$(hostname -s)

# 1. Deteksi Sistem Operasi
if [ -f /etc/os-release ]; then
    . /etc/os-release
```text
OS_ID=$ID
OS_VER=$VERSION_ID
```

else
```text
echo "Gagal mendeteksi /etc/os-release"
```

    exit 1
fi

echo "Mendeteksi OS: $NAME (Versi: $VERSION_ID)"

# 2. Import GPG Key Resmi Wazuh
rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

# 3. Pasang Repository Wazuh
cat > /etc/yum.repos.d/wazuh.repo << 'EOF'
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

# 4. Instalasi Berdasarkan Package Manager
if [ "$OS_ID" = "amzn" ] && [ "$OS_VER" = "2023" ]; then
```bash
echo "Menginstal Wazuh Agent via DNF pada Amazon Linux 2023..."
dnf clean all
WAZUH_MANAGER="$WAZUH_MANAGER_IP" \
WAZUH_AGENT_GROUP="$WAZUH_GROUP_NAME" \
WAZUH_AGENT_NAME="$AGENT_HOSTNAME" \
dnf install -y wazuh-agent
```

else
```bash
echo "Menginstal Wazuh Agent via YUM pada Amazon Linux 2..."
yum clean all
WAZUH_MANAGER="$WAZUH_MANAGER_IP" \
WAZUH_AGENT_GROUP="$WAZUH_GROUP_NAME" \
WAZUH_AGENT_NAME="$AGENT_HOSTNAME" \
yum install -y wazuh-agent
```

fi

# 5. Batasi Penggunaan Resource (Cgroups)
systemctl set-property wazuh-agent MemoryMax=512M CPUQuota=30%

# 6. Aktifkan dan Jalankan Service
systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

echo "Instalasi Wazuh Agent selesai dengan status sukses."
```

### 7.2 AWS SYSTEMS MANAGER (SSM) RUN COMMAND (ZERO SSH DEPLOYMENT)

Jika Anda mengelola ratusan server EC2 tanpa membuka akses SSH, gunakan AWS SSM 
Run Command (`AWS-RunShellScript`):

1. Pastikan EC2 instans memiliki IAM Role dengan policy `AmazonSSMManagedInstanceCore`.
2. Buka AWS Console -> Systems Manager -> Run Command.
3. Pilih document: `AWS-RunShellScript`.
4. Masukkan perintah one-liner:
```bash
rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH && \
cat > /etc/yum.repos.d/wazuh.repo << 'EOF'
```

[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
```bash
WAZUH_MANAGER='172.1.10.50' WAZUH_AGENT_GROUP='production' yum install -y wazuh-agent && \
systemctl enable --now wazuh-agent
```

5. Pilih Target: Instance ID `i-xxxxxxx` (host `hrptrsapprd` dan `ip-172-1-12-178`).
6. Klik "Run". Status eksekusi akan terlapor "Success" dalam hitungan detik.

### 7.3 ANSIBLE PLAYBOOK DUAL-PLATFORM (AL2 & AL2023)

Jika Anda menggunakan Ansible Automation Controller:

```yaml
---
- name: Deploy Wazuh Agent pada Armada Amazon Linux EC2
```text
hosts: amazon_linux_servers
become: yes
vars:
  wazuh_manager_ip: "172.1.10.50"
  wazuh_agent_group: "production"
tasks:
```

    - name: Import GPG Key Wazuh
```text
ansible.builtin.rpm_key:
  key: https://packages.wazuh.com/key/GPG-KEY-WAZUH
  state: present
```

    - name: Pasang Repository Wazuh
```text
ansible.builtin.yum_repository:
  name: wazuh
  description: EL-$releasever - Wazuh
  baseurl: https://packages.wazuh.com/4.x/yum/
  gpgcheck: yes
  gpgkey: https://packages.wazuh.com/key/GPG-KEY-WAZUH
  enabled: yes
```

    - name: Instal Paket wazuh-agent
```text
ansible.builtin.package:
  name: wazuh-agent
  state: present
environment:
  WAZUH_MANAGER: "{{ wazuh_manager_ip }}"
  WAZUH_AGENT_GROUP: "{{ wazuh_agent_group }}"
  WAZUH_AGENT_NAME: "{{ inventory_hostname }}"
```

    - name: Terapkan Resource Limit Cgroups
```bash
ansible.builtin.command:
  cmd: systemctl set-property wazuh-agent MemoryMax=512M CPUQuota=30%
```

    - name: Start dan Enable Service wazuh-agent
```text
ansible.builtin.systemd:
  name: wazuh-agent
  enabled: yes
  state: started
  daemon_reload: yes
```

```

## 8. VERIFIKASI KONEKTIVITAS & STATUS DI SISI WAZUH MANAGER

Setelah instalasi pada server target (`hrptrsapprd` dan `ip-172-1-12-178`) selesai, 
lakukan verifikasi dari sisi server Wazuh Manager:

### 8.1 VERIFIKASI VIA COMMAND LINE (CLI WAZUH MANAGER)

Login via SSH ke server Wazuh Manager Anda:

1. Tampilkan daftar semua agent yang terdaftar dan statusnya:
```bash
sudo /var/ossec/bin/agent_control -l
```

   Contoh Output yang Diharapkan:
   Wazuh agent_control. List of available agents:
```text
ID: 000, Name: wazuh-manager (server), IP: 127.0.0.1, Active/Local
ID: 001, Name: hrptrsapprd, IP: any, Active
ID: 002, Name: ip-172-1-12-178, IP: any, Active
```

2. Cek rincian detail spesifik salah satu agent (misal ID 001):
```bash
sudo /var/ossec/bin/agent_control -i 001
```

   Output menampilkan:
   - Status: Active
   - Operating System: Amazon Linux 2
   - IP Address: IP private instans
   - Last Keep Alive: Baru saja (dalam hitungan detik)
   - Group: production, hr-payroll

3. Pengecekan via tool database pendaftaran:
```bash
sudo /var/ossec/bin/manage_agents -l
```

### 8.2 VERIFIKASI VIA WEB DASHBOARD WAZUH

1. Buka browser: `https://<IP_PUBLIC_ATAU_DNS_WAZUH_MANAGER>`
2. Login dengan akun admin.
3. Klik ikon menu kiri atas -> Pilih "Agents" -> "Summary".
4. Pada tab "Active Agents", pastikan nama `hrptrsapprd` dan `ip-172-1-12-178` tercantum 
   dengan indikator lingkaran hijau (Active).
5. Klik nama host untuk melihat dashboard telemetri:
   - Security Configuration Assessment (SCA Score)
   - Vulnerabilities (CVE detected pada software OS)
   - File Integrity Monitoring (Perubahan file terdeteksi)
   - MITRE ATT&CK Framework Mapping

## 9. TROUBLESHOOTING KOMPREHENSIF KASUS LAPANGAN (AL2 & AL2023)

KASUS 1: Error "Cannot find a valid baseurl for repo: wazuh" atau GPG Key Error
- Gejala: Gagal menjalankan `yum install` atau `dnf install` dengan pesan error repo.
- Analisis: Koneksi internet instans EC2 tidak dapat mencapai `packages.wazuh.com` 
  atau DNS resolver AWS gagal meresolusi domain eksternal.
- Solusi:
  1. Pastikan instans memiliki akses internet (via Internet Gateway jika di public subnet, 
     atau via NAT Gateway jika di private subnet).
  2. Uji resolusi domain:
```bash
curl -I https://packages.wazuh.com/key/GPG-KEY-WAZUH
```

  3. Bersihkan cache package manager:
     - Di AL2: `sudo yum clean all && sudo yum makecache`
     - Di AL2023: `sudo dnf clean all && sudo dnf makecache`

KASUS 2: Agent Berstatus "Never connected" atau "Disconnected"
- Gejala: Service `wazuh-agent` aktif (running), namun di Manager statusnya tetap "Never connected".
- Analisis: Trafik outbound ke port 1514 atau port 1515 terblokir oleh Security Group 
  atau Network ACL.
- Solusi:
  1. Periksa log error di agent:
```bash
sudo grep -iE "error|waiting for server|unable to connect" /var/ossec/logs/ossec.log
```

  2. Jika muncul log: `Waiting for server reply (authd) ... Connection timed out`:
     - Periksa Security Group Wazuh Manager: Pastikan Inbound Port 1515 dan Port 1514 
       mengizinkan subnet `172.1.0.0/16`.
     - Periksa Outbound Security Group EC2 Agent: Pastikan port 1514 dan 1515 diizinkan keluar.
  3. Periksa file `/var/ossec/etc/ossec.conf` di agent. Pastikan tag `<address>` berisi 
     IP private Wazuh Manager yang benar, bukan `0.0.0.0` atau placeholder.

KASUS 3: Key Registrasi Rusak atau Mismatch ("Invalid Key For Agent")
- Gejala: Log menampilkan pesan `Invalid key for agent 'hrptrsapprd'`.
- Solusi:
  1. Hentikan service agent di target:
```bash
sudo systemctl stop wazuh-agent
```

  2. Hapus key korup di target:
```bash
sudo rm -f /var/ossec/etc/client.keys
```

  3. Daftarkan ulang secara manual menggunakan command `agent-auth`:
```bash
sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_MANAGER> -A hrptrsapprd
# Atau jika menggunakan password:
sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_MANAGER> -P PasswordRahasiaWazuh123 -A hrptrsapprd
```

  4. Jalankan kembali service:
```bash
sudo systemctl start wazuh-agent
```

KASUS 4: Masalah Permission Denied Membaca `/var/log/audit/audit.log`
- Gejala: Log wazuh menampilkan `Could not open file '/var/log/audit/audit.log' due to [(13)-(Permission denied)]`.
- Analisis: File audit.log milik root dengan permission `0600` (`-rw-------`), 
  sedangkan service wazuh berjalan di bawah user `wazuh`.
- Solusi Resmi:
  Berikan akses read kepada grup wazuh menggunakan POSIX ACL:
```bash
sudo setfacl -m g:wazuh:r /var/log/audit/audit.log
sudo setfacl -d -m g:wazuh:r /var/log/audit/
```

KASUS 5: Peringatan SELinux pada AL2023
- Gejala: Muncul peringatan AVC denial pada `/var/log/audit/audit.log` terkait proses wazuh.
- Analisis: SELinux di AL2023 secara default berstatus `permissive` sehingga tidak memblokir 
  eksekusi. Namun jika sistem diubah ke mode `enforcing`, aturan SELinux diperlukan.
- Solusi:
  Pastikan mode SELinux tetap permissive untuk wazuh atau jalankan audit2allow:
```bash
sudo ausearch -c 'wazuh-agentd' --raw | audit2allow -M wazuh_agent_policy
sudo semodule -i wazuh_agent_policy.pp
```

## 10. QUICK COMMAND CHEAT SHEET KHUSUS AMAZON LINUX (AL2 & AL2023)

--- PERINTAH DI SISI AGENT AMAZON LINUX 2 (`hrptrsapprd`) ---
Status Service       : sudo systemctl status wazuh-agent
Restart Service      : sudo systemctl restart wazuh-agent
Pantau Log Realtime  : sudo tail -f /var/ossec/logs/ossec.log
Cek Key Registrasi   : sudo cat /var/ossec/etc/client.keys
Reinstall Paket      : sudo yum reinstall -y wazuh-agent

--- PERINTAH DI SISI AGENT AMAZON LINUX 2023 (`ip-172-1-12-178`) ---
Status Service       : sudo systemctl status wazuh-agent
Restart Service      : sudo systemctl restart wazuh-agent
Pantau Log Realtime  : sudo tail -f /var/ossec/logs/ossec.log
Cek Key Registrasi   : sudo cat /var/ossec/etc/client.keys
Reinstall Paket      : sudo dnf reinstall -y wazuh-agent
Cek Resource Cgroups : systemctl show wazuh-agent -p CPUQuota,MemoryMax

--- PERINTAH DI SISI WAZUH MANAGER ---
Lihat Semua Agent    : sudo /var/ossec/bin/agent_control -l
Cek Info Detail Agent: sudo /var/ossec/bin/agent_control -i <AGENT_ID>
Restart Agent Remote : sudo /var/ossec/bin/agent_control -R -u <AGENT_ID>
Trigger Scan FIM     : sudo /var/ossec/bin/agent_control -r -u <AGENT_ID>
Trigger Scan SCA     : sudo /var/ossec/bin/agent_control -s -u <AGENT_ID>
Hapus Agent          : sudo /var/ossec/bin/manage_agents -r <AGENT_ID>

## SELESAI & TERVERIFIKASI
