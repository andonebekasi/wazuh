# KETERANGAN TAMBAHAN & PANDUAN TROUBLESHOOTING: - PENYEBAB & SOLUSI WAZUH AGENT BARU TIDAK MUNCUL DI DASHBOARD WAZUH

Dokumen ini disusun sebagai keterangan tambahan dan panduan operasional terpisah 
berdasarkan kasus instalasi Wazuh Agent di server client (contoh: hrptrsdbprd), 
di mana status systemd service wazuh-agent sudah berstatus ACTIVE (RUNNING), 
namun entitas agent tersebut belum muncul atau tidak terdeteksi di Wazuh Dashboard.

## DAFTAR ISI

1. Ringkasan Masalah Lapangan: Mengapa Service "Running" tapi Belum Terlihat?
2. Alur Cepat Diagnosa Mandiri (Triage 3 Menit)
3. Lima (5) Akar Masalah Utama (Root Causes) & Solusi Teknis
   - 3.1 Masalah 1: Agent Belum Memiliki Kunci Autentikasi (client.keys Kosong)
   - 3.2 Masalah 2: IP / Alamat Wazuh Manager di ossec.conf Salah atau Masih Default
   - 3.3 Masalah 3: Traffic Terblokir di AWS Security Group / Firewall (Port 1514 & 1515)
   - 3.4 Masalah 4: Konflik Nama / IP Agent di Sisi Wazuh Manager (Duplicate Agent)
   - 3.5 Masalah 5: Delay Sinkronisasi Wazuh Indexer / Dashboard Filter
4. Panduan Eksekusi Perbaikan Langkah-Demi-Langkah (Runbook di Client)
5. Verifikasi & Pengecekan dari Sisi Wazuh Server / Manager
6. Tabel Matriks Pesan Error Log (ossec.log) & Solusi Cepat
7. Kasus Nyata Lapangan: Penanganan Status "Never Connected" & Duplikasi Nama
   - 7.1 Mengapa Dashboard Masih "Never connected" Setelah agent-auth Berhasil?
   - 7.2 Analisis Kasus Duplikat: ID 002 (hrptrsdbprd) vs ID 003 (hrptrsdbprd-new)
   - 7.3 Dua Pilihan Solusi (Solusi Instan vs Solusi Bersih Standar Produksi)

## 1. RINGKASAN MASALAH LAPANGAN: MENGAPA SERVICE "RUNNING" TAPI BELUM TERLIHAT?

Pada log terminal client:
  ● wazuh-agent.service - Wazuh agent
```text
Active: active (running)
CGroup: /system.slice/wazuh-agent.service
```

             ├─72595 /var/ossec/bin/wazuh-execd
             ├─72604 /var/ossec/bin/wazuh-agentd
             ├─72618 /var/ossec/bin/wazuh-syscheckd
             ├─72629 /var/ossec/bin/wazuh-logcollector
             └─72647 /var/ossec/bin/wazuh-modulesd

KONDISI INI WAJAR DAN SERING TERJADI:
- Daemon `wazuh-agent` dan sub-prosesnya (agentd, syscheckd, logcollector, modulesd) 
  didesain untuk tetap hidup (running) di sistem operasi Linux meskipun:
  1. Belum memiliki sertifikat/kunci registrasi (`client.keys`).
  2. Belum berhasil melakukan handshake TCP ke Wazuh Manager.
  3. Wazuh Manager sedang offline atau port tidak dapat dijangkau.
- Wazuh Dashboard TIDAK membaca proses lokal di server client; Dashboard hanya 
  menampilkan data yang dilaporkan oleh **Wazuh Indexer / Wazuh Manager**.
- Jika Manager belum pernah menerima pendaftaran (enrollment) atau data keepalive 
  dari client, maka Dashboard sama sekali tidak mengetahui keberadaan agent tersebut.

## 2. ALUR CEPAT DIAGNOSA MANDIRI (TRIAGE 3 MENIT)

Lakukan 4 langkah pengecekan berikut di terminal client (ec2-user@hrptrsdbprd):

[LANGKAH 1] Cek Log Agent (Sumber Kebenaran Utama):
```bash
sudo tail -n 50 /var/ossec/logs/ossec.log

Perhatikan baris dengan label `wazuh-agentd: ERROR` atau `wazuh-agentd: WARNING`.

[LANGKAH 2] Cek Kunci Autentikasi / Registrasi:
```

