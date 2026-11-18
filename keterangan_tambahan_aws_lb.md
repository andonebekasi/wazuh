# KETERANGAN TAMBAHAN & PANDUAN OPERASIONAL PRODUKSI: - AWS APPLICATION LOAD BALANCER (ALB) & TARGET GROUP UNTUK WAZUH DASHBOARD

Dokumen ini disusun sebagai keterangan tambahan dan catatan operasional resmi 
berdasarkan kasus konfigurasi AWS Application Load Balancer (ALB) dan Target Group 
untuk server Wazuh Dashboard (kasus: instance 'trees-wazuh-prod', Target Group 
'trees-wazuh-prod-tg', Load Balancer 'trees-wazuh-prod-lb').

## DAFTAR ISI

1. Ringkasan Kasus Lapangan: Target Berstatus Unhealthy (HTTP 302)
2. Analisis Akar Masalah (Root Cause Analysis)
   - 2.1 Mengapa Wazuh Dashboard Mengirimkan Respons HTTP 302?
   - 2.2 Mengapa Mengubah Path ke '/app/login' Masih Tetap Gagal?
   - 2.3 Mengapa ALB Menolak Kode 302 Secara Default?
3. Panduan Solusi Teknis Langkah-Demi-Langkah (Action Plan)
   - 3.1 Mengubah Success Codes ke '200,302' atau '200-399'
   - 3.2 Menyesuaikan Health Check Path
   - 3.3 Optimasi Interval & Threshold (Mempercepat Transisi Status Healthy)
4. Konfigurasi Wajib & Rekomendasi AWS ALB untuk Wazuh Dashboard
   - 4.1 Target Group Stickiness (Session Persistence)
   - 4.2 ALB Idle Timeout untuk Query Berat & Indexer Search
   - 4.3 Matriks Security Group (ALB SG vs EC2 Wazuh SG)
   - 4.4 Listener HTTP (Port 80) Redirect Otomatis ke HTTPS (Port 443)
   - 4.5 Penanganan Sertifikat SSL (ACM vs Self-Signed Backend)
5. Checklist Verifikasi & Pengujian Lapangan (Testing Runbook)
6. Tabel Ringkasan Error Code Health Check ALB & Solusinya

## 1. RINGKASAN KASUS LAPANGAN: TARGET BERSTATUS UNHEALTHY (HTTP 302)

Pada AWS Console (EC2 -> Target Groups -> trees-wazuh-prod-tg):
- Target Group ARN : arn:aws:elasticloadbalancing:ap-southeast-3:223563812681:targetgroup/trees-wazuh-prod-tg/44b48408e10c9747
- Target Type      : Instance
- Protocol : Port  : HTTPS: 443
- Target Instance  : i-07ea107235ebb1201 (trees-wazuh-prod)
- Health Status    : Unhealthy
- Detail Status    : "Health checks failed with these codes: [302]"
- Health Check Path: Diuji pada '/' maupun '/app/login'
- Success Codes    : '200'

Pertanyaan / Kebingungan Lapangan:
"Mengapa target dianggap Unhealthy padahal port 443 aktif, instance running, 
dan path sudah dicoba diarahkan ke /app/login?"

## 2. ANALISIS AKAR MASALAH (ROOT CAUSE ANALYSIS)

### 2.1 MENGAPA WAZUH DASHBOARD MENGIRIMKAN RESPONS HTTP 302?

- Wazuh Dashboard dibangun di atas platform OpenSearch Dashboards (fork Kibana).
- Arsitektur web ini mengimplementasikan autentikasi berbasis session state & cookie.
- Ketika ada request GET HTTP/HTTPS masuk tanpa menyertakan cookie session valid 
  (seperti request health check berkala dari ALB), web server dashboard secara otomatis 
  melakukan redirect (HTTP 302 Found) ke mekanisme login internal atau routing sub-path.
- Dengan demikian, respons `302` adalah PERILAKU NORMAL DAN SEHAT dari aplikasi 
  Wazuh Dashboard ketika menerima anonymous request.

### 2.2 MENGAPA MENGUBAH PATH KE '/app/login' MASIH TETAP GAGAL?

- Pada tes kedua, path health check diubah menjadi `/app/login`. Namun, ALB tetap 
```text
melaporkan: `Health checks failed with these codes: [302]`.
```

- Hal ini terjadi karena OpenSearch Dashboards / Wazuh Dashboard melakukan routing 
  internal berbasis JavaScript SPA (Single Page Application). Endpoint `/app/login` 
  pun masih melakukan evaluasi header, redirect internal dengan query parameter 
  (misal `?nextUrl=...`), atau redirect antar modul autentikasi sebelum halaman 
  benar-benar dirender dengan kode 200.
- Karena **Success codes** pada Target Group masih disetel ke **`200`**, respons 302 
  tersebut tetap ditolak oleh ALB.

### 2.3 MENGAPA ALB MENOLAK KODE 302 SECARA DEFAULT?

