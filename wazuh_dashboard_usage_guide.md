# PANDUAN OPERASIONAL & CARA PENGGUNAAN LENGKAP WAZUH DASHBOARD - (Endpoint Monitoring, Analisis Metrik Keamanan & Seluruh Modul Wazuh)

Dokumen ini disusun sebagai panduan operasional teknis terperinci untuk Security 
Analyst, DevOps, dan System Administrator dalam memahami tampilan dashboard, 
indikator data, metrik kepatuhan (compliance), mitigasi temuan keamanan, serta 
tata cara penggunaan seluruh modul yang tersedia pada Wazuh Dashboard v4.9.x.

## DAFTAR ISI

1.  PENGENALAN TAMPILAN ENDPOINT & IDENTITAS AGENT (hrptrsapprd)
    1.1 Penjelasan Field Metadata Agent
    1.2 Fitur Navigasi Utama: Inventory Data, Stats, Configuration
2.  ANALISIS MENDALAM METRIK WIDGET DASHBOARD (LAST 24 HOURS)
    2.1 MITRE ATT&CK: Top Tactics Breakdown & Investigasi Anomali
    2.2 Compliance PCI DSS: Analisis Kode Kontrol & Log Trigger
    2.3 FIM (File Integrity Monitoring): Status "No Recent Events" & Cara Uji
    2.4 Events Count Evolution: Membaca Pola & Spike Timestamp
    2.5 SCA (Security Configuration Assessment): CIS Benchmark & Analisis Skor 40%
3.  PANDUAN CARA PENGGUNAAN MODUL-MODUL WAZUH DASHBOARD
    3.1 Endpoint Security
        - Configuration Assessment (SCA)
        - Malware Detection (Rootcheck & Integrasi YARA)
        - File Integrity Monitoring (FIM / Syscheck)
    3.2 Threat Intelligence
        - Threat Hunting (SIEM Discover & KQL / Lucene Query Syntax)
        - Vulnerability Detection (Deteksi Kerentanan CVE)
        - MITRE ATT&CK Matrix & Mapping
        - VirusTotal Integration
    3.3 Security Operations & Regulatory Compliance
        - PCI DSS (Payment Card Industry Data Security Standard)
        - GDPR (General Data Protection Regulation)
        - HIPAA (Health Insurance Portability and Accountability Act)
        - NIST 800-53 (Security and Privacy Controls)
        - TSC (Trust Services Criteria / SOC 2)
    3.4 Cloud Security
        - Docker Monitoring
        - Amazon Web Services (AWS Integration)
        - Google Cloud Platform (GCP)
        - GitHub Audit Logs
        - Office 365 (Microsoft 365 Security)
4.  PANDUAN PRAKTIS REMEDIASI SKOR SCA 40% PADA AMAZON LINUX 2
    4.1 Audit File Konfigurasi SSH Daemon (/etc/ssh/sshd_config)
    4.2 Audit Password Hashing & Shadow Permissions
    4.3 Audit & Hardening Kernel Parameter (/etc/sysctl.d/99-cis.conf)
    4.4 Audit Layanan Tidak Terpakai (Legacy Daemons) & Core Dumps
    4.5 Audit Sistem Logging Auditd (/etc/audit/rules.d/audit.rules)
5.  STANDARD OPERATING PROCEDURE (SOP) HARIAN & INVESTIGASI INSIDEN
    5.1 Daily SOC/Admin Routine Checklist (10 Menit Rutinitas Harian)
    5.2 Alur Triage Alert Berlevel Tinggi (Level >= 10)
    5.3 Strategi Whitelist & Penanganan False Positive (local_rules.xml)
    5.4 Otomasi Respon Keamanan (Active Response Execution)

## 1. PENGENALAN TAMPILAN ENDPOINT & IDENTITAS AGENT (hrptrsapprd)

Ketika Anda membuka menu:
Wazuh Home ──> Endpoints ──> hrptrsapprd (001)

Dashboard menampilkan panel ringkasan informasi dan status agent target. Berikut 
arti setiap parameter dan implikasi operasionalnya:

### 1.1 PENJELASAN FIELD METADATA AGENT

1. ID: 001
   - Nomor pengenal unik yang diberikan oleh Wazuh Manager saat pendaftaran 
     (registration/enrollment via authd).
   - ID 000 selalu dicadangkan untuk Wazuh Manager itu sendiri.
   - Digunakan dalam query filter dashboard: `agent.id: "001"`.

2. Status: active
   - Menandakan agent terhubung secara real-time dan berkomunikasi aktif dengan 
     Wazuh Manager melalui port TCP 1514.
   - Status lain yang mungkin muncul:
     * disconnected : Agent mati, service stop, atau terblokir firewall.
     * never_connected: Agent terdaftar di manager tetapi belum pernah kirim keep-alive.
     * pending      : Agent sedang menunggu kunci otorisasi atau sinkronisasi awal.

3. IP Address: 172.1.12.18
   - Alamat IP internal private dari server target (dalam subnet AWS VPC).
   - Catatan Arsitektur: Ini adalah IP host saat pendaftaran. Komunikasi internal 
     ke Wazuh Manager aman karena berada dalam VPC yang sama atau melalui VPC Peering.

