# KETERANGAN OPERASIONAL & PANDUAN TERPISAH: FRESH INSTALL VS UPGRADE - WAZUH AGENT PADA AMAZON LINUX (AWS EC2)

Dokumen ini disusun sebagai dokumentasi teknis dan panduan operasional terpisah 
berdasarkan kasus nyata di server hrptrsdbprd ([ec2-user@hrptrsdbprd ~]$), di mana
eksekusi perintah yum install dengan variabel environment WAZUH_MANAGER, 
WAZUH_AGENT_GROUP, dan WAZUH_AGENT_NAME menghasilkan proses "Upgrade" 
(wazuh-agent.x86_64 4.9.2-1 -> 4.14.7-1) dan bukan "Fresh Install".

## DAFTAR ISI

1. Analisis Kasus Lapangan: Mengapa Terjadi Upgrade dan Env Var Diabaikan?
2. Aturan Kompatibilitas Versi (Wazuh Manager vs Wazuh Agent)
3. Panduan Prosedur A: Clean Fresh Install (Instalasi Bersih Dari Nol)
4. Panduan Prosedur B: In-Place Upgrade & Penyesuaian Konfigurasi Manual
5. Matriks Perbandingan: Fresh Install vs In-Place Upgrade
6. Checklist Verifikasi & Validasi Koneksi Agent-ke-Manager
7. Troubleshooting Masalah Registrasi & Koneksi

## 1. ANALISIS KASUS LAPANGAN: MENGAPA TERJADI UPGRADE DAN ENV VAR DIABAIKAN?

### 1.1 LOG TERMINAL KASUS

Saat administrator menjalankan:
```bash
sudo WAZUH_MANAGER='172.1.12.93' \
WAZUH_AGENT_GROUP='production,hr-payroll' \
WAZUH_AGENT_NAME='hrptrsdbprd' \
yum install -y wazuh-agent
```

Output transaksi YUM:
```text
Updating:
  wazuh-agent     x86_64     4.14.7-1     wazuh     11 M
```

  Transaction Summary:
    Upgrade  1 Package
```text
Updating : wazuh-agent-4.14.7-1.x86_64
Cleanup  : wazuh-agent-4.9.2-1.x86_64
```

  Complete!

### 1.2 MENGAPA BUKAN FRESH INSTALL?

Pada sistem tersebut, paket `wazuh-agent` versi 4.9.2-1 SUDAH TERPASANG sebelumnya. 
Dalam manajemen paket RPM/YUM di Linux:
- Perintah `yum install <nama-paket>` memiliki perilaku:
  * Jika paket BELUM ada di sistem -> Melakukan FRESH INSTALL.
  * Jika paket SUDAH ada dan tersedia versi lebih baru di repositori -> Secara 
    otomatis beralih fungsi menjadi UPGRADE / UPDATE paket.

### 1.3 MENGAPA VARIABEL ENVIRONMENT (WAZUH_MANAGER, DLL.) DIABAIKAN?

Paket RPM Wazuh Agent memiliki skrip instalasi internal (RPM scriptlets `%post`):
- Variabel environment seperti `WAZUH_MANAGER`, `WAZUH_AGENT_GROUP`, dan 
  `WAZUH_AGENT_NAME` HANYA dieksekusi saat proses instalasi awal (fresh install, 
  kondisi `$1 == 1` pada RPM spec).
- Jika RPM mendeteksi proses upgrade (`$1 == 2`), skrip `%post` sengaja TIDAK 
  menimpa file konfigurasi `/var/ossec/etc/ossec.conf` dan file identitas 
  `/var/ossec/etc/client.keys` yang sudah ada, guna mencegah rusaknya konfigurasi 
  produksi yang telah berjalan.
- AKIBATNYA:
  * Versi binary ter-update ke 4.14.7-1.
  * Namun IP Manager, Group, dan Nama Agent TIDAK BERUBAH (tetap menggunakan 
    konfigurasi lama yang tersimpan di `/var/ossec/etc/ossec.conf`).

## 2. ATURAN KOMPATIBILITAS VERSI (WAZUH MANAGER VS WAZUH AGENT)

