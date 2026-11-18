# KETERANGAN TAMBAHAN & PANDUAN OPERASIONAL PRODUKSI: - ORACLE CLOUD INFRASTRUCTURE (OCI) LOAD BALANCER UNTUK WAZUH DASHBOARD

Dokumen ini disusun sebagai keterangan tambahan dan catatan operasional resmi
berdasarkan kasus konfigurasi OCI Load Balancer (kasus: LB 'lb_wazuh' dengan IP
publik 168.110.214.196, Backend Set 'bs_lb_2026-0914-1120', backend instance
'trees-wazuh-prod' IP privat 10.10.30.196:443 di subnet sn-prod-mgmt, serta node
health check internal Load Balancer 10.10.0.69 di subnet sn-prod-lb, VCN prod-vcn
Region ap-batam-1).

## DAFTAR ISI

1. Ringkasan Kasus Lapangan:
   - Kasus A: Backend Berstatus "Critical - Connection failed"
   - Kasus B: Health Check "Ok", tapi Akses Publik Mengalami Timeout
   - Kasus C: Health Check "Ok" (Status "Warning"), Browser Menampilkan "502 Bad Gateway"
2. Analisis Akar Masalah (Root Cause Analysis)
   - 2.1 Mismatch Protocol Health Check (Plaintext HTTP vs HTTPS TLS di Port 443)
   - 2.2 Investigasi Firewall OS pada AlmaLinux 10 (Status firewalld, iptables, nft)
   - 2.3 Pembuktian Konektivitas Antar-Subnet via Bastion Host
   - 2.4 Kesalahan Fatal Pengisian Ingress Rule: Source Port vs Destination Port Range
   - 2.5 Mengapa Muncul 502 Bad Gateway Saat Health Check Sudah Hijau/Ok?
3. Panduan Solusi Teknis Langkah-Demi-Langkah (Action Plan)
   - 3.1 Konfigurasi Health Check Terbaik di Backend Set (TCP Port 443)
   - 3.2 Opsi Alternatif Health Check HTTP/HTTPS (Penanganan Respons HTTP 302)
   - 3.3 Koreksi Ingress Rule Security List OCI untuk Akses Internet Publik
   - 3.4 Solusi 502: Mengaktifkan "Use SSL" pada Backend Set Tanpa Peer Verification
   - 3.5 Solusi Alternatif 502: Mode TCP Listener (SSL Pass-Through Murni)
4. Matriks Arsitektur Jaringan OCI VCN untuk Wazuh
   - 4.1 Detail Subnet & Alokasi IP (sn-prod-lb vs sn-prod-mgmt)
   - 4.2 Matriks Rule Security List & NSG (Ingress & Egress)
   - 4.3 Port-Port Esensial Wazuh Lainnya (1514, 1515, 55000)
5. Runbook Diagnostik Lapangan (Command Cheat Sheet)
6. Tabel Ringkasan Masalah OCI Load Balancer & Solusinya

## 1. RINGKASAN KASUS LAPANGAN

Pada OCI Console (Networking -> Load Balancers -> lb_wazuh):
- Region              : ap-batam-1
- VCN                 : prod-vcn (10.10.0.0/16)
- Subnet LB           : sn-prod-lb (10.10.0.0/24 - Public)
- Subnet Backend      : sn-prod-mgmt (10.10.30.0/24 - Private)
- Instance Backend    : trees-wazuh-prod (10.10.30.196)
- Instance Bastion    : trees-harpa-bastion-prod (10.10.0.125 / Public 129.225.7.97)
- LB Public IP        : 168.110.214.196
- LB Health Checker IP: 10.10.0.69
- Backend Set         : bs_lb_2026-0914-1120

Tiga Fase Kendala yang Dihadapi:
1. Fase 1: Health check berstatus "Critical - Connection failed" pada target 10.10.30.196:443.
2. Fase 2: Health check berhasil diubah ke TCP dan berstatus "Ok", namun akses dari
   internet ke https://168.110.214.196 mengalami Connection Timed Out.