sudo cat /var/ossec/etc/client.keys

- Jika output KOSONG (0 bytes) -> Agent belum terdaftar ke Wazuh Manager.
- Jika ada 1 baris (berisi ID, Nama, IP, dan Key acak) -> Agent sudah terdaftar.

[LANGKAH 3] Cek Konfigurasi Alamat Manager:
```bash
sudo grep -A 6 "<server>" /var/ossec/etc/ossec.conf

Pastikan tag `<address>` berisi IP Private atau Hostname Wazuh Manager yang benar, 
bukan `0.0.0.0` atau placeholder `MANAGER_IP`.

[LANGKAH 4] Tes Keterjangkauan Port Jaringan ke Manager:
```

Ganti `<IP_WAZUH_MANAGER>` dengan IP Manager Anda:

# Uji port pendaftaran (authd)
nc -zvw3 <IP_WAZUH_MANAGER> 1515

# Uji port komunikasi data & log (agentd)
nc -zvw3 <IP_WAZUH_MANAGER> 1514

(Jika utility `nc` belum terpasang, gunakan: `curl -v telnet://<IP_WAZUH_MANAGER>:1514`)

## 3. LIMA (5) AKAR MASALAH UTAMA (ROOT CAUSES) & SOLUSI TEKNIS

### 3.1 MASALAH 1: AGENT BELUM MEMILIKI KUNCI AUTENTIKASI (client.keys KOSONG)

Penyebab:
Saat instalasi `wazuh-agent-4.9.2`, jika Anda tidak mengoper variabel 
`WAZUH_MANAGER="<IP>"` ke dalam perintah instalasi, file `/var/ossec/etc/client.keys` 
akan kosong. Tanpa key ini, daemon `wazuh-agentd` tidak memiliki identitas untuk 
berkomunikasi dengan Manager.

Pesan di `ossec.log`:
```text
wazuh-agentd: ERROR: No authentication key found.
wazuh-agentd: ERROR: (1214): Problem retrieving keys from server: No key was found.
```

Solusi:
Jalankan proses registrasi manual menggunakan utilitas `agent-auth`:

#### A. Registrasi Standar (tanpa password):

```bash
sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_MANAGER> -A hrptrsdbprd
```

#### B. Registrasi dengan Password (jika Manager menggunakan authd.pass):

```bash
sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_MANAGER> -A hrptrsdbprd -P "PasswordRegistrasiAnda"
```

#### C. Registrasi dengan Group Tertentu:

```bash
sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_MANAGER> -A hrptrsdbprd -G "production,hr-payroll"
```

Setelah muncul pesan `Valid key received`, restart agent:
```bash
sudo systemctl restart wazuh-agent
```

### 3.2 MASALAH 2: IP / ALAMAT WAZUH MANAGER DI ossec.conf SALAH ATAU MASIH DEFAULT

Penyebab:
Di dalam `/var/ossec/etc/ossec.conf`, blok `<client><server><address>` belum diisi 
dengan IP / DNS Wazuh Manager yang valid.

Pesan di `ossec.log`:
```text
wazuh-agentd: INFO: Trying to connect to server (0.0.0.0:1514/tcp).
wazuh-agentd: WARNING: (1210): Queue '/var/ossec/queue/sockets/queue' not accessible: 'Connection refused'.
```

Solusi:
Edit file konfigurasi:
```bash
sudo nano /var/ossec/etc/ossec.conf
```

Cari blok berikut dan sesuaikan:
```text
<client>
  <server>
    <address>172.1.12.93</address>   <!-- Ganti dengan IP Manager Anda -->
    <port>1514</port>
    <protocol>tcp</protocol>
  </server>
</client>
```

Simpan perubahan (Ctrl+O, Enter, Ctrl+X), lalu restart service:
```bash
sudo systemctl restart wazuh-agent
```

### 3.3 MASALAH 3: TRAFFIC TERBLOKIR DI AWS SECURITY GROUP / FIREWALL (PORT 1514 & 1515)