PENTING: Perhatikan versi Wazuh Manager Anda sebelum memutuskan versi Agent!

Aturan Resmi Wazuh:
1. Versi Wazuh Agent TIDAK BOLEH LEBIH TINGGI daripada versi Wazuh Manager.
   - Contoh TIDAK VALID / ERROR: Manager v4.9.2 < Agent v4.14.7
   - Jika Manager Anda masih versi 4.9.2, Agent 4.14.7 berisiko gagal terhubung,
     terjadi error komunikasi protokol, atau data telemetri tidak terbaca.
2. Versi Wazuh Agent BOLEH SAMA atau LEBIH RENDAH daripada versi Manager.
   - Contoh VALID: Manager v4.14.x >= Agent v4.9.2 (Backward Compatible).
   - Contoh VALID: Manager v4.14.x == Agent v4.14.x.

Jika Wazuh Manager Anda sudah v4.14.x, maka upgrade ke 4.14.7 sudah tepat.
Namun jika Wazuh Manager Anda masih v4.9.2, Anda HARUS menginstal versi 4.9.2-1 
(lihat panduan instalasi versi spesifik di bagian 3).

## 3. PANDUAN PROSEDUR A: CLEAN FRESH INSTALL (INSTALASI BERSIH DARI NOL)

Gunakan prosedur ini jika Anda ingin:
- Menghapus seluruh data, cache, sertifikat, dan identitas agent lama.
- Menerapkan parameter `WAZUH_MANAGER`, `WAZUH_AGENT_GROUP`, dan `WAZUH_AGENT_NAME` 
  secara otomatis dan murni dari awal melalui package installer.

### LANGKAH 1: Stop Service Wazuh Agent

Hentikan service yang sedang berjalan:
```bash
sudo systemctl stop wazuh-agent
```

### LANGKAH 2: Hapus (Uninstall) Paket Wazuh Agent

Hapus paket wazuh-agent menggunakan YUM:
```bash
sudo yum remove -y wazuh-agent
```

### LANGKAH 3: Bersihkan Residu Direktori /var/ossec (CRITICAL STEP)

Saat paket di-uninstall via YUM/RPM, direktori `/var/ossec` biasanya TIDAK dihapus 
secara menyeluruh karena berisi file konfigurasi yang dimodifikasi (`ossec.conf`) 
dan kunci registrasi (`client.keys`).

Jika direktori ini tidak dihapus, instalasi berikutnya TIDAK AKAN dianggap fresh 
install dan variabel environment akan tetap diabaikan!

Lakukan backup kunci lama (opsional jika masih dibutuhkan sebagai arsip):
```bash
sudo cp /var/ossec/etc/client.keys /tmp/client.keys.bak.$(date +%F) 2>/dev/null || true
```

Hapus seluruh direktori residu `/var/ossec`:
```bash
sudo rm -rf /var/ossec
```

### LANGKAH 4: Eksekusi Fresh Install dengan Variabel Environment

PILIHAN A.1: Fresh Install Versi Terbaru (v4.14.x)
Gunakan opsi ini jika Wazuh Manager Anda sudah versi 4.14.x atau lebih baru:

```bash
sudo WAZUH_MANAGER='172.1.12.93' \
WAZUH_AGENT_GROUP='production,hr-payroll' \
WAZUH_AGENT_NAME='hrptrsdbprd' \
yum install -y wazuh-agent
```

PILIHAN A.2: Fresh Install Versi Spesifik (v4.9.2-1)
Gunakan opsi ini jika Wazuh Manager Anda masih versi 4.9.2:

```bash
sudo WAZUH_MANAGER='172.1.12.93' \
WAZUH_AGENT_GROUP='production,hr-payroll' \
WAZUH_AGENT_NAME='hrptrsdbprd' \
yum install -y wazuh-agent-4.9.2-1
```

Catatan Tambahan (Jika Manager Menggunakan Password Registrasi / authd.pass):
Sertakan variabel `WAZUH_REGISTRATION_PASSWORD`:

```bash
sudo WAZUH_MANAGER='172.1.12.93' \
WAZUH_AGENT_GROUP='production,hr-payroll' \
WAZUH_AGENT_NAME='hrptrsdbprd' \
WAZUH_REGISTRATION_PASSWORD='PasswordRegistrasiManagerAnda' \
yum install -y wazuh-agent
```

### LANGKAH 5: Verifikasi Otomasi Konfigurasi Hasil Fresh Install

Periksa apakah IP manager sudah otomatis terisi di `/var/ossec/etc/ossec.conf`:
```bash
sudo grep -A 2 "<address>" /var/ossec/etc/ossec.conf
```

Output yang diharapkan:
  <address>172.1.12.93</address>

### LANGKAH 6: Reload Systemd, Aktifkan & Jalankan Service

Jalankan service wazuh-agent:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
sudo systemctl status wazuh-agent
```

## 4. PANDUAN PROSEDUR B: IN-PLACE UPGRADE & PENYESUAIAN MANUAL

Gunakan prosedur ini jika paket sudah terlanjur ter-upgrade ke 4.14.7-1 dan Anda 
TIDAK INGIN menghapus / meng-uninstall paket dari awal, melainkan hanya ingin 
menyesuaikan IP Manager, Nama Agent, atau Group secara langsung.

### LANGKAH 1: Periksa dan Sesuaikan IP Manager di ossec.conf

Buka dan periksa file konfigurasi:
```bash
sudo grep -A 2 "<address>" /var/ossec/etc/ossec.conf
```

Jika alamat belum menunjuk ke `172.1.12.93`, lakukan perubahan pada blok `<client>`:
Edit file `/var/ossec/etc/ossec.conf`:
```bash
sudo sed -i 's/<address>.*<\/address>/<address>172.1.12.93<\/address>/g' /var/ossec/etc/ossec.conf
```

Atau pastikan struktur XML di dalam `/var/ossec/etc/ossec.conf` adalah:
```text
<client>
  <server>
    <address>172.1.12.93</address>
    <port>1514</port>
    <protocol>tcp</protocol>
  </server>
</client>
```

### LANGKAH 2: Daftarkan Ulang (Re-enroll) Menggunakan agent-auth

Karena variabel environment diabaikan saat upgrade, daftarkan nama agent dan group 
secara manual langsung ke auth daemon (authd) Wazuh Manager:

#### A. Jika Manager TIDAK memerlukan password registrasi:

```bash
sudo /var/ossec/bin/agent-auth -m 172.1.12.93 -A hrptrsdbprd -G "production,hr-payroll"
```

#### B. Jika Manager MEMERLUKAN password registrasi:

```bash
sudo /var/ossec/bin/agent-auth -m 172.1.12.93 -A hrptrsdbprd -G "production,hr-payroll" -P "PasswordRegistrasiManagerAnda"
```

Output yang sukses:
  2026/09/08 16:35:00 agent-auth: INFO: Started (pid: 12345).
  2026/09/08 16:35:01 agent-auth: INFO: Connected to 172.1.12.93:1515
  2026/09/08 16:35:01 agent-auth: INFO: Valid key received

Periksa apakah key telah terisi:
```bash
sudo cat /var/ossec/etc/client.keys
```

  (Harus menampilkan baris: ID_AGENT NAMA_AGENT IP_AGENT CRYPTO_KEY)

### LANGKAH 3: Restart Service Wazuh Agent

Terapkan perubahan dengan me-restart service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl restart wazuh-agent
sudo systemctl status wazuh-agent
```

## 5. MATRIKS PERBANDINGAN: FRESH INSTALL VS IN-PLACE UPGRADE