3. Fase 3: Ingress Rule diperbaiki sehingga traffic internet berhasil masuk, tetapi
   browser menampilkan halaman error "HTTP 502 Bad Gateway" dan status Backend
   menjadi "Warning".

## 2. ANALISIS AKAR MASALAH (ROOT CAUSE ANALYSIS)

### 2.1 MISMATCH PROTOCOL HEALTH CHECK (PLAINTEXT HTTP VS HTTPS TLS DI PORT 443)

- Wazuh Dashboard berjalan di atas engine Node.js (OpenSearch Dashboards) dan
  secara default mengikat koneksi HTTPS terenkripsi SSL/TLS pada port 443 (0.0.0.0:443).
- Konfigurasi bawaan Health Check pada OCI Load Balancer disetel ke:
  - Protocol: HTTP
  - Port: 443
  - Status code: 200
  - URL path: /
- Ketika Load Balancer mengirimkan probe plaintext HTTP (misal: "GET / HTTP/1.1")
  ke socket TLS Node.js Wazuh, engine Node.js mengalami error TLS Handshake
  (unhandled record type / invalid method) dan langsung memutus koneksi secara paksa
  (TCP FIN/RST - ECONNRESET).
- OCI Load Balancer mencatat pemutusan koneksi sepihak ini sebagai status
  "Critical - Connection failed".
- Selain itu, Wazuh Dashboard secara default mengembalikan kode HTTP 302 Found
  (redirect ke /app/login?), sehingga meskipun probe TLS berhasil, ekspektasi kode 200
  akan tetap menyebabkan health check gagal.

### 2.2 INVESTIGASI FIREWALL OS PADA ALMALINUX 10 (STATUS FIREWALLD, IPTABLES, NFT)

- Pada pengujian di server 'trees-wazuh-prod':
  - `sudo firewall-cmd --list-all`  -> command not found
  - `sudo iptables -L -n -v`        -> command not found
  - `sudo nft list ruleset`         -> command not found
- AlmaLinux 10 (EL10) telah sepenuhnya menghapus paket legacy iptables dan secara
  default menggunakan subsistem nftables. Karena tidak ada firewall daemon aktif,
  terbukti 100% bahwa di level Guest OS VM sama sekali tidak ada firewall yang
  memblokir koneksi masuk.
- Service port 443 aktif dan mendengarkan pada interface global (0.0.0.0:443),
  dijalankan oleh PID node.

### 2.3 PEMBUKTIAN KONEKTIVITAS ANTAR-SUBNET VIA BASTION HOST

- Instance Bastion ('trees-harpa-bastion-prod' / 10.10.0.125) berada di subnet yang
  sama dengan Load Balancer ('sn-prod-lb' / 10.10.0.0/24).
- Ketika dijalankan pengujian dari Bastion:
  `curl -k -I https://10.10.30.196:443`
  Didapatkan hasil:
  ```text
  HTTP/1.1 302 Found
```text
location: /app/login?
osd-name: trees-wazuh-prod
```
```

- Ini membuktikan secara empiris:
  1. Routing VCN lokal antar-subnet (10.10.0.0/24 ke 10.10.30.0/24) bekerja sempurna.
  2. Ingress Rule Security List pada subnet backend telah mengizinkan port 443.
  3. Wazuh Dashboard merespons request HTTPS dengan benar.

### 2.4 KESALAHAN FATAL PENGISIAN INGRESS RULE: SOURCE PORT VS DESTINATION PORT RANGE

- Pada 'Default Security List for prod-vcn', ditemukan aturan ingress berikut:
  - Source                 : 0.0.0.0/0
  - IP Protocol            : TCP
  - Source Port Range      : 443  <-- [KESALAHAN FATAL]
  - Destination Port Range : All  <-- [KESALAHAN FATAL]
