# PANDUAN LENGKAP: INSTALASI & KONFIGURASI WAZUH AGENT (MULTI-PLATFORM)

Dokumen ini adalah panduan teknis komprehensif untuk instalasi, pendaftaran 
(enrollment), konfigurasi modul keamanan, dan troubleshooting Wazuh Agent di 
berbagai sistem operasi (Ubuntu/Debian, RHEL/Amazon Linux, Windows Server, 
macOS, dan Docker Container).

## DAFTAR ISI

1. Pengenalan Wazuh Agent & Mekanisme Pendaftaran (Enrollment)
2. Prasyarat Jaringan, Firewall & Port Matrix Agent-to-Manager
3. Metode Pendaftaran (Enrollment): Otomatis, Password Authd & Manual CLI
4. Step-by-Step Instalasi Agent di Linux Ubuntu / Debian
5. Step-by-Step Instalasi Agent di Linux RHEL / AlmaLinux / Amazon Linux (AL2 & AL2023)
6. Step-by-Step Instalasi Agent di Microsoft Windows Server / Desktop
7. Step-by-Step Instalasi Agent di macOS (Intel & Apple Silicon M-Series)
8. Step-by-Step Instalasi Agent di Lingkungan Docker Host
9. Konfigurasi Modul Keamanan Inti Agent (`ossec.conf`):
   - 9.1 File Integrity Monitoring (FIM / syscheck) Real-time & Whodata
   - 9.2 Pengumpulan Log Sistem & Aplikasi (Syslog, Nginx, Apache, MySQL)
   - 9.3 Pengumpulan Windows Event Channel (Security, System, Sysmon)
   - 9.4 Policy Monitoring & Security Configuration Assessment (SCA)
   - 9.5 Active Response (Auto-Block Penyerang via Firewall)
10. Manajemen Sentralisasi Konfigurasi via Agent Groups (`agent.conf`)
11. Verifikasi Status, Monitoring Konektivitas & Health Check
12. Troubleshooting Masalah Koneksi Agent & Kasus Lapangan
13. Cheat Sheet Perintah Penting & Lokasi File Kunci

## 1. PENGENALAN WAZUH AGENT & MEKANISME PENDAFTARAN (ENROLLMENT)

Wazuh Agent adalah service ringan multi-platform yang dipasang pada endpoint/server. 
Agent bertugas membaca event sistem lokal, memonitor integritas file, mengecek 
kerentanan software, dan mengirimkannya secara aman ke Wazuh Manager.

Siklus Hidup Pendaftaran (Agent Enrollment Flow):
1. Registrasi (Enrollment):
   Agent menghubungi endpoint Authd pada Wazuh Manager (Port 1515 TCP).
   Manager memvalidasi request, memberikan ID unik (misal: `001`), dan 
   menghasilkan cryptographic key 128-bit yang disimpan di `/var/ossec/etc/client.keys`.
2. Komunikasi Event & Log:
   Setelah terdaftar, agent beralih berkomunikasi secara terenkripsi dua arah 
   dengan Wazuh Manager melalui Port 1514 TCP.
3. Sinkronisasi Aturan:
   Agent mengunduh konfigurasi grup (`agent.conf`) dan database baseline keamanan 
   dari Manager secara otomatis.

## 2. PRASYARAT JARINGAN, FIREWALL & PORT MATRIX AGENT-TO-MANAGER

Sebelum menginstal agent, pastikan port jaringan dari server Agent ke arah 
Wazuh Manager (Inbound di sisi Manager, Outbound di sisi Agent) telah dibuka:

| PORT / PROTOKOL | ARAH TRAFIK | FUNGSI |
| :--- | :--- | :--- |
| TCP 1514 | Agent -> Manager | Pengiriman event log, alerts, dan heartbeat |
| TCP 1515 | Agent -> Manager | Pendaftaran awal agent (authd registration service) |

Uji Konektivitas Sebelum Instalasi (dari sisi server Agent):
```text
# Tes port pendaftaran (1515)
nc -zvw3 <IP_ATAU_DOMAIN_WAZUH_MANAGER> 1515
# Tes port komunikasi log (1514)
nc -zvw3 <IP_ATAU_DOMAIN_WAZUH_MANAGER> 1514
```

Jika output menampilkan "Connection to ... port ... [tcp/*] succeeded!", 
berarti koneksi jaringan siap.