4. Version: Wazuh v4.9.2
   - Versi biner Wazuh Agent yang terpasang pada EC2 target.
   - Kompatibilitas: Versi agent tidak boleh lebih tinggi dari versi Wazuh Manager 
     (Wazuh Server). Versi 4.9.2 membawa peningkatan performa Syscollector dan 
     koneksi FIM whodata.

5. Groups: default
   - Grup konfigurasi tersentralisasi (Centralized Configuration).
   - Konfigurasi pada group `default` diatur di Wazuh Manager pada file:
     `/var/ossec/etc/shared/default/agent.conf`
   - Setiap perubahan rule/konfigurasi pada grup ini akan di-push secara otomatis 
     ke seluruh agent anggota tanpa perlu SSH ke server satu per satu.

6. Operating System: Amazon Linux 2
   - Distribusi sistem operasi yang dideteksi oleh kernel detector Wazuh.
   - Menentukan template rule SCA mana yang akan diaplikasikan (yaitu benchmark 
     khusus Amazon Linux 2 berbasis RPM & SysV/Systemd).

7. Cluster Node: node01
   - Nama node worker atau master Wazuh Manager yang sedang menangani koneksi 
     agent ini. Menunjukkan bahwa cluster manager Anda berstatus aktif dan seimbang.

8. Registration Date: Sep 8, 2026 @ 16:21:42.000
   - Waktu pertama kali agent berhasil melakukan autentikasi registrasi ke server.

9. Last Keep Alive: Sep 9, 2026 @ 15:38:53.000
   - Waktu paket heartbeat terakhir diterima oleh Manager.
   - Secara default, Wazuh Agent mengirim heartbeat setiap 10 detik. Jika dalam 
     waktu 10-30 menit tidak ada keep-alive, status akan otomatis berubah menjadi 
     `disconnected`.

### 1.2 FITUR NAVIGASI UTAMA: INVENTORY DATA, STATS, CONFIGURATION

Di bawah nama agent `hrptrsapprd (001)`, terdapat 3 tab penting:

#### A. [ Inventory Data ] (Syscollector)

   Menyediakan inventaris perangkat keras dan perangkat lunak lengkap tanpa perlu 
   login SSH:
   - Hardware: Informasi CPU model, jumlah core, utilisasi RAM, swap, arsitektur.
   - Network: Daftar interface jaringan (eth0, lo), IP private, MAC address, MTU, gateway.
   - Packages: Seluruh paket RPM yang terinstall pada Amazon Linux 2 beserta versinya. 
     Sangat krusial untuk melacak paket yang kedaluwarsa atau paket ilegal/tidak terdaftar.
   - Ports: Port TCP/UDP yang sedang LISTENING beserta PID dan nama proses yang 
     membukanya (membantu mendeteksi backdoor yang membuka port tersembunyi).
   - Processes: Snapshot proses yang sedang aktif berjalan di server saat scan terakhir.

#### B. [ Stats ]

   Menampilkan grafik statistik performa internal daemon agent:
   - Total event yang dihasilkan per detik/menit.
   - Event buffer usage (mengetahui apakah buffer penyimpanan sementara agent penuh).
   - Rata-rata waktu pengiriman log ke Manager.

#### C. [ Configuration ]

   Menampilkan konfigurasi efektif Wazuh Agent yang sedang aktif, termasuk hasil merger 
   antara konfigurasi lokal `/var/ossec/etc/ossec.conf` dengan konfigurasi grup tersentral 
   dari Manager (`agent.conf`).

## 2. ANALISIS MENDALAM METRIK WIDGET DASHBOARD (LAST 24 HOURS)

Pada dashboard agent `hrptrsapprd`, muncul beberapa widget penting dengan data 24 jam 
terakhir:

### 2.1 MITRE ATT&CK: TOP TACTICS BREAKDOWN & INVESTIGASI ANOMALI

Data yang ditampilkan:
- Defense Evasion     : 985
- Privilege Escalation: 984
- Initial Access      : 499
- Persistence         : 499
- Lateral Movement    : 6

MENGAPA ANGKA INI TINGGI DAN APA MAKSUDNYA?
1. Defense Evasion (985 Events) & Privilege Escalation (984 Events):
   - Jangan langsung panik: Jumlah angka 900+ BUKAN berarti server Anda sedang diretas 
     900 kali secara aktif!
   - Dalam sistem Linux, taktik ini terpicu setiap kali ada eksekusi berkas atau 
     perintah dengan hak akses `sudo`, `su`, perubahan izin file (`chmod`, `chown`), 
     eksekusi skrip otomasi cron job berkala yang berjalan sebagai `root`, atau 
     perubahan atribut file.
   - Korelasi Angka: Perhatikan bahwa Defense Evasion (985) dan Privilege Escalation (984) 
     hampir identik. Ini biasanya menandakan ada skrip otomasi sistem, scheduled task, 
     atau monitoring agent pihak ketiga yang mengeksekusi perintah sudo berulang kali 
     tiap beberapa menit (misal skrip health-check AWS SSM, CloudWatch agent, atau cron).

2. Initial Access (499 Events) & Persistence (499 Events):
   - Pasangan angka identik (499) menunjukkan log autentikasi SSH atau pembuatan sesi login.
   - Setiap sesi SSH baru yang berhasil diverifikasi memicu tagging MITRE:
     * Initial Access (T1078 - Valid Accounts)
     * Persistence (T1078 - Akun dipertahankan untuk akses selanjutnya)
   - Jika 499 login terjadi dalam 24 jam (~20 login per jam), pastikan apakah ini 
     berasal dari developer/admin yang login, atau koneksi API/pipeline CI-CD.