Penyebab:
Wazuh menggunakan dua port utama:
1. **Port 1515/TCP**: Digunakan saat proses pendaftaran (Enrollment / agent-auth).
2. **Port 1514/TCP**: Digunakan untuk streaming log dan status heartbeat agent.

Jika Security Group pada instance Wazuh Manager (atau Firewall lokal firewalld/ufw/iptables) 
tidak membuka port 1514 dan 1515 untuk IP private instance client (`hrptrsdbprd`), 
maka paket data akan di-drop.

Pesan di `ossec.log`:
```text
wazuh-agentd: WARNING: (1216): Unable to connect to any server.
wazuh-agentd: INFO: Trying to connect to server (172.1.12.93:1514/tcp)...
wazuh-agentd: ERROR: Connection timed out
```

Solusi di AWS Console / Security Group:
1. Masuk ke AWS Console -> EC2 -> Security Groups.
2. Cari Security Group yang menempel pada **EC2 Wazuh Manager**.
3. Tambahkan **Inbound Rule**:
   - Type: Custom TCP | Port: 1514 | Source: Subnet VPC Client atau IP Client (/32)
   - Type: Custom TCP | Port: 1515 | Source: Subnet VPC Client atau IP Client (/32)
4. Pastikan **Outbound Rule** pada Security Group Client mengizinkan koneksi keluar (All Traffic atau TCP 1514-1515 ke arah Manager).

### 3.4 MASALAH 4: KONFLIK NAMA / IP AGENT DI SISI WAZUH MANAGER (DUPLICATE AGENT)

Penyebab:
Jika sebelumnya pernah ada agent dengan nama `hrptrsdbprd` atau dengan IP yang sama 
terdaftar di Manager, Manager akan menolak pendaftaran ulang jika fitur 
`force_insert` tidak diaktifkan pada authd Manager.

Pesan di `ossec.log`:
```text
wazuh-agentd: ERROR: Unable to add agent (from manager)
ERROR: Duplicate agent name: hrptrsdbprd
```

Solusi (Dijalankan di Sisi Server Wazuh Manager):
1. Login ke instance Wazuh Manager via SSH.
2. Cek apakah nama host sudah ada di database:
```bash
sudo /var/ossec/bin/manage_agents -l
```

3. Jika sudah ada agent lama dengan nama tersebut, catat ID-nya (contoh: ID 005), 
   lalu hapus entitas lama tersebut:
```bash
sudo /var/ossec/bin/manage_agents -r 005
```

4. Setelah dihapus dari Manager, jalankan ulang `agent-auth` di sisi client.

### 3.5 MASALAH 5: DELAY SINKRONISASI WAZUH INDEXER / DASHBOARD FILTER

Penyebab:
Terkadang agent sebenarnya sudah berhasil terdaftar dan terhubung (status: Active), 
tetapi di Wazuh Dashboard:
- Filter status di Dashboard sedang terkunci pada kondisi tertentu (misal filter hanya menampilkan status "Disconnected").
- Wazuh Indexer membutuhkan waktu 10 - 30 detik untuk mengindeks entitas baru ke Elasticsearch/OpenSearch.

Solusi:
1. Pada Wazuh Dashboard, masuk ke menu **Wazuh -> Agents**.
2. Klik tombol **Clear filters** atau ubah view filter dari "Active" ke "All".
3. Lakukan hard refresh browser (Ctrl + F5 atau Cmd + Shift + R).

## 4. PANDUAN EKSEKUSI PERBAIKAN LANGKAH-DEMI-LANGKAH (RUNBOOK DI CLIENT)

Berikut adalah urutan perintah perbaikan standar yang dapat langsung Anda 
eksekusi di server `hrptrsdbprd`:

# 1. Masuk sebagai root atau gunakan sudo
sudo su -

# 2. Cek isi client.keys
cat /var/ossec/etc/client.keys
# Jika kosong, lanjutkan ke langkah 3.

# 3. Daftarkan agent ke Manager (Ganti IP 172.1.12.93 dengan IP Manager Anda)
/var/ossec/bin/agent-auth -m 172.1.12.93 -A hrptrsdbprd