## 3. METODE PENDAFTARAN (ENROLLMENT): OTOMATIS, PASSWORD AUTHD & MANUAL CLI

Terdapat 3 metode utama untuk mendaftarkan agent ke Wazuh Manager:

--- METODE A: AUTO-ENROLLMENT DENGAN ENVIRONMENT VARIABLES (PALING POPULER) ---
Menginjeksi parameter konfigurasi saat instalasi paket (deb/rpm/msi).
Parameter utama:
- `WAZUH_MANAGER`: IP Private / Elastic IP / Domain FQDN dari Wazuh Manager.
- `WAZUH_AGENT_GROUP`: Menempatkan agent langsung ke grup tertentu (default: `default`).
- `WAZUH_AGENT_NAME`: Menentukan hostname spesifik agent (default: hostname OS).
- `WAZUH_REGISTRATION_SERVER`: IP server registrasi (biasanya sama dengan `WAZUH_MANAGER`).

--- METODE B: PENDAFTARAN MENGGUNAKAN REGISTRATION PASSWORD (SECURE AUTHD) ---
Untuk mencegah sembarang server mendaftar ke Manager Anda di lingkungan cloud publik:
1. Di sisi Wazuh Manager, buat password registrasi:
```bash
echo "PasswordRahasiaAgent123" | sudo tee /var/ossec/etc/authd.pass
sudo chmod 640 /var/ossec/etc/authd.pass
sudo chown root:wazuh /var/ossec/etc/authd.pass
sudo systemctl restart wazuh-manager
```

2. Di sisi Agent, tambahkan variabel saat instalasi:
```text
WAZUH_REGISTRATION_PASSWORD='PasswordRahasiaAgent123'
```

--- METODE C: PENDAFTARAN MANUAL MENGGUNAKAN CLI (OFFLINE / AIR-GAPPED) ---
Gunakan jika port 1515 tidak boleh dibuka sama sekali:
1. Di sisi Wazuh Manager, tambahkan agent secara manual:
```bash
sudo /var/ossec/bin/manage_agents
```

   - Ketik 'A' (Add an agent).
   - Masukkan nama agent (misal: `db-server-01`).
   - Masukkan IP agent (atau ketik `any` jika IP dinamis).
   - Ketik 'E' (Extract key for an agent) -> Masukkan ID agent -> Salin string key yang muncul.
2. Di sisi server Agent:
```bash
sudo /var/ossec/bin/manage_agents
```

   - Ketik 'I' (Import key from the server).
   - Tempelkan (paste) string key dari Manager -> Tekan Enter -> Ketik 'y'.
   - Restart agent: `sudo systemctl restart wazuh-agent`.

## 4. STEP-BY-STEP INSTALASI AGENT DI LINUX UBUNTU / DEBIAN

Kompatibel dengan: Ubuntu 20.04 LTS, Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Debian 11/12.

#### Langkah 1: Import GPG Key Resmi Wazuh

```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
sudo chmod 644 /usr/share/keyrings/wazuh.gpg
```

#### Langkah 2: Tambahkan Repository Resmi Wazuh

```bash
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt-get update
```

#### Langkah 3: Instal Wazuh Agent dengan Konfigurasi Manager

Ganti `<IP_WAZUH_MANAGER>` dengan IP Private atau Elastic IP Wazuh Anda:
```bash
sudo WAZUH_MANAGER='<IP_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='default' \
     WAZUH_AGENT_NAME='web-ubuntu-prod-01' \
```

       apt-get install -y wazuh-agent

#### Langkah 4: Jalankan dan Aktifkan Service Systemd

```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

#### Langkah 5: Verifikasi Status Service & Koneksi

```bash
sudo systemctl status wazuh-agent
# Pantau log komunikasi handshake
sudo tail -f /var/ossec/logs/ossec.log | grep -E "Connected to the server|Valid key received"
```

## 5. STEP-BY-STEP INSTALASI AGENT DI LINUX RHEL / ALMALINUX / AMAZON LINUX (AL2 & AL2023)

Kompatibel dengan: RHEL 8/9, CentOS 7/8, Rocky Linux 8/9, AlmaLinux 8/9, Amazon Linux 2, Amazon Linux 2023.
(Catatan: Untuk panduan produksi mendalam khusus AWS EC2 Amazon Linux 2 & 2023, 
lihat file terpisah: wazuh_agent_amazon_linux_install_guide.txt)

#### Langkah 1: Import GPG Key Resmi Wazuh

```bash
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
```

#### Langkah 2: Tambahkan Repository Resmi Wazuh YUM/DNF

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

#### Langkah 3: Instalasi Paket Agent Berdasarkan Distribusi OS:

```bash
--- PILIHAN A: UNTUK AMAZON LINUX 2 (AL2 - Host seperti 'hrptrsapprd') ---
sudo WAZUH_MANAGER='<IP_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='production,hr-payroll' \
     WAZUH_AGENT_NAME='hrptrsapprd' \
     yum install -y wazuh-agent

