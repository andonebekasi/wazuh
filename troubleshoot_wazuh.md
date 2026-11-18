# PANDUAN TROUBLESHOOTING LENGKAP: WAZUH AGENT & WAZUH SERVER

## DAFTAR KASUS TROUBLESHOOTING:

1. Error: "Agent version must be lower or equal to manager version"
2. Cara Pengecekan Versi Wazuh Client dan Server via Linux CLI
3. Error: "Unable to add agent (from manager)" - Duplikasi Nama/IP
4. Menu "Cloud Security" Kosong ("No results") Setelah Install Agent
5. Port Matrix & AWS Security Group Wazuh Server
6. Cheat Sheet Perintah Diagnosa Penting
7. Error: "No such tag 'users' at module 'syscollector'" (Wazuh Agent Service Failed)
8. Cara Rename / Ganti Nama Wazuh Agent (manage_agents)
9. Error: "<Error><Code>AccessDenied</Code></Error>" Saat curl wazuh-install.sh

## 1. ERROR: "AGENT VERSION MUST BE LOWER OR EQUAL TO MANAGER VERSION"

#### A. Gejala & Log Error:

Saat menjalankan `sudo /var/ossec/bin/agent-auth -m 172.1.12.93` di client, muncul:
```text
agent-auth: INFO: Started (pid: 32348).
agent-auth: INFO: Requesting a key from server: 172.1.12.93
agent-auth: INFO: No authentication password provided
agent-auth: INFO: Using agent name as: hrptrsapprd
agent-auth: INFO: Waiting for server reply
agent-auth: ERROR: Agent version must be lower or equal to manager version (from manager)
agent-auth: ERROR: Unable to add agent (from manager)
```

#### B. Studi Kasus Nyata (Mismatch Versi):

- Pengecekan di Server (wazuh-tree-prod):
```bash
sudo /var/ossec/bin/wazuh-control info
```

  -> WAZUH_VERSION="v4.9.2"
  -> WAZUH_REVISION="40921"
  -> WAZUH_TYPE="server"

- Pengecekan di Client (hrptrsapprd):
```bash
sudo /var/ossec/bin/wazuh-agentd -V
```

  -> Wazuh v4.14.7 - Wazuh Inc.

Kesimpulan:
Versi Agent (v4.14.7) jauh lebih tinggi daripada Server (v4.9.2). Sesuai ATURAN EMAS WAZUH:
Versi Wazuh Agent TIDAK BOLEH LEBIH TINGGI daripada versi Wazuh Manager (Agent <= Manager).
Maka pendaftaran otomatis DITOLAK oleh Manager.

#### C. Langkah Perbaikan (Downgrade Versi Agent di Client ke 4.9.2):

Jalankan perintah berikut langsung di terminal client (hrptrsapprd):

1. Stop dan hapus paket wazuh-agent v4.14.7:
```bash
sudo systemctl stop wazuh-agent
sudo yum remove wazuh-agent -y
sudo rm -f /var/ossec/etc/client.keys
```

2. Install versi agent yang sama persis dengan server (v4.9.2-1):
```bash
sudo WAZUH_MANAGER='172.1.12.93' yum install -y wazuh-agent-4.9.2-1
```

   (Jika menggunakan Amazon Linux 2023 / DNF):
```bash
sudo WAZUH_MANAGER='172.1.12.93' dnf install -y wazuh-agent-4.9.2-1
```

3. Aktifkan dan jalankan service agent:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

4. Verifikasi versi agent setelah downgrade:
```bash
sudo /var/ossec/bin/wazuh-agentd -V
Output: Wazuh v4.9.2 - Wazuh Inc.
```

5. Verifikasi koneksi agent ke server:
```bash
sudo tail -n 25 /var/ossec/logs/ossec.log
```

   Output sukses:
```text
wazuh-agentd: INFO: Valid key received
wazuh-agentd: INFO: Connected to the server [172.1.12.93:1514]
wazuh-agentd: INFO: Server responded. Agent is now connected.
```

6. Verifikasi di sisi Wazuh Server (wazuh-tree-prod):
```bash
sudo /var/ossec/bin/agent_control -l
```

   Pastikan host `hrptrsapprd` berstatus Active.