# Bila sukses, akan muncul output:
# 2026/09/08 17:15:00 wazuh-authd: INFO: Started (pid: ...)
# 2026/09/08 17:15:01 wazuh-authd: INFO: Connected to 172.1.12.93:1515
# 2026/09/08 17:15:02 wazuh-authd: INFO: Valid key received

# 4. Pastikan ossec.conf mengarah ke IP Manager yang benar
grep -A 5 "<server>" /var/ossec/etc/ossec.conf

# 5. Restart wazuh-agent service
systemctl restart wazuh-agent

# 6. Pantau log apakah sudah terhubung dengan sukses
tail -n 25 /var/ossec/logs/ossec.log

Tanda BERHASIL terhubung pada log:
```text
wazuh-agentd: INFO: Connected to the server (172.1.12.93:1514/tcp).
wazuh-agentd: INFO: Server responded. Agent authenticated.
```

## 5. VERIFIKASI & PENGECEKAN DARI SISI WAZUH SERVER / MANAGER

Jika Anda memiliki akses SSH ke Wazuh Manager, jalankan verifikasi berikut:

1. Cek daftar seluruh agent yang terdaftar:
```bash
sudo /var/ossec/bin/manage_agents -l
```

2. Cek status koneksi real-time agent:
```bash
sudo /var/ossec/bin/agent_control -l
```

   Contoh Output Berhasil:
     Wazuh agent_control. List of available agents:
```text
ID: 000, Name: wazuh-server, IP: 127.0.0.1, Active/Local
ID: 001, Name: hrptrsdbprd, IP: 172.1.x.x, Active
```

3. Cek detail spesifik satu agent:
```bash
sudo /var/ossec/bin/agent_control -i 001
```

## 6. TABEL MATRIKS PESAN ERROR LOG (ossec.log) & SOLUSI CEPAT

| Pesan Error pada ossec.log | Penyebab & Solusi Cepat |
| :--- | :--- |
| "No authentication key found" | File client.keys kosong. |
|  | Solusi: Jalankan `/var/ossec/bin/agent-auth -m <IP>`. |
| "Unable to connect to any server" / "Connection ref." | Port 1514 tertutup atau IP salah. |
|  | Solusi: Buka port 1514 di AWS SG dan cek address di conf. |
| "Unable to add agent (from manager)" | Ditolak server (versi mismatch, duplikat, butuh pass). |
|  | Solusi: Cek versi agent vs manager, atau cek auth pass. |
| "Connected to the server (...) / Agent authenticated" | KONEKSI BERHASIL 100%. |
|  | Agent siap tampil di Dashboard (refresh browser). |

## 7. KASUS NYATA LAPANGAN: PENANGANAN STATUS "NEVER CONNECTED" & DUPLIKASI NAMA

### 7.1 MENGAPA DASHBOARD MASIH "NEVER CONNECTED" SETELAH AGENT-AUTH BERHASIL?

```bash
Ketika proses `agent-auth` dijalankan dan menampilkan pesan:
  2026/09/08 17:08:56 agent-auth: INFO: Valid key received

Itu berarti kunci kriptografi telah berhasil diambil dari Manager dan disimpan 
ke dalam file lokal `/var/ossec/etc/client.keys`.

Namun di Wazuh Dashboard (atau `manage_agents -l`), status agent tersebut masih 
tercatat sebagai "never connected" (atau "never connected (1)" pada dashboard).

MENGAPA INI TERJADI?
- Perintah `agent-auth` HANYA bertugas mengambil key dan menulis file `client.keys`.
- Daemon `wazuh-agentd` yang sedang berjalan di background TIDAK secara otomatis 
  membaca ulang file `client.keys` tersebut saat file diperbarui.
- Selama service `wazuh-agent` belum di-restart, daemon `wazuh-agentd` masih 
  beroperasi tanpa key autentikasi lama, sehingga belum pernah melakukan koneksi 
  TCP ke port 1514 Wazuh Manager dengan identitas barunya.
- AKIBATNYA: Status di Manager & Dashboard tetap "Never connected".

SOLUSI:
Cukup jalankan restart pada server client:
  sudo systemctl restart wazuh-agent

Begitu service di-restart, `wazuh-agentd` akan langsung memuat key dari `client.keys`, 
menghubungi Manager via port 1514/TCP, mengirim data OS dan IP, lalu statusnya di 
Dashboard akan seketika berubah menjadi **Active** (warna hijau).

7.2 ANALISIS KASUS DUPLIKAT: ID 002 (hrptrsdbprd) VS ID 003 (hrptrsdbprd-new)
```