--- PILIHAN B: UNTUK AMAZON LINUX 2023 (AL2023 - Host seperti 'ip-172-1-12-178') ---
sudo WAZUH_MANAGER='<IP_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='production,backend' \
     WAZUH_AGENT_NAME='ip-172-1-12-178' \
     dnf install -y wazuh-agent

--- PILIHAN C: UNTUK RHEL 8/9 / ROCKY / ALMALINUX ---
sudo WAZUH_MANAGER='<IP_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='default' \
     WAZUH_AGENT_NAME='db-rhel-prod-01' \
     yum install -y wazuh-agent
```

#### Langkah 4: Konfigurasi Firewall Lokal (Jika Menggunakan Firewalld)

Jika server lokal memiliki firewall aktif, pastikan port outbound diizinkan:
```bash
sudo firewall-cmd --state
# Jika active, pastikan outbound port 1514 dan 1515 ke arah Manager tidak diblokir.
```

#### Langkah 5: Jalankan dan Aktifkan Service Systemd

```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
sudo systemctl status wazuh-agent
```

#### Langkah 6: Verifikasi Pendaftaran & Handshake Log

```bash
sudo cat /var/ossec/etc/client.keys
sudo tail -f /var/ossec/logs/ossec.log | grep -E "Connected to the server|Valid key received"
```

## 6. STEP-BY-STEP INSTALASI AGENT DI MICROSOFT WINDOWS SERVER / DESKTOP

Kompatibel dengan: Windows Server 2016, 2019, 2022, Windows 10, Windows 11.

--- CARA 1: INSTALASI OTOMATIS VIA POWERSHELL (CLI - SANGAT DIREKOMENDASIKAN) ---
1. Buka PowerShell sebagai Administrator ("Run as Administrator").
2. Jalankan perintah unduh dan instalasi silent berikut:

   $WazuhManager = "<IP_WAZUH_MANAGER>"
   $AgentName    = "win-server-prod-01"
   $InstallerUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.0-1.msi"
   $Destination  = "$env:TEMP\wazuh-agent.msi"

```text
# Unduh paket installer
```

   [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
   Invoke-WebRequest -Uri $InstallerUrl -OutFile $Destination

```text
# Eksekusi instalasi silent dengan parameter registrasi
$Arguments = "/i `"$Destination`" /qn WAZUH_MANAGER=`"$WazuhManager`" WAZUH_REGISTRATION_SERVER=`"$WazuhManager`" WAZUH_AGENT_NAME=`"$AgentName`""
```

   Start-Process msiexec.exe -ArgumentList $Arguments -Wait

```text
# Menjalankan service Windows
```

   Start-Service -Name "WazuhSvc"
   Set-Service -Name "WazuhSvc" -StartupType Automatic

3. Cek status service di PowerShell:
   Get-Service -Name "WazuhSvc"
```text
# Lihat log agent
```

   Get-Content -Path "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 30