3. Lateral Movement (6 Events):
   - Taktik ini terpicu ketika host melakukan koneksi keluar (outbound SSH/SCP/Rsync) 
     ke mesin lain dalam VPC atau menerima koneksi remote shell dari host lain.
   - Angka 6 tergolong rendah dan umumnya merupakan maintenance berkala antar-server.

CARA INVESTIGASI & DRILL-DOWN:
1. Klik pada batang grafik "Defense Evasion". Dashboard akan langsung mengarahkan Anda 
   ke modul Threat Hunting dengan filter:
   `rule.mitre.tactic: "defense-evasion" AND agent.id: "001"`
2. Periksa field `rule.description` dan `data.srcuser` atau `data.dstuser`.
3. Jika berasal dari perintah internal yang sah (misal AWS SSM Agent menjalankan run-command), 
   kejadian tersebut adalah Normal Business Traffic (Bukan serangan).

### 2.2 COMPLIANCE PCI DSS: ANALISIS KODE KONTROL & LOG TRIGGER

Data yang ditampilkan:
- 10.2.5 : 1592 events
- 10.2.2 : 484 events
- 2.2    : 185 events
- 10.2.4 : 109 events
- 2.2.4  : 68 events

ARTI DARI MASING-MASING KODE PERSYARATAN PCI DSS:
1. PCI DSS 10.2.5 (1592 Events):
   - Definisi: "Verifikasi penggunaan mekanisme identifikasi dan otentikasi" (Authentication 
     mechanisms, valid/invalid password entries, token validation).
   - Penyebab: Log dari SSH, PAM (Pluggable Authentication Modules), sudo authentication 
     yang mencatat keberhasilan atau kegagalan input kredensial.

2. PCI DSS 10.2.2 (484 Events):
   - Definisi: "Verifikasi semua tindakan yang dilakukan oleh pengguna dengan hak istimewa 
     root atau administratif".
   - Penyebab: Setiap kali user menjalankan `sudo`, beralih ke user root (`su -`), atau 
     perintah command-line yang dieksekusi dengan EUID=0.

3. PCI DSS 2.2 (185 Events):
   - Definisi: "Terapkan standar konfigurasi sistem untuk semua komponen sistem" 
     (System hardening, disabling insecure services/protocols).
   - Penyebab: Terpicu oleh rule audit konfigurasi dasar atau modul SCA yang mencatat 
     status konfigurasi daemon di Amazon Linux 2.

4. PCI DSS 10.2.4 (109 Events):
   - Definisi: "Verifikasi upaya akses logis yang tidak valid (Invalid logical access attempts)".
   - Penyebab: Log autentikasi yang gagal (misal salah ketik password SSH, user tidak 
     ditemukan, login rejected).
   - Tindakan: Investigasi 109 event ini! Cek apakah ada brute-force dari IP luar atau 
     hanya human error dari staf internal.

5. PCI DSS 2.2.4 (68 Events):
   - Definisi: "Konfigurasikan parameter keamanan sistem untuk mencegah penyalahgunaan".
   - Penyebab: Catatan audit terkait permission file penting (/etc/passwd, /etc/shadow, 
     kernel sysctl parameters).

### 2.3 FIM (FILE INTEGRITY MONITORING): STATUS "NO RECENT EVENTS" & CARA UJI

Widget menampilkan: "No recent events"
Artinya: Dalam kurun waktu 24 jam terakhir, tidak ada berkas yang dimonitor oleh 
Syscheck mengalami perubahan (tambah, modifikasi, atau hapus).

MENGAPA KOSONG?
1. Sistem stabil: Server Linux produksi yang tenang memang jarang mengalami perubahan berkas 
   pada direktori sistem penting (`/bin`, `/sbin`, `/etc`, `/usr/bin`).
2. Scan Interval belum terpicu: Syscheck secara default berjalan tiap 12 jam sekali (bukan 
   realtime untuk semua folder).
3. Direktori kustom aplikasi belum ditambahkan ke konfigurasi.

CARA PENGUJIAN FIM (VERIFIKASI INTEGRITAS ENGINE):
Untuk memastikan modul FIM bekerja normal, jalankan perintah ini via SSH di server `hrptrsapprd`:
```bash
# Buat file tes di direktori yang dipantau secara default (/etc)
sudo touch /etc/test_wazuh_fim.txt
sudo echo "Test alert FIM" > /etc/test_wazuh_fim.txt

# Paksa Wazuh Agent menjalankan FIM syscheck scan seketika:
sudo /var/ossec/bin/agent_control -r -a
```
Tunggu 10-30 detik, lalu refresh Dashboard. Widget FIM akan langsung menampilkan event baru:
- Path: `/etc/test_wazuh_fim.txt`
- Action: `added`
- Rule description: `File added to the system.`
- Rule ID: `554`

### 2.4 EVENTS COUNT EVOLUTION: MEMBACA POLA & SPIKE TIMESTAMP