## 2. CARA PENGECEKAN VERSI WAZUH CLIENT DAN SERVER VIA LINUX CLI

#### A. Pengecekan di Sisi WAZUH CLIENT (Agent):

Jalankan salah satu perintah berikut di terminal mesin client:

1. Menggunakan Binary Wazuh (Semua Distro Linux):
```text
/var/ossec/bin/wazuh-control info
```

   Contoh Output:
```text
WAZUH_VERSION="v4.9.0"
WAZUH_REVISION="40900"
WAZUH_TYPE="agent"
```

   Atau cek versi daemon agent:
```text
/var/ossec/bin/wazuh-agentd -V
```

   Contoh Output: Wazuh v4.9.0 - Wazuh Inc.

2. Menggunakan Package Manager OS:
   - Amazon Linux / RHEL / CentOS:
```bash
rpm -q wazuh-agent
```

     (Output contoh: wazuh-agent-4.9.0-1.x86_64)

   - Ubuntu / Debian:
     dpkg -l | grep wazuh-agent

---

B. Pengecekan di Sisi WAZUH SERVER (Manager: 172.1.12.93):
Login via SSH ke Wazuh Server, jalankan salah satu perintah berikut:

1. Menggunakan Binary Wazuh Manager:
```text
/var/ossec/bin/wazuh-control info
```

   Contoh Output:
```text
WAZUH_VERSION="v4.8.2"
WAZUH_REVISION="40802"
WAZUH_TYPE="server"
```

   Atau cek versi analysis daemon:
```text
/var/ossec/bin/wazuh-analysisd -V
```

2. Menggunakan Package Manager OS (Cek Manager, Indexer, Dashboard Sekaligus):
   - Amazon Linux / RHEL / CentOS:
```bash
rpm -qa | grep -E 'wazuh-manager|wazuh-indexer|wazuh-dashboard'
```

     Contoh Output:
```text
wazuh-manager-4.8.2-1.x86_64
wazuh-indexer-4.8.2-1.x86_64
wazuh-dashboard-4.8.2-1.x86_64
```

   - Ubuntu / Debian:
     dpkg -l | grep -E 'wazuh-manager|wazuh-indexer|wazuh-dashboard'

## 3. ERROR: "UNABLE TO ADD AGENT (FROM MANAGER)" - DUPLIKASI NAMA/IP

#### A. Gejala:

Log client menampilkan pesan penolakan `Unable to add agent (from manager)`, dan 
saat di-tes manual muncul pesan `Duplicate agent name` atau `Duplicate IP`.

#### B. Penyebab:

Nama hostname mesin client (misal: `hrptrsapprd`) atau IP-nya sudah pernah 
terdaftar di database Manager sebelumnya. Secara default Wazuh Manager menolak 
pendaftaran nama yang sama.

#### C. Solusi di Wazuh Server:

#### Opsi 1 (Hapus Agent Lama):

1. Cari ID agent lama:
```bash
sudo /var/ossec/bin/agent_control -l
```

2. Hapus agent lama:
```bash
sudo /var/ossec/bin/manage_agents -r <ID_AGENT>
```

#### Opsi 2 (Aktifkan force_insert - Rekomendasi Terbaik):

Edit `/var/ossec/etc/ossec.conf` di Wazuh Server, pastikan blok `<auth>` diset:
<auth>
  <disabled>no</disabled>
  <port>1515</port>
  <use_source_ip>no</use_source_ip>
  <force_insert>yes</force_insert>
  <force_time>0</force_time>
  <purge>yes</purge>
</auth>

Lalu restart server:
sudo systemctl restart wazuh-manager

## 4. MENU "CLOUD SECURITY" KOSONG ("NO RESULTS") SETELAH INSTALL AGENT

#### A. Penjelasan Konsep:

- Menu "Cloud security" (Amazon Web Services, Google Cloud, GitHub, dll.) pada 
  Wazuh Dashboard KHUSUS untuk integrasi API Cloud (Agentless).