--- CARA 2: INSTALASI VIA GRAPHICAL USER INTERFACE (GUI) ---
1. Unduh installer `.msi` dari situs resmi Wazuh di browser Windows.
2. Klik ganda file `.msi` dan ikuti wizard instalasi hingga selesai (lokasi: `C:\Program Files (x86)\ossec-agent\`).
3. Jalankan aplikasi "Wazuh Agent Manager" (`win32ui.exe`) sebagai Administrator.
4. Masukkan parameter:
   - Manager IP: `<IP_WAZUH_MANAGER>`
   - Registration Key / Authentication Server: `<IP_WAZUH_MANAGER>`
5. Klik menu "Manage" -> "Restart".
6. Status bar di bagian bawah jendela akan menampilkan "Connected".

## 7. STEP-BY-STEP INSTALASI AGENT DI MACOS (INTEL & APPLE SILICON M-SERIES)

Kompatibel dengan: macOS 11 (Big Sur), macOS 12 (Monterey), macOS 13 (Ventura), macOS 14 (Sonoma).

#### Langkah 1: Unduh Paket Installer PKG

```bash
curl -so /tmp/wazuh-agent.pkg https://packages.wazuh.com/4.x/macos/wazuh-agent-4.9.0-1.intel64.pkg
# Untuk Apple Silicon (M1/M2/M3), gunakan paket arm64 jika tersedia atau jalankan via Rosetta.
```

#### Langkah 2: Konfigurasikan File Environment Sebelum Install

```text
echo "WAZUH_MANAGER='<IP_WAZUH_MANAGER>'" > /tmp/wazuh_envs
echo "WAZUH_AGENT_GROUP='default'" >> /tmp/wazuh_envs
```

#### Langkah 3: Instal Paket

```bash
sudo installer -pkg /tmp/wazuh-agent.pkg -target /
```

#### Langkah 4: Jalankan Service via Launchctl

```bash
sudo /Library/Ossec/bin/wazuh-control start
# Cek status
sudo /Library/Ossec/bin/wazuh-control status
```

## 8. STEP-BY-STEP INSTALASI AGENT DI LINGKUNGAN DOCKER HOST

Untuk memonitor host Docker dan seluruh container yang berjalan di dalamnya:

#### Langkah 1: Instal Wazuh Agent pada Docker Host (Gunakan Bab 4 atau 5).

#### Langkah 2: Tambahkan User `wazuh` ke dalam Grup `docker`

Hal ini memberikan izin kepada Wazuh Agent untuk membaca Docker Socket API:
```bash
sudo usermod -aG docker wazuh
```

#### Langkah 3: Aktifkan Modul Docker Listener di `/var/ossec/etc/ossec.conf`:

Buka file konfigurasi agent:
```bash
sudo nano /var/ossec/etc/ossec.conf
```

Tambahkan blok berikut di dalam `<ossec_config>`:
  <wodle name="docker-listener">
    <disabled>no</disabled>
  </wodle>

#### Langkah 4: Restart Agent:

```bash
sudo systemctl restart wazuh-agent
```

Kini Wazuh akan mendeteksi event container (start, stop, pause, kill, image pull).

## 9. KONFIGURASI MODUL KEAMANAN INTI AGENT (`OSSEC.CONF`)

File konfigurasi utama di sisi agent terletak di:
- Linux: `/var/ossec/etc/ossec.conf`
- Windows: `C:\Program Files (x86)\ossec-agent\ossec.conf`

Berikut modul-modul penting yang wajib dikonfigurasi untuk standar keamanan produksi:

### 9.1 FILE INTEGRITY MONITORING (FIM / SYSCHECK) REAL-TIME & WHODATA

FIM mendeteksi pembuatan, modifikasi, atau penghapusan file sensitif secara instan.

Konfigurasi Linux (`/var/ossec/etc/ossec.conf`):
  <syscheck>
    <disabled>no</disabled>
    <frequency>43200</frequency> <!-- Scan rutin setiap 12 jam -->
    <scan_on_start>yes</scan_on_start>

    <!-- Monitor direktori sistem penting secara real-time -->
    <directories check_all="yes" realtime="yes">/etc,/usr/bin,/usr/sbin</directories>
    <directories check_all="yes" realtime="yes">/root/.ssh,/home/*/.ssh</directories>
    
    <!-- Monitor folder kode web aplikasi dengan fitur Whodata (Auditd Who Modified) -->
    <directories check_all="yes" whodata="yes">/var/www/html</directories>

    <!-- Pengecualian (Ignore) file yang sering berubah otomatis -->
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
    <ignore>/etc/adjtime</ignore>
  </syscheck>

### 9.2 PENGUMPULAN LOG SISTEM & APLIKASI (LOCALFILE)

Kirim log aplikasi lokal ke Wazuh Manager untuk dianalisis:

  <!-- Log Autentikasi Linux (SSH Login, Sudo Abuse) -->
```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/auth.log</location> <!-- /var/log/secure untuk RHEL -->
</localfile>
```

  <!-- Log Web Server Nginx (Access & Error) -->
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

  <!-- Log Database MySQL / MariaDB -->
```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/mysql/error.log</location>
</localfile>
```

### 9.3 PENGUMPULAN WINDOWS EVENT CHANNEL (KHUSUS WINDOWS)

Pada Windows, gunakan `eventchannel` untuk menyadap event modern Windows & Sysmon:

```xml
<localfile>
  <log_format>eventchannel</log_format>
  <location>Security</location>
</localfile>
<localfile>
  <log_format>eventchannel</log_format>
  <location>System</location>
</localfile>
<!-- Menyadap Sysmon jika terpasang -->
<localfile>
  <log_format>eventchannel</log_format>
  <location>Microsoft-Windows-Sysmon/Operational</location>
</localfile>
```

### 9.4 SECURITY CONFIGURATION ASSESSMENT (SCA)

SCA mengevaluasi kepatuhan konfigurasi OS terhadap standar CIS Benchmark:
  <sca>
    <enabled>yes</enabled>
    <scan_on_start>yes</scan_on_start>
    <interval>12h</interval>
    <skip_nfs>yes</skip_nfs>
  </sca>

### 9.5 ACTIVE RESPONSE (AUTO-BLOCK PENYERANG VIA FIREWALL)

Aktifkan kemampuan agent untuk mengeksekusi script otomatis (misal: blokir IP 
SSH brute force selama 10 menit via firewall-cmd / iptables):
  <active-response>
    <disabled>no</disabled>
    <ca_store>/var/ossec/etc/wpk_root.pem</ca_store>
  </active-response>

## 10. MANAJEMEN SENTRALISASI KONFIGURASI VIA AGENT GROUPS (`AGENT.CONF`)

Jika Anda memiliki puluhan atau ratusan server, mengedit `ossec.conf` satu per satu 
di setiap agent sangat tidak efisien. Gunakan fitur Agent Groups!

Langkah-langkah:
1. Buat grup baru di Wazuh Manager via CLI:
```bash
sudo /var/ossec/bin/agent_groups -a -g "web-servers"
sudo /var/ossec/bin/agent_groups -a -g "db-servers"
```

2. Masukkan agent ke dalam grup:
```bash
sudo /var/ossec/bin/agent_groups -p -i 001 -g "web-servers"
```

3. Buat file konfigurasi terpusat di Manager:
   Edit file `/var/ossec/etc/shared/web-servers/agent.conf`:
   
   <agent_config>
     <!-- Seluruh server di grup web-servers otomatis memonitor path ini -->
     <syscheck>
       <directories check_all="yes" realtime="yes">/var/www/html</directories>
     </syscheck>
```xml
  <localfile>
    <log_format>apache</log_format>
    <location>/var/log/nginx/access.log</location>
  </localfile>
</agent_config>
```

4. Restart agent dari jarak jauh via Manager:
```bash
sudo /var/ossec/bin/agent_control -R -g "web-servers"
```

   Agent akan mengunduh konfigurasi baru secara otomatis tanpa perlu Anda SSH ke server!

## 11. VERIFIKASI STATUS, MONITORING KONEKTIVITAS & HEALTH CHECK

#### A. PENGECEKAN DARI SISI WAZUH MANAGER:

1. Menampilkan seluruh agent terdaftar:
```bash
sudo /var/ossec/bin/agent_control -l
```

   
   Contoh Output:
   Wazuh agent_control. List of available agents:
```text
ID: 000, Name: wazuh-manager (server), IP: 127.0.0.1, Active/Local
ID: 001, Name: web-ubuntu-prod-01, IP: any, Active
ID: 002, Name: db-rhel-prod-01, IP: any, Active
ID: 003, Name: win-server-prod-01, IP: any, Active
```

2. Melihat detail informasi sistem 1 agent:
```bash
sudo /var/ossec/bin/agent_control -i 001
```

#### B. PENGECEKAN DARI SISI WAZUH DASHBOARD (WEB UI):

1. Masuk ke Wazuh Dashboard: `https://<IP_WAZUH_DASHBOARD>`
2. Klik menu navigasi kiri -> "Endpoints Summary".
3. Pastikan kolom "Status" berwarna hijau ("Active").
4. Klik nama agent untuk melihat inventaris software, open ports, status FIM, dan CVE vulnerability.

## 12. TROUBLESHOOTING MASALAH KONEKSI AGENT & KASUS LAPANGAN

KASUS 1: Agent Status "Never Connected" atau "Disconnected"
- Penyebab: 
  * Port 1514/1515 terhalang Security Group AWS atau firewall lokal (UFW / iptables).
  * Konfigurasi IP Manager salah di dalam file `ossec.conf`.
- Prosedur Solusi:
  1. Periksa log di server agent:
```bash
sudo tail -n 50 /var/ossec/logs/ossec.log
```

  2. Jika muncul error: `Unable to connect to any server`:
     Uji port dari agent: `nc -zvw3 <IP_MANAGER> 1514`
  3. Buka `/var/ossec/etc/ossec.conf`, pastikan tag `<address>` berisi IP yang valid:
```text
<server>
  <address>10.0.1.50</address> <!-- IP Private Manager jika 1 VPC -->
  <port>1514</port>
  <protocol>tcp</protocol>
</server>
```

  4. Restart agent: `sudo systemctl restart wazuh-agent`.

KASUS 2: Error "Invalid Key For Agent" atau "Key Mismatch"
- Penyebab: Agent didaftarkan ulang tetapi masih menyimpan key lama di `client.keys`.
- Solusi:
  1. Hentikan service agent:
```bash
sudo systemctl stop wazuh-agent
```

  2. Hapus file key lokal:
```bash
sudo rm -f /var/ossec/etc/client.keys
```

  3. Daftarkan ulang menggunakan utilitas `agent-auth`:
```bash
sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_MANAGER> -A <NAMA_AGENT>
```

  4. Jalankan kembali service:
```bash
sudo systemctl start wazuh-agent
```

KASUS 3: High CPU Usage pada Wazuh Agent di Linux
- Penyebab: Modul FIM (syscheck) memonitor folder yang berisi jutaan file dinamis 
  (contoh: `/var/log`, `/tmp`, `node_modules`, `cache`).
- Solusi:
  1. Tambahkan tag `<ignore>` di konfigurasi `<syscheck>`:
     <ignore type="sregex">^/var/www/.*/node_modules</ignore>
     <ignore type="sregex">^/var/www/.*/storage/framework/cache</ignore>
  2. Atur batas pembacaan IO (`max_eps`):
     <max_eps>100</max_eps>

## 13. CHEAT SHEET PERINTAH PENTING & LOKASI FILE KUNCI

--- PERINTAH KONTROL SERVICE AGENT (LINUX) ---
Status Service    : sudo systemctl status wazuh-agent
Start Service     : sudo systemctl start wazuh-agent
Stop Service      : sudo systemctl stop wazuh-agent
Restart Service   : sudo systemctl restart wazuh-agent
Pantau Log Realtime: sudo tail -f /var/ossec/logs/ossec.log

--- PERINTAH KONTROL SERVICE AGENT (WINDOWS POWERSHELL) ---
Status Service    : Get-Service -Name "WazuhSvc"
Start Service     : Start-Service -Name "WazuhSvc"
Restart Service   : Restart-Service -Name "WazuhSvc"
Pantau Log Realtime: Get-Content -Path "C:\Program Files (x86)\ossec-agent\ossec.log" -Wait -Tail 20

--- PERINTAH MANAJEMEN DI SISI WAZUH MANAGER ---
Daftar seluruh agent           : sudo /var/ossec/bin/agent_control -l
Restart agent jarak jauh        : sudo /var/ossec/bin/agent_control -R -u <AGENT_ID>
Eksekusi scan FIM langsung      : sudo /var/ossec/bin/agent_control -r -u <AGENT_ID>
Eksekusi scan SCA langsung      : sudo /var/ossec/bin/agent_control -s -u <AGENT_ID>
Hapus agent dari database       : sudo /var/ossec/bin/manage_agents -r <AGENT_ID>

--- LOKASI FILE PENTING (LINUX) ---
Konfigurasi Utama Agent         : /var/ossec/etc/ossec.conf
Kredensial & Enkripsi Key       : /var/ossec/etc/client.keys
Log Aktivitas & Error           : /var/ossec/logs/ossec.log
Konfigurasi Sentral dari Server : /var/ossec/etc/shared/agent.conf

--- LOKASI FILE PENTING (WINDOWS) ---
Folder Instalasi                : C:\Program Files (x86)\ossec-agent\
Konfigurasi Utama Agent         : C:\Program Files (x86)\ossec-agent\ossec.conf
Log Aktivitas & Error           : C:\Program Files (x86)\ossec-agent\ossec.log
GUI Agent Manager               : C:\Program Files (x86)\ossec-agent\win32ui.exe

## AKHIR DARI PANDUAN