Grafik timeline ini memplot volume log per 30 menit (dari pukul 18:00 hingga 15:00):
- Pola Rata (Baseline): Volume log stabil antara 50 - 150 events per 30 menit menandakan 
  aktivitas sistem yang wajar.
- Pola Lonjakan (Spike): Jika tiba-tiba grafik melonjak tajam ke angka 1.000+ pada jam 
```text
tertentu:
```

  * Jika terjadi jam 03:00 / 04:00 subuh: Biasanya korelasi dengan jadwal cron job backup, 
    logrotate harian, atau scanning SCA berkala.
  * Jika terjadi di jam kerja secara acak: Segera filter timestamp tersebut di menu 
    Threat Hunting untuk melihat apakah sedang terjadi insiden denial-of-service, 
    brute-force login, atau restart service.

### 2.5 SCA (SECURITY CONFIGURATION ASSESSMENT): CIS BENCHMARK & ANALISIS SKOR 40%

Data pada widget:
- Policy: CIS Amazon Linux 2 Benchmark v2.0.0 (cis_amazon_linux_2)
- End scan: Sep 9, 2026 @ 04:22:29.000
- Passed: 73
- Failed: 108
- Not applicable: 2
- Score: 40%

ANALISIS KRITIS KEAMANAN:
- Skor 40% adalah skor kepatuhan (hardening) yang RENDAH untuk server target produksi.
- Artinya: Dari seluruh standar keamanan Center for Internet Security (CIS) untuk 
  Amazon Linux 2, server Anda baru memenuhi 73 aturan, sementara 108 aturan keamanan 
  dinyatakan GAGAL (Failed).
- Implikasi: Server memiliki celah konfigurasi sistem default yang belum dikeraskan 
  (unhardened baseline), seperti konfigurasi SSH masih terlalu longgar, parameter 
  kernel sysctl belum diproteksi dari spoofing/redirect, hak akses file sistem terlalu 
  terbuka, atau auditd belum diaktifkan secara maksimal.

CARA MENGGUNAKAN DETAIL SCA DI DASHBOARD:
1. Klik pada tulisan "CIS Amazon Linux 2 Benchmark v2.0.0".
2. Dashboard akan membuka daftar lengkap dari 108 item yang gagal.
3. Klik salah satu item yang Failed. Anda akan melihat:
   - Title: Contoh "Ensure permissions on /etc/shadow are configured".
   - Rationale: Alasan keamanan mengapa aturan ini diwajibkan.
   - Remediation: Perintah shell langsung yang harus dijalankan untuk memperbaikinya.
   - Compliance: Pemetaan ke standar industri (PCI DSS, HIPAA, NIST).

## 3. PANDUAN CARA PENGGUNAAN MODUL-MODUL WAZUH DASHBOARD

Berikut panduan langkah-demi-langkah cara navigasi, membaca, dan menggunakan seluruh 
modul yang tercantum pada menu navigasi Wazuh:

### 3.1 ENDPOINT SECURITY