- Modul ini membaca log audit AWS CloudTrail / S3 Bucket / GuardDuty dari API AWS.
- Agent Linux di client adalah "Endpoint Security", BUKAN "Cloud Security".
- Jadi jika hanya menginstal Agent di OS Linux tanpa konfigurasi AWS CloudTrail 
  ke S3 di Wazuh Server, menu "Cloud security" akan selalu KOSONG.

#### B. Lokasi Data Client Linux Sebenarnya:

1. Menu "Agents": Melihat daftar seluruh server client dan status "Active".
2. Menu "Endpoint security" -> "Threat Hunting": Melihat aktivitas event & log Linux.
3. Menu "Configuration Assessment" (SCA): Hasil audit keamanan CIS Benchmark.
4. Menu "File Integrity Monitoring" (FIM): Perubahan file sistem Linux.

## 5. PORT MATRIX & AWS SECURITY GROUP (EC2 WAZUH SERVER)

Pastikan Security Group pada instance EC2 Wazuh Server membuka port:
- 1515/TCP : Authd (Registrasi/Enrollment Agent baru)
- 1514/TCP : Remoted (Pengiriman log/event dari agent ke server)
- 443/TCP  : Akses Web Console Wazuh Dashboard

## 6. CHEAT SHEET PERINTAH DIAGNOSA PENTING

#### A. Di Sisi Client Linux (Agent):

1. Cek versi      : /var/ossec/bin/wazuh-control info (atau rpm -q wazuh-agent)
2. Status service : sudo systemctl status wazuh-agent
3. Baca log live  : sudo tail -f /var/ossec/logs/ossec.log
4. Test registrasi: sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_SERVER>
5. Cek key file   : sudo cat /var/ossec/etc/client.keys
6. Restart agent  : sudo systemctl restart wazuh-agent

#### B. Di Sisi Server (EC2 Wazuh Manager):

1. Cek versi      : /var/ossec/bin/wazuh-control info (atau rpm -qa | grep wazuh)
2. List agent     : sudo /var/ossec/bin/agent_control -l
3. Detail 1 agent : sudo /var/ossec/bin/agent_control -i <AGENT_ID>
4. Hapus agent    : sudo /var/ossec/bin/manage_agents -r <AGENT_ID>
5. Cek port listen: sudo ss -tulpn | grep -E '1514|1515'
6. Restart manager: sudo systemctl restart wazuh-manager
## 

7. ERROR: "NO SUCH TAG 'USERS' / 'SERVICES' / 'BROWSER_EXTENSIONS'"
## A. Gejala & Log Error: - Saat menjalankan `sudo systemctl restart wazuh-agent` atau `sudo /var/ossec/bin/wazuh-modulesd -t`, - muncul pesan error konfigurasi: - -------------------------------------------------------------------------------- - wazuh-modulesd: ERROR: No such tag 'users' at module 'syscollector'. - (atau 'groups', 'services', 'browser_extensions') - wazuh-modulesd: ERROR: (1202): Configuration error at 'etc/ossec.conf'. - wazuh-modulesd: Configuration error. Exiting - -------------------------------------------------------------------------------- - B. Penyebab: - - Terjadi setelah proses downgrade versi agent dari v4.14.x ke v4.9.2, di - mana konfigurasi lama `ossec.conf` masih digunakan atau di-restore. - - Di Wazuh Agent v4.9.2, modul `syscollector` BELUM MENDUKUNG 4 tag baru dari v4.14: - `<users>`, `<groups>`, `<services>`, dan `<browser_extensions>`. - - Tag yang didukung pada v4.9.2 hanyalah: - interval, scan_on_start, disabled, network, os, hardware, packages, ports, - processes, hotfixes, synchronization. - C. Solusi di Sisi Client: - 1. Hapus ke-4 tag yang tidak didukung dari ossec.conf: - sudo sed -i -E '/<(users|groups|services|browser_extensions)>.*<\/(users|groups|services|browser_extensions)>/d' /var/ossec/etc/ossec.conf - 2. Validasi konfigurasi: - sudo /var/ossec/bin/wazuh-modulesd -t - 3. Restart service agent: - sudo systemctl daemon-reload - sudo systemctl restart wazuh-agent - sudo systemctl status wazuh-agent