Pada terminal Wazuh Manager (`wazuh-tree-prod`), output `manage_agents -l` menampilkan:
  Available agents:
```text
ID: 001, Name: hrptrsapprd, IP: any
ID: 002, Name: hrptrsdbprd, IP: any
ID: 003, Name: hrptrsdbprd-new, IP: any
```

Dan di Dashboard menampilkan:
  - ID 001: hrptrsapprd     | 172.1.12.18 | Amazon Linux 2 | active
  - ID 002: hrptrsdbprd     | 172.1.12.22 | Amazon Linux 2 | active
  - ID 003: hrptrsdbprd-new | any         | -              | never connected

ANALISIS TEKNIS:
1. ID 002 (`hrptrsdbprd`) adalah entitas dari server LAMA (tercatat OS Amazon Linux 2).
2. Ketika Anda menginstal server baru (Amazon Linux 2023) dan mencoba mendaftarkan 
   kembali dengan nama asli:
```bash
sudo /var/ossec/bin/agent-auth -m 172.1.12.93 -A hrptrsdbprd
```

   Wazuh Manager menolaknya dengan error:
```text
ERROR: Duplicate agent name: hrptrsdbprd (from manager)
ERROR: Unable to add agent (from manager)
```

   karena nama `hrptrsdbprd` masih terkunci di database Manager pada ID 002.
3. Anda kemudian menggunakan nama baru `hrptrsdbprd-new`, yang sukses didaftarkan 
   sebagai ID 003.

### 7.3 DUA PILIHAN SOLUSI LAPANGAN

[PILIHAN A: SOLUSI INSTAN (TETAP PAKAI hrptrsdbprd-new)]
Jika Anda tidak mempermasalahkan nama host di dashboard berakhiran `-new`:
1. Di server client (`hrptrsdbprd`):
```bash
sudo systemctl restart wazuh-agent
```

2. Pantau log:
```bash
sudo tail -n 25 /var/ossec/logs/ossec.log
```

3. Refresh Wazuh Dashboard. Status ID 003 akan langsung berubah menjadi Active.

[PILIHAN B: SOLUSI BERSIH & STANDAR PRODUKSI (PAKAI NAMA ASLI hrptrsdbprd)]
Sangat direkomendasikan untuk lingkungan produksi agar nama server konsisten dan 
tidak meninggalkan entitas "ghost / zombie agent" di database Wazuh.

#### Langkah 1: Di Server Wazuh Manager (`ec2-user@wazuh-tree-prod`)

Hapus entitas agent lama (ID 002) dan ID sementara (ID 003):
```bash
sudo /var/ossec/bin/manage_agents -r 002
```

  (Tekan 'y' dan Enter untuk konfirmasi)

```bash
sudo /var/ossec/bin/manage_agents -r 003
```

  (Tekan 'y' dan Enter untuk konfirmasi)

Verifikasi bahwa ID 002 dan 003 sudah terhapus:
```bash
sudo /var/ossec/bin/manage_agents -l
```

#### Langkah 2: Di Server Client (`ec2-user@hrptrsdbprd`)

Daftarkan kembali dengan nama resmi `hrptrsdbprd`:
```bash
sudo /var/ossec/bin/agent-auth -m 172.1.12.93 -A hrptrsdbprd
```

#### Langkah 3: Restart Wazuh Agent di Client:

```bash
sudo systemctl restart wazuh-agent
```

#### Langkah 4: Validasi Koneksi di Client:

```bash
sudo tail -n 25 /var/ossec/logs/ossec.log
```

  Output Sukses:
```text
wazuh-agentd: INFO: Connected to the server (172.1.12.93:1514/tcp).
wazuh-agentd: INFO: Server responded. Agent authenticated.
```

Hasil Akhir di Dashboard:
Dashboard hanya menampilkan agent aktif yang valid dan rapi:
- ID 001: hrptrsapprd (Active)
- ID 002: hrptrsdbprd (Active, Amazon Linux 2023)

## AKHIR DOKUMEN