#### A. CONFIGURATION ASSESSMENT (SCA)

   - Fungsi Utama:
     Audit kepatuhan baseline hardening OS berdasarkan standar Center for Internet 
     Security (CIS Benchmark). File policy benchmark SCA berformat YAML dan tersimpan di 
     agent pada folder `/var/ossec/ruleset/sca/`.
   - Cara Menggunakan di Dashboard:
     1. Buka: Endpoint Security ──> Configuration Assessment.
     2. Pilih Agent: Klik nama host `hrptrsapprd`.
     3. Tinjau Ringkasan: Anda akan melihat Score (40%), Total Checks (183), Passed (73), 
        Failed (108).
     4. Filter Temuan: Klik tab "Failed".
     5. Buka Detail Check: Klik salah satu judul temuan (misal "Ensure SSH root login 
        is disabled").
     6. Periksa Kolom:
        * Description: Apa konfigurasi yang diuji.
        * Rationale: Risiko jika tidak diterapkan.
        * Remediation: Perintah bash pasti untuk menyelesaikan temuan tersebut.
     7. Ekspor Laporan: Klik tombol "Formatted" / "CSV" di pojok kanan atas untuk 
        unduh bukti audit kepatuhan.

#### B. MALWARE DETECTION (Rootcheck & Integrasi YARA)

   - Fungsi Utama:
     Mendeteksi rootkit (hidden process, hidden port, trojaned system binary seperti ls, 
     ps, netstat palsu), file abnormal, serta integrasi YARA scanning engine.
   - Cara Menggunakan di Dashboard:
     1. Buka: Endpoint Security ──> Malware Detection.
     2. Panel "Events": Menampilkan file-file yang dicurigai sebagai anomaly atau 
        rootkit signature.
     3. Panel "Controls": Menampilkan pemeriksaan integritas sistem berkala:
        * Check for hidden processes (deteksi PID yang disembunyikan oleh kernel rootkit).
        * Check for hidden ports (deteksi backdoor listening port).
        * Check /dev anomalies (deteksi device file ilegal).
     4. Jika muncul event, periksa path file dan rule level-nya. Jika level 7+, 
        lakukan analisa file forensik atau isolasi host.

#### C. FILE INTEGRITY MONITORING (FIM / Syscheck)

   - Fungsi Utama:
     Mendeteksi modifikasi, pembuatan, dan penghapusan berkas penting sistem atau berkas 
     aplikasi web/database secara real-time atau terjadwal.
   - Cara Mengonfigurasi Direktori Baru (di ossec.conf):
     ```xml
     <syscheck>
       <directories check_all="yes" realtime="yes" report_changes="yes">/etc,/var/www,/opt/app</directories>
       <ignore>/etc/mtab</ignore>
     </syscheck>
     ```
   - Cara Menggunakan di Dashboard:
     1. Buka: Endpoint Security ──> File Integrity Monitoring.
     2. Tab "Inventory": Cari berkas tertentu (misal `/etc/passwd`). Anda dapat melihat 
        ukuran file, owner, permissions, serta hash MD5, SHA1, dan SHA256.
     3. Tab "Events": Menampilkan riwayat perubahan:
        * Action: `added`, `modified`, atau `deleted`.
        * Who-data: Menampilkan user (misal `ec2-user`), Process ID (PID), dan nama 
          biner yang mengubah file (misal `vim` atau `nano`).
        * Diff: Menampilkan potongan baris teks yang dihapus vs baris yang ditambahkan.

### 3.2 THREAT INTELLIGENCE

#### A. THREAT HUNTING (SIEM Discover)

   - Fungsi Utama:
     Pencarian dan penyelidikan log mendalam menggunakan bahasa query KQL (Kibana Query 
     Language) atau Lucene. Di sinilah Security Analyst menghabiskan sebagian besar waktunya.
   - Cara Menggunakan di Dashboard:
     1. Buka: Threat Intelligence ──> Threat Hunting.
     2. Tentukan Time Range di pojok kanan atas (misal: "Last 24 hours" atau rentang kustom).
     3. Gunakan Bar Pencarian (Search Bar).
     4. Cheat Sheet Query Populer:
        * Mencari semua alert dengan severity tinggi:
          `rule.level: >= 10`
        * Mencari aktivitas user tertentu:
          `data.srcuser: "root" or data.dstuser: "root"`
        * Mencari kegagalan autentikasi SSH:
          `rule.groups: "authentication_failed" and data.srcip: *`
        * Mencari event FIM pada direktori tertentu:
          `syscheck.path: "/etc/*"`
        * Mencari eksekusi perintah sudo berbahaya:
          `rule.id: 5402 and full_log: "*userdel*"`
     5. Menambahkan Kolom Tabel: Pada sidebar kiri ("Available fields"), klik tanda "+" 
        pada field: `agent.name`, `rule.description`, `rule.level`, `data.srcip` agar 
        tampilan tabel menjadi rapi dan mudah dianalisa.

#### B. VULNERABILITY DETECTION (Deteksi Kerentanan CVE)

   - Fungsi Utama:
     Mendeteksi kerentanan CVE pada paket RPM/DEB yang terpasang di sistem target 
     tanpa memerlukan active network port scanning. Wazuh Manager mencocokkan daftar 
     paket Syscollector dengan database NVD, Red Hat OVAL, dan Amazon Linux Security Advisories.
   - Cara Menggunakan di Dashboard:
     1. Buka: Threat Intelligence ──> Vulnerability Detection.
     2. Filter Agent: Pastikan memilih `hrptrsapprd`.
     3. Dashboard menampilkan grafik donat: Severity (Critical, High, Medium, Low).
     4. Tab "Vulnerabilities":
        * CVE ID: Contoh `CVE-2023-38408`.
        * Package: Nama paket yang vulnerable (misal `openssh-server-7.4p1`).
        * Severity: Indikator tingkat bahaya (Critical / High).
        * CVSS v3 Score: Skor angka keparahan (misal 9.8).
        * Condition: Versi paket yang harus diinstall untuk memperbaiki celah (misal: 
          `Package version is less than 8.7p1`).
     5. Tindakan Remediasi: Jalankan update paket di server via `yum update <package>` 
        atau reboot jika melibatkan kernel patch.

#### C. MITRE ATT&CK MATRIX & MAPPING

   - Fungsi Utama:
     Menyajikan peta visual taktik dan teknik penyerangan siber berdasarkan kerangka 
     kerja global MITRE ATT&CK.
   - Cara Menggunakan di Dashboard:
     1. Buka: Threat Intelligence ──> MITRE ATT&CK.
     2. Matriks ATT&CK: Anda akan melihat 14 kolom taktik (Initial Access, Execution, 
        Persistence, Privilege Escalation, Defense Evasion, Credential Access, dll).
     3. Kotak Berwarna (Highlighted): Menunjukkan teknik yang aktif terdeteksi di infrastruktur 
        Anda dalam rentang waktu yang dipilih.
     4. Klik pada salah satu Teknik (contoh: "T1078 - Valid Accounts" atau "T1059 - Command 
        and Scripting Interpreter"):
        * Muncul pop-up deskripsi teknik dari database MITRE resmi.
        * Klik "Explore events" untuk melihat log spesifik yang memicu teknik tersebut.
     5. Sangat berguna untuk reporting ke manajemen C-Level atau CISO dalam mengevaluasi 
        postur pertahanan siber.

#### D. VIRUSTOTAL INTEGRATION

   - Fungsi Utama:
     Mengintegrasikan hash file yang terdeteksi oleh FIM ke VirusTotal API v3 untuk 
     memeriksa reputasi malware di lebih dari 70 engine antivirus.
   - Cara Konfigurasi di Wazuh Manager (`/var/ossec/etc/ossec.conf`):
     ```xml
```xml
<ossec_config>
  <integration>
    <name>virustotal</name>
    <api_key>API_KEY_VIRUSTOTAL_ANDA</api_key>
    <group>syscheck</group>
    <alert_format>json</alert_format>
  </integration>
</ossec_config>
```
```

   - Cara Menggunakan di Dashboard:
     1. Buka: Threat Intelligence ──> VirusTotal.
     2. Tab "Events": Menampilkan setiap file yang diperiksa reputasinya.
     3. Indikator Kritis:
        * Positive Engines Count: Berapa banyak vendor antivirus menandai file sebagai malware 
          (misal: 58/72).
        * Permalink: Link langsung ke hasil analisis web VirusTotal.
        * Malware Family: Nama varian malware (misal: Mirai, CobaltStrike, Kinsing).

### 3.3 SECURITY OPERATIONS & REGULATORY COMPLIANCE

Modul ini mengelompokkan log kejadian keamanan ke dalam klausa regulasi standar industri:

#### A. PCI DSS (Payment Card Industry Data Security Standard)

   - Digunakan oleh: Perusahaan perbankan, fintech, e-commerce, payment gateway.
   - Cara Menggunakan di Dashboard:
     1. Buka: Security Operations ──> PCI DSS.
     2. Filter Requirement:
        * Requirement 10 (Melacak dan memantau semua akses ke sumber daya jaringan & data kartu).
        * Requirement 11 (Uji keamanan sistem berkala & FIM file integritas).
        * Requirement 2 (Jangan gunakan nilai default vendor untuk kata sandi & parameter sistem).
     3. Periksa panel "Top Agents" dan "Top Rules" untuk melihat komponen sistem mana yang 
        paling banyak memicu log kepatuhan.

#### B. GDPR (General Data Protection Regulation)

   - Digunakan oleh: Organisasi yang memproses data pribadi warga Uni Eropa.
   - Cara Menggunakan di Dashboard:
     1. Buka: Security Operations ──> GDPR.
     2. Fokus pada:
        * Article 32 (Keamanan pemrosesan data, enkripsi, integritas sistem).
        * Article 33 (Notifikasi pelanggaran data dalam 72 jam).
     3. Pantau apakah ada akses unauthorized ke database pelanggan (MySQL/PostgreSQL) 
        atau ekspor data yang tidak wajar.

#### C. HIPAA (Health Insurance Portability and Accountability Act)

   - Digunakan oleh: Rumah sakit, klinik kesehatan, pengelola rekam medis elektronik.
   - Cara Menggunakan di Dashboard:
     1. Buka: Security Operations ──> HIPAA.
     2. Fokus pada kontrol teknis:
        * 164.312(a)(1): Kontrol akses sistem kesehatan.
        * 164.312(b): Kontrol audit dan review berkala.
        * 164.312(c)(1): Integritas data ePHI dari perusakan tanpa izin.

#### D. NIST 800-53 (Security and Privacy Controls for Information Systems)

   - Digunakan oleh: Instansi pemerintah, BUMN, organisasi enterprise dengan standar ketat.
   - Cara Menggunakan di Dashboard:
     1. Buka: Security Operations ──> NIST 800-53.
     2. Tinjau kategori kontrol:
        * AC (Access Control)
        * AU (Audit and Accountability)
        * SI (System and Information Integrity)
        * CM (Configuration Management)

#### E. TSC (Trust Services Criteria / SOC 2 Type II)

   - Digunakan oleh: Penyedia layanan cloud B2B / SaaS untuk membuktikan kontrol keamanan 
     ke klien enterprise.
   - Cara Menggunakan di Dashboard:
     1. Buka: Security Operations ──> TSC.
     2. Pantau kriteria Common Criteria (CC):
        * CC6.1 - CC6.8: Kontrol akses logis dan proteksi perimeter.
        * CC7.1 - CC7.4: Monitoring operasional sistem, anomali, dan respon insiden.

### 3.4 CLOUD SECURITY

Wazuh menghubungkan log cloud native langsung ke dalam SIEM:

#### A. DOCKER MONITORING

   - Cara Kerja:
     Wazuh Agent membaca log socket `/var/run/docker.sock` menggunakan modul docker-listener.
   - Aktivasi di `ossec.conf` Agent:
     ```xml
     <wodle name="docker-listener">
       <interval>10m</interval>
       <attempts>5</attempts>
       <run_on_start>yes</run_on_start>
       <disabled>no</disabled>
     </wodle>
     ```
   - Cara Menggunakan di Dashboard:
     1. Buka: Cloud Security ──> Docker.
     2. Tinjau event: Container start, stop, pause, kill, top.
     3. Deteksi ancaman: Kontainer yang dijalankan dengan mode `--privileged` atau 
        volume mount berbahaya ke root host (`-v /:/host`).

#### B. AMAZON WEB SERVICES (AWS INTEGRATION)

   - Cara Kerja:
     Wazuh Manager menggunakan wodle `aws-s3` untuk menarik log dari bucket S3 AWS.
   - Layanan AWS yang Didukung:
     * AWS CloudTrail (audit seluruh API call IAM, EC2, S3, RDS).
     * AWS GuardDuty (temuan threat intel berbasis machine learning AWS).
     * AWS VPC Flow Logs (lalu lintas paket jaringan IP VPC).
     * AWS Macie, AWS Inspector, AWS WAF.
   - Konfigurasi di Wazuh Manager (`ossec.conf`):
     ```xml
     <wodle name="aws-s3">
       <disabled>no</disabled>
       <interval>10m</interval>
       <run_on_start>yes</run_on_start>
       <service type="cloudtrail">
         <aws_profile>default</aws_profile>
         <bucket>nama-bucket-cloudtrail-anda</bucket>
       </service>
       <service type="guardduty">
         <aws_profile>default</aws_profile>
         <bucket>nama-bucket-guardduty-anda</bucket>
       </service>
     </wodle>
     ```
   - Cara Menggunakan di Dashboard:
     1. Buka: Cloud Security ──> Amazon Web Services.
     2. Filter berdasarkan Region AWS (misal `ap-southeast-1` Jakarta atau `ap-southeast-3`).
     3. Pantau: Siapa yang mengubah Security Group, siapa yang menghapus snapshot, 
        atau siapa yang login sebagai Root AWS Account.

#### C. GOOGLE CLOUD PLATFORM (GCP)

   - Cara Kerja:
     Menarik log via Google Cloud Pub/Sub topic menggunakan GCP Service Account credential JSON.
   - Cara Menggunakan di Dashboard:
     1. Buka: Cloud Security ──> Google Cloud.
     2. Memantau GCP Audit Logs, admin activity, compute engine status, dan firewall changes.

#### D. GITHUB AUDIT LOGS

   - Cara Kerja:
     Mengintegrasikan log audit organisasi GitHub (Enterprise/Team) via GitHub Webhook 
     atau REST API.
   - Cara Menggunakan di Dashboard:
     1. Buka: Cloud Security ──> GitHub.
     2. Memantau: Penambahan anggota organisasi baru, penghapusan repositori, 
        perubahan branch protection rule, repositori privat diubah menjadi publik, 
        dan potensi kebocoran personal access token.

#### E. OFFICE 365 (MICROSOFT 365)

   - Cara Kerja:
     Menghubungkan Microsoft Office 365 Management Activity API (Azure AD / Entra ID).
   - Cara Menggunakan di Dashboard:
     1. Buka: Cloud Security ──> Office 365.
     2. Pantau insiden kritis:
        * Impossible Travel: Akun login dari Jakarta lalu 10 menit kemudian login dari Rusia.
        * Perubahan role Global Admin tanpa otorisasi.
        * Pembuatan inbox forwarding rule mencurigakan (tanda BEC - Business Email Compromise).
        * Pengunduhan massal berkas dari OneDrive / SharePoint.

## 4. PANDUAN PRAKTIS REMEDIASI SKOR SCA 40% PADA AMAZON LINUX 2

Berikut panduan langkah-demi-langkah perbaikan teknis di server `hrptrsapprd` (172.1.12.18) 
untuk menaikkan skor CIS Benchmark dari 40% menuju 85%+:

### 4.1 AUDIT & HARDENING SSH DAEMON (/etc/ssh/sshd_config)

Buka file `/etc/ssh/sshd_config` menggunakan editor teks:
```bash
sudo vi /etc/ssh/sshd_config
```
Tambahkan atau sesuaikan nilai parameter berikut:
```ini
# Batasi percobaan password gagal
MaxAuthTries 4

# Matikan X11 forwarding pada server tanpa GUI
X11Forwarding no

# Matikan login root langsung menggunakan password
PermitRootLogin prohibit-password

# Gunakan sandi cipher modern (hapus 3DES / RC4)
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Otomatis putus sesi idle mengambang setelah 15 menit
ClientAliveInterval 300
ClientAliveCountMax 3

# Matikan autentikasi berbasis rhosts
IgnoreRhosts yes
HostbasedAuthentication no
PermitEmptyPasswords no
```
Uji sintaks dan restart layanan SSH:
```bash
sudo sshd -t && sudo systemctl restart sshd
```

### 4.2 AUDIT PASSWORD HASHING & HAK AKSES BERKAS OTENTIKASI

Pastikan berkas kredensial sistem terlindungi dengan hak akses yang ketat:
```bash
# Set ownership ke root:root
sudo chown root:root /etc/passwd /etc/shadow /etc/gshadow /etc/group

# Set permission sesuai standar CIS
sudo chmod 644 /etc/passwd
sudo chmod 000 /etc/shadow
sudo chmod 000 /etc/gshadow
sudo chmod 644 /etc/group
```

### 4.3 AUDIT & HARDENING KERNEL PARAMETER (/etc/sysctl.d/99-cis.conf)

Buat berkas konfigurasi sysctl khusus hardening jaringan:
```bash
sudo vi /etc/sysctl.d/99-cis.conf
```
Isi konfigurasi berikut:
```ini
# Cegah paket IP Forwarding (kecuali server NAT/Router)
net.ipv4.ip_forward = 0

# Matikan ICMP Redirects (mencegah manipulasi tabel routing)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Proteksi terhadap serangan SYN Flood
net.ipv4.tcp_syncookies = 1

# Proteksi IP Spoofing (Reverse Path Filtering)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Abaikan ping broadcast
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Aktifkan perlindungan memori Address Space Layout Randomization (ASLR)
kernel.randomize_va_space = 2

# Batasi dmesg hanya untuk user root
kernel.dmesg_restrict = 1
```

Terapkan konfigurasi seketika tanpa perlu reboot:
```bash
sudo sysctl --system
```

### 4.4 AUDIT LAYANAN TIDAK TERPAKAI & CORE DUMPS

Nonaktifkan layanan lawas yang tidak dibutuhkan:
```bash
sudo systemctl stop rpcbind 2>/dev/null || true
sudo systemctl disable rpcbind 2>/dev/null || true

# Matikan fasilitas pembuatan core dump agar kredensial tidak tersimpan di disk jika proses crash
echo "* hard core 0" | sudo tee -a /etc/security/limits.conf
sudo sysctl -w fs.suid_dumpable=0
```

### 4.5 AUDIT SISTEM LOGGING AUDITD (/etc/audit/rules.d/audit.rules)

CIS Amazon Linux 2 mewajibkan pencatatan seluruh perubahan waktu sistem dan akun:
Tambahkan ke `/etc/audit/rules.d/audit.rules`:
```ini
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope
```

Muat ulang konfigurasi auditd:
```bash
sudo augenrules --load
```

Setelah langkah perbaikan di atas selesai dieksekusi, paksa scan ulang SCA dengan 
merestart agent:
```bash
sudo systemctl restart wazuh-agent
```
Dalam waktu 2-5 menit, refresh Wazuh Dashboard Anda. Skor SCA akan melonjak naik 
menjadi di atas 80% dan status 108 item Failed akan berkurang drastis.

## 5. STANDARD OPERATING PROCEDURE (SOP) HARIAN & INVESTIGASI INSIDEN

### 5.1 DAILY SOC/ADMIN ROUTINE CHECKLIST (10 MENIT RUTINITAS HARIAN)

1. Buka Wazuh Home ──> Endpoints:
   - Pastikan agent `hrptrsapprd` berstatus `active` (hijau).
   - Pastikan parameter `Last keep alive` tidak lebih dari 5 menit yang lalu.
2. Buka Threat Intelligence ──> Threat Hunting:
   - Pasang filter waktu: `Last 24 hours`.
   - Pasang query filter: `rule.level: >= 10`.
   - Evaluasi apakah ada notifikasi critical (eksekusi malware, brute-force masif).
3. Buka Threat Intelligence ──> Vulnerability Detection:
   - Cek apakah muncul CVE Critical baru yang membutuhkan patch segera.
4. Buka Endpoint Security ──> File Integrity Monitoring:
   - Review berkas yang berstatus `modified` atau `added`. Pastikan perubahannya 
     diketahui oleh tim dev/ops.

### 5.2 ALUR TRIAGE ALERT BERLEVEL TINGGI (LEVEL >= 10)

Jika menemukan alert dengan Rule Level 10 s/d 15:
1. Identifikasi Aktor & Sumber:
   - Cek field `data.srcip`: Apakah IP lokal VPC atau IP publik internet?
   - Cek field `data.srcuser`: User apa yang mengeksekusi aksi tersebut?
2. Korelasikan dengan Jam Kerja & Tiket Perubahan (Change Request):
   - Jika aktivitas dilakukan oleh tim DevOps resmi saat jam maintenance, 
     tutup tiket sebagai `False Positive / Authorized Activity`.
3. Isolasi Host (Jika Terbukti Serangan/Compromised):
   - Jalankan fitur Active Response untuk memutus akses IP penyerang via iptables/firewalld.
   - Atau lepaskan Security Group AWS EC2 instance dari internet dan masukkan ke 
     dalam Security Group "Quarantine" untuk investigasi forensik lebih lanjut.

### 5.3 STRATEGI WHITELIST & PENANGANAN FALSE POSITIVE (local_rules.xml)

Jika widget MITRE ATT&CK Anda terus mencatat 980+ Defense Evasion yang disebabkan oleh 
skrip internal resmi (misalnya cron job backup yang berjalan setiap menit):
- Anda dapat menurunkannya atau mengecualikannya di Wazuh Manager pada file:
  `/var/ossec/etc/rules/local_rules.xml`

Contoh: Membuat rule custom level 0 (ignore) untuk script internal terpercaya:
```xml
<group name="syslog,">
```xml
<rule id="100010" level="0">
  <if_sid>5402</if_sid>
  <match>/opt/scripts/backup.sh</match>
  <description>Ignore safe internal backup cron job from triggering alert</description>
</rule>
```

</group>
```

### 5.4 OTOMASI RESPON KEAMANAN (ACTIVE RESPONSE EXECUTION)

Wazuh dapat merespon serangan secara otomatis tanpa intervensi manual:
1. Blokir IP Otomatis (Drop IP Attacker):
   Jika terjadi 5 kali percobaan SSH gagal berturut-turut dalam 3 menit, IP penyerang 
   dapat diblokir via iptables selama 600 detik (10 menit).
2. Karantina Berkas Berbahaya:
   Jika berkas baru terdeteksi oleh FIM dan diverifikasi berbahaya oleh VirusTotal API, 
   skrip active response memindahkan berkas tersebut ke direktori karantina khusus 
   (`/var/ossec/quarantine/`).

## AKHIR DOKUMEN