8. CARA RENAME / GANTI NAMA WAZUH AGENT (MANAGE_AGENTS)
## Kasus: - Agent terdaftar dengan nama hostname otomatis bawaan AWS EC2 (contoh: - `ip-172-1-12-178.ap-southeast-3.compute.internal`) dan ingin diubah menjadi - nama standar (contoh: `hrptrsappprd-new`). - Catatan: - Wazuh tidak memiliki perintah bawaan langsung untuk "rename" karena nama agent - terikat pada cryptographic auth key dan database. Dua cara penyelesaian: - --- METODE 1: RE-ENROLLMENT (SANGAT DIREKOMENDASIKAN & RESMI) --- - 1. Stop service agent di server client: - sudo systemctl stop wazuh-agent - 2. Hapus agent lama (ID 004) di Wazuh Manager: - sudo /var/ossec/bin/manage_agents -r 004 - (Ketik 'y' untuk konfirmasi) - 3. Daftarkan ulang dengan nama baru: - * Cara Cepat (dari Client via agent-auth): - sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_MANAGER> -A hrptrsappprd-new - sudo systemctl start wazuh-agent - * Cara Manual (dari Manager via manage_agents): - - Di Manager: `sudo /var/ossec/bin/manage_agents` -> pilih 'A' -> masukkan nama 'hrptrsappprd-new' & IP 'any' - - Di Manager: pilih 'E' -> salin (copy) key ID agent baru -> 'Q' - - Di Client: `sudo /var/ossec/bin/manage_agents -i <KEY>` -> 'y' -> 'Q' - - Di Client: `sudo systemctl start wazuh-agent` - 4. Verifikasi di Manager: - sudo /var/ossec/bin/manage_agents -l - --- METODE 2: WORKAROUND MANUAL DATABASE (MEMPERTAHANKAN ID LAMA) --- - (Gunakan hanya jika Anda wajib mempertahankan nomor ID agent lama) - 1. Stop service: - - Client:  sudo systemctl stop wazuh-agent - - Manager: sudo systemctl stop wazuh-manager - 2. Edit `/var/ossec/etc/client.keys` di Manager: - Ganti nama hostname lama pada baris ID 004 menjadi `hrptrsappprd-new`. - 3. Update database SQLite di Manager: - sudo sqlite3 /var/ossec/queue/db/global.db "UPDATE agent SET name='hrptrsappprd-new' WHERE id=4;" - 4. Edit `/var/ossec/etc/client.keys` di Client: - Ubah namanya agar identik dengan yang ada di Manager. - 5. Nyalakan service: - - Manager: sudo systemctl start wazuh-manager - - Client:  sudo systemctl start wazuh-agent

## 9. ERROR: "<Error><Code>AccessDenied</Code></Error>" SAAT CURL WAZUH-INSTALL.SH

#### A. Gejala & Log:

Saat mencoba mengunduh script installer Wazuh dengan perintah:
```bash
curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh
```

File `wazuh-install.sh` berukuran sangat kecil (~111 bytes) dan berisi XML:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>
```

Jika file tersebut dieksekusi (`bash ./wazuh-install.sh`), akan muncul syntax error:
  ./wazuh-install.sh: line 1: syntax error near unexpected token `newline'

#### B. Penyebab:

- Wazuh menyimpan paket dan script pada AWS S3 / CloudFront.
- Path generic '4.x' (`packages.wazuh.com/4.x/wazuh-install.sh`) TIDAK ADA / tidak disediakan.
- Karena direct listing S3 dinonaktifkan (public read list disabled), S3 mengembalikan 
  status 403 Forbidden ("AccessDenied") alih-alih 404 Not Found.

#### C. Solusi:

1. Hapus file installer rusak:
```text
rm -f wazuh-install.sh
```

2. Unduh menggunakan nomor versi minor spesifik yang valid (contoh: 4.14):
```bash
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh
```

   (Untuk file config.yml jika instalasi cluster/custom):
```bash
curl -sO https://packages.wazuh.com/4.14/config.yml
```

3. Verifikasi file berupa bash script:
```bash
head -n 5 wazuh-install.sh
# Pastikan baris pertama adalah: #!/bin/bash
```

4. Lanjutkan instalasi:
```bash
sudo bash ./wazuh-install.sh -a
```

================================================================================

