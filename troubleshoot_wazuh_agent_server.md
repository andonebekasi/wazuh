# PANDUAN LENGKAP TROUBLESHOOTING: WAZUH AGENT & SERVER (LINUX STANDALONE) - Monitoring Endpoint Linux Tanpa Kebutuhan AWS CloudTrail & S3 Bucket

## DAFTAR ISI:

1. Penjelasan Mengapa Menu "Cloud Security" Tetap Kosong / "No results"
2. Tempat Yang Benar Melihat Data Client Linux di Wazuh Dashboard
3. Prasyarat Jaringan & Port AWS Security Group (EC2 Wazuh Server)
4. Diagnosa & Troubleshooting di Sisi Client (Wazuh Agent)
5. Diagnosa & Troubleshooting di Sisi Server (EC2 Wazuh Manager)
6. Alur Pendaftaran (Enrollment) Ulang Agent Secara Manual
7. Ringkasan Error Umum & Solusi Cepat (Cheat Sheet)

## 1. PENJELASAN MENGAPA MENU "CLOUD SECURITY" KOSONG / "NO RESULTS"

Kasus: Anda sudah menginstal Wazuh Agent di client Linux, tetapi menu 
"Cloud security" (Amazon Web Services / Google Cloud / dll.) tetap "No results".

Penjelasan:
- Menu "Cloud security" di Wazuh KHUSUS diperuntukkan bagi integrasi API Cloud 
  (Agentless), seperti membaca log audit AWS CloudTrail, AWS GuardDuty, atau 
  VPC Flow Logs dari AWS S3 Bucket.
- Wazuh Agent yang dipasang langsung di OS Linux (misal: Ubuntu, Debian, RHEL, 
  Amazon Linux) bertindak sebagai "Endpoint Security", BUKAN "Cloud Security".
- Oleh karena itu, jika Anda hanya menginstal Agent di mesin Linux tanpa setup 
  CloudTrail/S3 di Wazuh Server, menu "Cloud security" akan SELALU KOSONG, 
  dan hal ini sepenuhnya NORMAL.

## 2. TEMPAT YANG BENAR MELIHAT DATA CLIENT LINUX DI WAZUH DASHBOARD

Data, status, dan log aktivitas dari client Linux Anda akan muncul di menu:

1. Menu "Agents" (Navigasi Kiri Atas -> Agents):
   - Menampilkan daftar semua server client yang terdaftar.
   - Pastikan status client Anda bertuliskan "Active" (lingkaran hijau).
   - Klik nama client untuk melihat rincian hardware, OS, IP, RAM, dan proses.

2. Menu "Endpoint security" -> "Threat Hunting":
   - Menampilkan rekaman event keamanan, log autentikasi (SSH login sukses/gagal), 
     eksekusi perintah sudo, dan anomali sistem dari client Linux.

3. Menu "Configuration Assessment" (SCA):
   - Menampilkan skor kepatuhan audit keamanan sistem operasi (CIS Benchmark).

4. Menu "File Integrity Monitoring" (FIM):
   - Menampilkan rekaman modifikasi, pembuatan, atau penghapusan file sistem 
     penting di Linux client.

5. Menu "Vulnerability Detection":
   - Menampilkan daftar CVE / kelemahan keamanan pada paket aplikasi yang terinstal 
     di client Linux.

## 3. PRASYARAT JARINGAN & PORT AWS SECURITY GROUP (EC2 WAZUH SERVER)

Karena Wazuh Server berjalan di AWS EC2, koneksi dari Agent ke Server HANYA 
bisa terhubung jika Security Group EC2 mengizinkan port berikut:

| PORT / PROTOKOL | SUMBER (SOURCE) | FUNGSI |
| :--- | :--- | :--- |
| 1514 / TCP | IP Client Linux (atau Any) | Komunikasi event/log dari Agent ke Server |
| 1515 / TCP | IP Client Linux (atau Any) | Registrasi / Enrollment Agent baru |
| 443  / TCP | IP Admin / Browser Anda | Akses Web Wazuh Dashboard |

Catatan Penentuan Alamat IP Server:
- Jika Client Linux berada di dalam AWS VPC yang sama:
  Gunakan PRIVATE IP dari EC2 Wazuh Server.
- Jika Client Linux berada di luar AWS (on-premise / laptop / cloud lain):
  Gunakan PUBLIC IP / ELASTIC IP dari EC2 Wazuh Server, dan pastikan Port 1514 
  serta 1515 di Security Group EC2 terbuka ke IP Publik client tersebut.

## 4. DIAGNOSA & TROUBLESHOOTING DI SISI CLIENT (WAZUH AGENT)

1. Cek Status Service Agent:
```bash
sudo systemctl status wazuh-agent
```

   Jika mati atau gagal start:
```bash
sudo systemctl restart wazuh-agent
```

2. Periksa File Konfigurasi Agent (`/var/ossec/etc/ossec.conf`):
   Pastikan alamat IP Wazuh Server sudah sesuai:
```bash
sudo nano /var/ossec/etc/ossec.conf
```

   Cari blok:
```text
<client>
  <server>
    <address>IP_EC2_WAZUH_SERVER</address>
    <port>1514</port>
    <protocol>tcp</protocol>
  </server>
</client>
```

3. Cek Log Koneksi Real-time:
```bash
sudo tail -n 50 /var/ossec/logs/ossec.log
```

   - INDIKASI SUKSES:
```text
wazuh-agentd: INFO: Connected to the server [IP_EC2_WAZUH_SERVER:1514]
wazuh-agentd: INFO: Server responded. Agent is now connected.
```

   - INDIKASI GAGAL:
     * "Connection refused" / "Unable to connect to ...:1514"
       -> Port 1514 belum dibuka di Security Group AWS EC2, atau IP server salah.
     * "Waiting for server reply"
       -> Paket diblokir oleh firewall AWS atau ISP.
     * "Invalid key" / "Agent key not found"
       -> Agent belum terdaftar di Manager atau file client.keys kosong.

## 5. DIAGNOSA & TROUBLESHOOTING DI SISI SERVER (EC2 WAZUH MANAGER)

1. Pastikan Service Wazuh Manager Berjalan Normal:
```bash
sudo systemctl status wazuh-manager
```

2. Pastikan Port 1514 dan 1515 Sedang Mendengarkan (Listening):
```bash
sudo ss -tulpn | grep -E '1514|1515'
```

   Hasil yang diharapkan:
   tcp  LISTEN  0  511  0.0.0.0:1514  ...
   tcp  LISTEN  0  511  0.0.0.0:1515  ...

3. Cek Daftar Agent yang Terdaftar di Manager:
```bash
sudo /var/ossec/bin/agent_control -l
```

   Status agent:
   - Active       : Agent terhubung dan sedang mengirim log.
   - Disconnected : Agent pernah terdaftar namun saat ini kehilangan koneksi.
   - Never connected : Agent terdaftar tetapi belum pernah sukses kontak via port 1514.

4. Cek Informasi Detail Satu Agent:
```bash
sudo /var/ossec/bin/agent_control -i <AGENT_ID>
```

   Contoh:
```bash
sudo /var/ossec/bin/agent_control -i 001
```

5. Pantau Log Aktivitas Server:
```bash
sudo tail -f /var/ossec/logs/ossec.log | grep -E 'auth|remoted'
```

## 6. ALUR PENDAFTARAN (ENROLLMENT) ULANG AGENT SECARA MANUAL

Jika agent client belum terdaftar atau kunci enkripsi corrupt, jalankan pendaftaran 
ulang langsung dari terminal Client Linux:

#### Langkah 1: Daftarkan Agent ke Server via CLI

sudo /var/ossec/bin/agent-auth -m <IP_EC2_WAZUH_SERVER> -p 1515

Jika sukses, output akan memunculkan pesan:
"Valid key received"

#### Langkah 2: Restart Service Agent di Client

sudo systemctl restart wazuh-agent

#### Langkah 3: Verifikasi File Kunci

Pastikan file `/var/ossec/etc/client.keys` tidak kosong:
sudo cat /var/ossec/etc/client.keys
(Akan terlihat 1 baris berisi ID, Nama Host, IP, dan Token Rahasia).

## 7. RINGKASAN ERROR UMUM & SOLUSI CEPAT (CHEAT SHEET)

| GEJALA / ERROR | PENYEBAB & SOLUSI CEPAT |
| :--- | :--- |
| Menu Cloud Security "No results" | Normal. Cloud Security hanya untuk API |
|  | CloudTrail/S3. Buka menu Agents atau |
|  | Endpoint Security -> Threat Hunting. |
| Status Agent "Never connected" | Port 1514 TCP diblokir oleh Security |
|  | Group EC2 AWS. Buka Port 1514 di AWS. |
| Log Agent: "Connection refused" | Salah masukkan IP Server di ossec.conf |
|  | atau service wazuh-manager sedang stop. |
| Log Agent: "Invalid key" | Kunci di /var/ossec/etc/client.keys |
|  | tidak cocok dengan Manager. Hapus file |
|  | tersebut lalu jalankan agent-auth lagi. |
| Log: "Unable to add agent | Nama/IP agent sudah ada di Manager |
| (from manager)" | (duplicate). Hapus via manage_agents |
|  | atau pasang force_insert=yes di server. |
| Status Agent "Disconnected" | Client Linux mati, network terputus, |
|  | atau service wazuh-agent stop. |

================================================================================