- Standar default AWS Application Load Balancer (ALB) untuk matcher "Success codes" 
  hanyalah angka `200`.
- Bagi ALB, setiap kode status di luar angka yang terdaftar di matcher dianggap sebagai 
  indikasi backend sedang bermasalah (misalnya backend mengalami loop redirect 
  atau halaman maintenance).
- Oleh karena itu, kunci utama bukan hanya pada path, melainkan pada matcher kode sukses.

## 3. PANDUAN SOLUSI TEKNIS LANGKAH-DEMI-LANGKAH (ACTION PLAN)

Untuk mengubah status instance dari Unhealthy menjadi Healthy, lakukan langkah berikut:

### 3.1 MENGUBAH SUCCESS CODES KE '200,302' ATAU '200-399'

1. Buka AWS Management Console.
2. Navigasi ke **EC2** -> **Target Groups** (di menu Load Balancing sebelah kiri).
3. Pilih Target Group: **`trees-wazuh-prod-tg`**.
4. Klik tab **Health checks**, lalu klik tombol **Edit**.
5. Pada bagian **Success codes**, hapus nilai default `200`, lalu ganti dengan:
   ```text
   200,302
   ```
   *Atau Anda bisa menggunakan rentang lengkap:*
   ```text
   200-399
   ```
   *(Rentang 200-399 mencakup semua kode sukses 200 OK serta redirect 301/302/307).*

### 3.2 MENYESUAIKAN HEALTH CHECK PATH

- Kembalikan parameter **Path** ke root:
  ```text
  /
  ```
- Alasan: Menggunakan path `/` lebih aman, standar, dan tidak rentan patah jika versi 
  Wazuh Dashboard di-upgrade (di mana path internal login bisa berubah antar rilis).

### 3.3 OPTIMASI INTERVAL & THRESHOLD (MEMPERCEPAT HEALTHY)

Secara default di AWS:
- Healthy threshold  : 5 consecutive successes
- Interval           : 30 seconds
Artinya, sistem membutuhkan waktu: 5 x 30 detik = 150 detik (2,5 menit) 
hanya untuk mengubah status target dari Unhealthy ke Healthy.

Agar ALB mendeteksi perubahan status lebih cepat saat pengujian/produksi:
- **Healthy threshold**  : Ubah menjadi **`2`**
- **Unhealthy threshold**: Tetap **`2`**
- **Timeout**            : **`5`** seconds
- **Interval**           : Ubah menjadi **`10`** seconds (atau 15 seconds)
Hasil: Target akan berubah menjadi Healthy hanya dalam waktu **20 detik**!

Klik **Save changes**.

## 4. KONFIGURASI WAJIB & REKOMENDASI AWS ALB UNTUK WAZUH DASHBOARD

Setelah Target Group berstatus Healthy, ada beberapa konfigurasi kritis tingkat 
produksi yang wajib diperhatikan agar koneksi web console Wazuh tidak bermasalah:

### 4.1 TARGET GROUP STICKINESS (SESSION PERSISTENCE)

- **Masalah**: Wazuh Dashboard menyimpan sesi pengguna di memori/cookie. Jika ALB 
  me-route request berikutnya ke target lain atau sesi terputus, user akan sering 
  mengalami logout mendadak ("Session Expired") saat membuka tab baru.
- **Solusi**:
  1. Di Target Group `trees-wazuh-prod-tg`, buka tab **Attributes** -> klik **Edit**.
  2. Aktifkan **Stickiness**.
  3. Tipe: **Duration-based (load balancer generated cookie)**.
  4. Durasi: **1 day** (86400 seconds) atau minimal **4 hours** (14400 seconds).
  5. Klik **Save changes**.

### 4.2 ALB IDLE TIMEOUT UNTUK QUERY BERAT & INDEXER SEARCH

- **Masalah**: Ketika administrator mencari log dalam rentang 7-30 hari terakhir 
  atau visualisasi kompleks di Wazuh Dashboard, backend Wazuh Indexer butuh waktu 
  lebih dari 60 detik untuk memproses query JSON agregasi.
- Secara default, AWS ALB memiliki **Idle timeout = 60 detik**. Jika query melebihi 
  60 detik, ALB akan memutuskan koneksi dan menampilkan error `504 Gateway Timeout`.
- **Solusi**:
  1. Buka EC2 -> Load Balancers -> pilih `trees-wazuh-prod-lb`.
  2. Buka tab **Attributes** -> klik **Edit**.
  3. Ubah **Idle timeout** dari `60` menjadi minimal **`120`** atau **`300`** detik.
  4. Klik **Save changes**.

### 4.3 MATRIKS SECURITY GROUP (ALB SG VS EC2 WAZUH SG)

Jangan pernah membuka port 443 di EC2 Wazuh ke public internet (0.0.0.0/0) jika sudah 
menggunakan ALB Internet-Facing!