| Parameter | Prosedur Fresh Install | Prosedur In-Place Upgrade |
| :--- | :--- | :--- |
| Kondisi Awal | Paket di-remove & /var/ossec | Paket lama sudah ada di sistem |
|  | dihapus bersih sebelum install | langsung di-update via yum |
| Variabel Env | DIBACA & DITERAPKAN OTOMATIS | DIABAIKAN oleh RPM installer |
| (WAZUH_MANAGER, dll.) | ke file ossec.conf & registrasi | (konfigurasi lama dipertahankan |
| File client.keys | Dibuat baru dari awal saat | Mempertahankan key lama jika |
|  | agent pertama kali mendaftar | tidak di-enroll ulang |
| File ossec.conf | Dibuat baru (template standar | Mempertahankan modifikasi |
|  | dengan IP manager terisi) | file ossec.conf sebelumnya |
| Kebutuhan agent-auth | Otomatis (tidak perlu manual) | Perlu dijalankan jika ingin |
|  |  | update nama agent / group |
| Rekomendasi Waktu | Setup node baru / migrasi | Update berkala minor patch |
| Penggunaan | server ke manager baru | tanpa mengubah arsitektur |

## 6. CHECKLIST VERIFIKASI & VALIDASI KONEKSI AGENT-KE-MANAGER

Setelah menjalankan Fresh Install ataupun In-Place Upgrade, lakukan checklist 
berikut di sisi Agent (`hrptrsdbprd`):

[ ] 1. Cek Status Service Agent:
```bash
sudo systemctl status wazuh-agent
```

       (Pastikan berstatus: "active (running)")

[ ] 2. Cek Log Komunikasi Agent:
```bash
sudo grep -iE "connected to the server|valid key received|error" /var/ossec/logs/ossec.log | tail -n 20
```

       (Pastikan muncul log: "Connected to the server (172.1.12.93:1514/tcp)")

[ ] 3. Verifikasi File Kunci Agent:
```bash
sudo ls -la /var/ossec/etc/client.keys
```

       (File tidak boleh 0 byte / kosong)

[ ] 4. Pengecekan dari Sisi Wazuh Manager (172.1.12.93):
```bash
sudo /var/ossec/bin/agent_control -l | grep hrptrsdbprd
```

       (Pastikan status agent menunjukkan "Active")

## 7. TROUBLESHOOTING MASALAH REGISTRASI & KONEKSI

### 7.1 PORT NETWORK & AWS SECURITY GROUP TERBLOKIR

Wazuh Agent memerlukan akses jaringan ke Wazuh Manager pada 2 port TCP:
- TCP Port 1515: Port registrasi (Wazuh Enrollment / Authd). Digunakan saat 
  menjalankan `agent-auth` atau proses auto-enrollment awal.
- TCP Port 1514: Port komunikasi data telemetry & log (Wazuh Remoted). Digunakan 
  selama agent berjalan (`active running`).

Uji konektivitas port dari server Agent ke Manager:
```text
nc -zvw3 172.1.12.93 1514
nc -zvw3 172.1.12.93 1515
```

Jika muncul error `Connection timed out`, periksa AWS Security Group pada 
EC2 Wazuh Manager (172.1.12.93) dan pastikan Inbound Rule mengizinkan port 1514 
dan 1515 dari subnet/IP EC2 Agent.

### 7.2 ERROR "INVALID KEY FOR SERVER" ATAU "WAITING FOR SERVER REPLY"

Penyebab: Key pada `client.keys` di agent tidak cocok dengan database key di manager.
Solusi:
1. Hapus isi file `client.keys` di agent:
```bash
sudo rm -f /var/ossec/etc/client.keys
```

2. Jalankan ulang pendaftaran manual via `agent-auth`:
```bash
sudo /var/ossec/bin/agent-auth -m 172.1.12.93 -A hrptrsdbprd -G "production,hr-payroll"
```

3. Restart wazuh-agent:
```bash
sudo systemctl restart wazuh-agent
```

### 7.3 KEBINGUNGAN DOWNGRADE KEMBALI KE v4.9.2 (JIKA MANAGER v4.9.2)

Jika ternyata manager Anda v4.9.2 dan agent v4.14.7 tidak kompatibel:
```bash
sudo systemctl stop wazuh-agent
sudo yum downgrade -y wazuh-agent-4.9.2-1
sudo systemctl restart wazuh-agent
```

  (Atau ikuti panduan lengkap di file `keterangan_downgrade_wazuh_client.txt`)

## AKHIR DOKUMEN - KETERANGAN FRESH INSTALL WAZUH AGENT