- Konsekuensi Teknis:
  - 'Source Port' adalah nomor port asal dari pengirim (klien/browser).
  - Ketika browser atau klien dari internet menghubungi https://168.110.214.196,
    sistem operasi klien selalu mengalokasikan port acak (ephemeral port, rentang
    32768-65535, misalnya port 52341) sebagai Source Port, dengan tujuan
    Destination Port 443.
  - Karena aturan OCI mensyaratkan Source Port = 443, semua paket dari internet
    yang menggunakan port ephemeral otomatis di-DROP oleh Security List OCI sebelum
    mencapai Load Balancer.
  - Akibatnya, koneksi dari internet mengalami Connection Timed Out.

### 2.5 MENGAPA MUNCUL 502 BAD GATEWAY SAAT HEALTH CHECK SUDAH HIJAU/OK?

- Pengujian eksternal menghasilkan respons:
  ```text
  HTTP/1.1 502 Bad Gateway
```text
X-Request-Id: 6447b232b21ea9d81fa431dd62f08bc6
```
```

- Mengapa ini terjadi padahal Health Check TCP sudah "Ok"?
  1. Health check TCP hanya memeriksa apakah socket port 443 merespons handshake SYN-ACK.
     Karena port 443 Wazuh hidup, health check TCP lulus ("Ok").
  2. Namun ketika traffic klien asli masuk melalui Listener HTTPS (Layer 7), OCI Load
     Balancer bertindak sebagai reverse-proxy dan mencoba meneruskan request HTTP
     tersebut ke backend server 10.10.30.196:443.
  3. Pada konfigurasi Backend Set, opsi "Use SSL" belum diaktifkan (Load Balancer
     mencoba mengirimkan plaintext HTTP ke port 443 Wazuh), ATAU opsi "Use SSL" aktif
     tetapi mencentang "Verify peer certificate" (OCI menolak sertifikat self-signed Wazuh).
  4. Karena negosiasi backend gagal saat memproses request HTTP klien, OCI Load Balancer
     mengembalikan kode "502 Bad Gateway" kepada browser dan memberi label "Warning"
     pada backend server.

## 3. PANDUAN SOLUSI TEKNIS LANGKAH-DEMI-LANGKAH (ACTION PLAN)

### 3.1 KONFIGURASI HEALTH CHECK TERBAIK DI BACKEND SET (TCP PORT 443)

Solusi paling stabil dan direkomendasikan untuk Wazuh Dashboard di OCI adalah
menggunakan Health Check berbasis TCP:
1. Buka OCI Console -> Networking -> Load Balancers -> pilih 'lb_wazuh'.
2. Pada menu Resources (sebelah kiri), klik **Backend Sets**.
3. Klik Backend Set Anda: **bs_lb_2026-0914-1120**.
4. Klik tab/tombol **Edit Health Check**.
5. Atur parameter berikut:
   - **Protocol**                : TCP
   - **Port**                    : 443
   - **Interval in milliseconds**: 10000 (10 detik)
   - **Timeout in milliseconds** : 3000 (3 detik)
   - **Number of retries**       : 3
6. Klik **Save Changes**. Status Health Check instance menjadi **Ok**.

### 3.2 OPSI ALTERNATIF HEALTH CHECK HTTP/HTTPS (PENANGANAN RESPONS HTTP 302)

Jika kebijakan sistem mengharuskan verifikasi pada Layer 7 (HTTP):
- **Protocol**        : HTTPS (atau HTTP dengan SSL backend aktif)
- **Port**            : 443
- **URL Path (URI)**  : / atau /app/login
- **Status Code**     : 302 (atau 200,302)
- **Plaintext Check** : Jangan centang "Force plaintext health checks".

### 3.3 KOREKSI INGRESS RULE SECURITY LIST OCI UNTUK AKSES INTERNET PUBLIK