Pola yang benar:
1. **Security Group ALB (contoh: `sg-alb-wazuh`)**:
   - Inbound Rules:
     * Port `443` (HTTPS) -> Source: `0.0.0.0/0` (atau IP Publik Kantor/VPN)
     * Port `80` (HTTP)   -> Source: `0.0.0.0/0` (untuk auto-redirect)
   - Outbound Rules:
     * All traffic atau Port `443` -> Destination: Security Group EC2 Wazuh.

2. **Security Group EC2 Wazuh (contoh: `sg-ec2-wazuh`)**:
   - Inbound Rules:
     * Port `443` (HTTPS) -> Source: `sg-alb-wazuh` (HANYA izinkan dari SG ALB!)
     * Port `1514` & `1515` -> Source: IP VPC / Client Subnet (Traffic Agent)
     * Port `22` (SSH)    -> Source: IP Bastion Host / VPN Admin
   - Outbound Rules:
     * All traffic ke Internet/NAT Gateway (untuk update repository/threat intel).

### 4.4 LISTENER HTTP (PORT 80) REDIRECT OTOMATIS KE HTTPS (PORT 443)

Pastikan pengguna yang mengetik URL tanpa https:// tidak mengalami error:
1. Di Load Balancer `trees-wazuh-prod-lb`, buka tab **Listeners and rules**.
2. Klik **Add listener**.
3. Protocol: **HTTP**, Port: **80**.
4. Default action: Pilih **Redirect to URL**.
   - Protocol: **HTTPS**
   - Port: **443**
   - Status code: **301 - Permanently moved**
5. Klik **Save**.

### 4.5 PENANGANAN SERTIFIKAT SSL (ACM VS SELF-SIGNED BACKEND)

- **Frontend (ALB Listener 443)**: Wajib menggunakan sertifikat SSL resmi (misal dari 
  AWS Certificate Manager / ACM yang terikat ke domain kustom Anda).
- **Backend (Target Group HTTPS 443)**: Server Wazuh EC2 menggunakan sertifikat 
  internal default (self-signed cert). 
  *Catatan Penting AWS ALB*: AWS ALB TIDAK MEMVALIDASI apakah sertifikat SSL di sisi 
  target EC2 valid atau self-signed. ALB tetap dapat melakukan enkripsi TLS ke target 
  selama port 443 menerima handshake TLS. Oleh karena itu, target group HTTPS 443 
  berfungsi normal meskipun Wazuh memakai self-signed certificate bawaan.

## 5. CHECKLIST VERIFIKASI & PENGUJIAN LAPANGAN (TESTING RUNBOOK)

Setelah konfigurasi di atas diterapkan, lakukan verifikasi berikut:

1. Verifikasi Status Target Group di AWS Console:
   - Status Target: **Healthy** (angka Healthy = 1, Unhealthy = 0).
   - Health status details: Tidak ada error code.

2. Verifikasi Respons HTTP Manual dari CLI / Terminal:
   Jalankan perintah curl ke DNS name ALB:
   ```bash
```bash
curl -Ik https://trees-wazuh-prod-lb-2078783426.ap-southeast-3.elb.amazonaws.com
```
```

   Output normal:
   ```text
   HTTP/2 302 
```text
location: /app/login?nextUrl=...
server: OpenSearch Dashboards
```
```

3. Verifikasi Akses Web Browser:
   - Buka browser ke DNS ALB atau domain Anda.
   - Halaman login Wazuh Dashboard harus muncul sempurna dengan gembok SSL valid.
   - Login menggunakan akun `admin` Wazuh.
   - Pastikan navigasi ke menu Security Events, Agent Management, dan Modules 
     berjalan mulus tanpa sering diminta login ulang.

## 6. TABEL RINGKASAN ERROR CODE HEALTH CHECK ALB & SOLUSINYA

| Kode / Pesan Error di Target Group | Penyebab Utama | Solusi Cepat |
| :--- | :--- | :--- |
| Failed with codes: [302] | Backend me-redirect request | Tambahkan '302' ke 'Success codes' di TG |
|  | (Normal untuk Wazuh Web) | (isi: '200,302' atau '200-399') |
| Request timed out | Traffic diblokir Firewall / | Pastikan Security Group EC2 mengizinkan |
|  | Security Group | inbound port 443 dari Security Group ALB |
| Connection refused | Service Wazuh Dashboard | Cek service di EC2: |
|  | mati di port 443 | 'systemctl status wazuh-dashboard' |
| 502 Bad Gateway (saat buka web) | Target tidak sehat / | Pastikan target berstatus Healthy di TG |
|  | SSL handshake gagal | dan port target sesuai (HTTPS 443) |
| 504 Gateway Timeout (saat buka web) | Query log di Wazuh Dashboard | Naikkan 'Idle timeout' di Attributes ALB |
|  | melebihi 60 detik | dari 60 detik menjadi 120 - 300 detik |

## AKHIR KETERANGAN TAMBAHAN