Perbaiki aturan port 443 agar Load Balancer dapat menerima traffic dari internet:
1. Buka OCI Console -> Networking -> Virtual Cloud Networks -> **prod-vcn**.
2. Klik **Security Lists** -> pilih **Default Security List for prod-vcn** (atau
   Security List yang terpasang pada subnet sn-prod-lb).
3. Hapus aturan 0.0.0.0/0 yang memiliki Source Port 443, lalu klik **Add Ingress Rules**:
   - **Stateless**              : No (Stateful)
   - **Source Type**            : CIDR
   - **Source CIDR**            : 0.0.0.0/0 (atau IP publik kantor/VPN Anda)
   - **IP Protocol**            : TCP
   - **Source Port Range**      : KOSONGKAN (artinya All / sembarang ephemeral port)
   - **Destination Port Range** : 443
   - **Description**            : Allow HTTPS Inbound from Internet to Load Balancer
4. Klik **Add Ingress Rules**.

### 3.4 SOLUSI 502: MENGAKTIFKAN "USE SSL" PADA BACKEND SET TANPA PEER VERIFICATION

Untuk menghilangkan error 502 Bad Gateway pada arsitektur Layer 7 (HTTPS Listener):
1. Buka Backend Set **bs_lb_2026-0914-1120** di OCI Console.
2. Klik tombol **Edit** (Edit Backend Set).
3. Centang kotak **Use SSL**.
4. **PENTING**: Pastikan opsi **Verify peer certificate** dalam keadaan **TIDAK DICENTANG / NONAKTIF**.
   *(Wazuh menggunakan sertifikat self-signed. Jika diverifikasi, OCI akan menolak sertifikat tersebut dan tetap menghasilkan 502).*
5. Klik **Save Changes**.

### 3.5 SOLUSI ALTERNATIF 502: MODE TCP LISTENER (SSL PASS-THROUGH MURNI)

Jika Anda tidak ingin mengelola terminasi atau re-enkripsi SSL di OCI Load Balancer:
1. Masuk ke **Listeners** pada Load Balancer 'lb_wazuh'.
2. Ubah / Buat Listener:
   - **Protocol**   : **TCP**
   - **Port**       : **443**
   - **Backend Set**: **bs_lb_2026-0914-1120**
3. Dalam mode TCP Listener (Layer 4), Load Balancer hanya meneruskan paket data terenkripsi
   langsung ke Wazuh tanpa membuka paket HTTP. Masalah 502 Bad Gateway dipastikan tidak
   akan pernah terjadi.

## 4. MATRIKS ARSITEKTUR JARINGAN OCI VCN UNTUK WAZUH

### 4.1 DETAIL SUBNET & ALOKASI IP

| Nama Subnet | CIDR Subnet | Tipe Akses | Komponen Terpasang |
| :--- | :--- | :--- | :--- |
| sn-prod-lb | 10.10.0.0/24 | Public (Regional) | OCI LB (10.10.0.69) |
|  |  |  | Bastion (10.10.0.125) |
| sn-prod-mgmt | 10.10.30.0/24 | Private (Regional) | trees-wazuh-prod |
|  |  |  | (10.10.30.196) |
| sn-prod-app | 10.10.10.0/24 | Private (Regional) | Aplikasi Produksi |
| sn-prod-db | 10.10.20.0/24 | Private (Regional) | Database Produksi |

### 4.2 MATRIKS RULE SECURITY LIST / NSG

#### A. Subnet sn-prod-lb (Load Balancer & Bastion)

| Tipe | Source / Destination | Protocol | Port | Keterangan |
| :--- | :--- | :--- | :--- | :--- |
| Ingress | 0.0.0.0/0 | TCP | Dst: 443 | Akses Web HTTPS Klien |
| Ingress | 0.0.0.0/0 | TCP | Dst: 22 | Akses SSH Bastion |
| Egress | 10.10.30.0/24 | TCP | Dst: 443 | LB Forward ke Wazuh |
| Egress | 0.0.0.0/0 | ALL | All Ports | Akses Internet / Default |

#### B. Subnet sn-prod-mgmt (Server Wazuh)

| Tipe | Source / Destination | Protocol | Port | Keterangan |
| :--- | :--- | :--- | :--- | :--- |
| Ingress | 10.10.0.0/24 | TCP | Dst: 443 | Health Check & Web LB |
| Ingress | 10.10.0.0/24 | TCP | Dst: 22 | SSH dari Bastion |
| Egress | 0.0.0.0/0 | ALL | All Ports | Egress via NAT Gateway |

### 4.3 PORT-PORT ESENSIAL WAZUH LAINNYA

Jika di kemudian hari Load Balancer juga digunakan untuk meneruskan traffic Agent:
- Port 1514 (TCP/UDP) : Komunikasi event dan log Wazuh Agent (remoted).
- Port 1515 (TCP)     : Pendaftaran otomatis agent baru (authd registration).
- Port 55000 (TCP)    : Wazuh Manager RESTful API.
Pastikan port-port di atas ditambahkan pada Security List jika agent berada di luar VCN.

## 5. RUNBOOK DIAGNOSTIK LAPANGAN (COMMAND CHEAT SHEET)

1. Cek port listening dan process binding di server backend:
   `sudo ss -tulpn | grep 443`
   atau
   `sudo netstat -tulpn | grep 443`

2. Uji respons lokal HTTPS di server backend:
   `curl -k -I https://localhost:443`
   `curl -k -I https://10.10.30.196:443`

3. Uji respons dari Bastion host (satu subnet dengan LB):
   `curl -k -I https://10.10.30.196:443`

4. Monitor paket health check OCI LB secara live (packet-buffered):
   `sudo tcpdump -nn -U -i any host 10.10.0.69`

5. Verifikasi konektivitas ICMP (Ping) ke node internal LB:
   `ping -c 3 10.10.0.69`

6. Uji akses IP publik Load Balancer dari mesin luar / laptop:
   `curl -i -k https://168.110.214.196:443`
   - Jika berhasil: HTTP/1.1 302 Found (atau 200 OK)
   - Jika timeout : Periksa Source Port Range vs Destination Port di Security List
   - Jika 502     : Aktifkan "Use SSL" di Backend Set tanpa "Verify peer cert"

## 6. TABEL RINGKASAN MASALAH OCI LOAD BALANCER & SOLUSINYA

| Gejala / Pesan Error | Kemungkinan Akar Masalah | Solusi Teknis |
| :--- | :--- | :--- |
| Critical - | Health check HTTP dikirim | Ubah Health Check Protocol ke TCP |
| Connection failed | ke port HTTPS/TLS (443). | port 443 pada Backend Set. |
| Critical - | Ingress rule subnet backend | Tambahkan Ingress rule TCP 443 |
| Connection failed | memblokir IP/subnet LB. | dengan Source CIDR subnet LB. |
| Critical - | NSG pada Load Balancer | Tambahkan Egress rule TCP 443 |
| Connection failed | tidak memiliki Egress rule. | ke subnet backend pada NSG LB. |
| Status code mismatch / | Health check HTTPS dengan | Ganti match status code ke 302 |
| Invalid response code | ekspektasi 200, tapi Wazuh | atau beralih ke TCP health check. |
|  | merespons 302 Found. |  |
| Health Check OK, tapi | Port 443 diisi di kolom | Pindahkan 443 ke Destination Port; |
| Akses Publik Timeout | Source Port Range pada SL. | Source Port Range dikosongkan. |
| Health Check OK, tapi | Backend Set belum pakai SSL | Centang "Use SSL" di Backend Set & |
| HTTP 502 Bad Gateway | atau sertifikat self-signed | matikan "Verify peer certificate", |
| (Backend status "Warning") | ditolak oleh peer check LB. | atau ubah Listener ke TCP 443. |

## Dibuat: 14 September 2026 - Lingkungan: OCI Production (ap-batam-1) - Wazuh Dashboard
