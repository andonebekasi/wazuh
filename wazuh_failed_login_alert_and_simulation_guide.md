# PANDUAN LENGKAP MEMBUAT ALERT GAGAL LOGIN DI WAZUH DASHBOARD - DAN SIMULASI PENGUJIAN KEAMANAN (FAILED LOGIN & BRUTE FORCE)

Dokumen ini merupakan panduan operasional dan implementasi teknis end-to-end 
untuk mendeteksi, membuat alert khusus (custom rule & notifications), membuat 
dashboard visualisasi monitoring gagal login, serta melakukan simulasi serangan 
(brute force & invalid user login) pada infrastruktur yang dimonitor oleh Wazuh SIEM.

## DAFTAR ISI

1.  KONSEP DASAR & ARSITEKTUR DETEKSI LOGIN WAZUH
    1.1 Bagaimana Wazuh Mendeteksi Upaya Login Gagal
    1.2 Sumber Log Otentikasi (Linux /var/log/secure, /var/log/auth.log & Windows)
    1.3 Rule Bawaan Wazuh untuk Failed Login (Rule ID 5503, 5710, 5712, 5716, dll.)
    1.4 Pemetaan Kerangka MITRE ATT&CK (T1110 - Brute Force)

2.  KONFIGURASI AGENT: MEMASTIKAN LOG LOGIN TERKIRIM
    2.1 Verifikasi Tag <localfile> pada Agent (/var/ossec/etc/ossec.conf)
    2.2 Konfigurasi SSH Daemon LogLevel (/etc/ssh/sshd_config)
    2.3 Menjalankan Uji Aliran Log ke Wazuh Manager

3.  MEMBUAT CUSTOM RULE ALERT GAGAL LOGIN (WAZUH MANAGER)
    3.1 Mengapa Memerlukan Custom Rule?
    3.2 Struktur File /var/ossec/etc/rules/local_rules.xml
    3.3 Contoh Rule 1: Eskalasi Level Alert Login Gagal Akun Sensitif (User 'root')
    3.4 Contoh Rule 2: Deteksi Brute Force Cepat (Threshold 3x Gagal dalam 60 Detik)
    3.5 Contoh Rule 3: Deteksi User Enumeration (Satu IP Mencoba Berbagai Username)
    3.6 Contoh Rule 4: Deteksi Gagal Login di Luar Jam Kerja Operasional
    3.7 Validasi Sintaks Rule dengan Utility wazuh-logtest

4.  MEMBUAT DASHBOARD & VISUALISASI MONITORING DI WAZUH DASHBOARD
    4.1 Pencarian Cepat via Modul Threat Hunting / Discover (KQL Query)
    4.2 Menambahkan Field Penting ke Saved View
    4.3 Membuat Visualisasi 1: Metric Total Failed Logins (24 Jam Terakhir)
    4.4 Membuat Visualisasi 2: Data Table Top IP Penyerang (data.srcip)
    4.5 Membuat Visualisasi 3: Pie Chart Username Sasaran Paling Sering Diserang
    4.6 Membuat Visualisasi 4: Histogram / Area Chart Tren Gagal Login per Waktu
    4.7 Menyusun Custom Dashboard "Authentication Failure & Brute Force Monitor"

5.  KONFIGURASI NOTIFIKASI REAL-TIME (EMAIL & WEBHOOK / TELEGRAM / SLACK)
    5.1 Mengaktifkan Alert Email Otomatis di ossec.conf
    5.2 Mengaktifkan Notifikasi via Webhook (Slack / Discord / Telegram)

6.  KONFIGURASI ACTIVE RESPONSE (OTOMATIS BLOKIR IP PENYERANG)
    6.1 Konsep Pertahanan Otomatis Active Response
    6.2 Menghubungkan Rule Gagal Login ke Command firewall-drop
    6.3 Menyetel Durasi Pemblokiran IP (Ban Time) & Whitelist IP Penting

7.  LANGKAH SIMULASI PENGUJIAN LENGKAP (SIMULATION SCENARIOS)
    7.1 Skenario A: Uji Coba Single Failed Login SSH (Password Salah)
    7.2 Skenario B: Uji Coba Login dengan User Fiktif (Non-Existent User)
    7.3 Skenario C: Simulasi Brute Force Otomatis (Bash Loop Script)
    7.4 Skenario D: Simulasi Serangan Khusus Akun Root
    7.5 Skenario E: Simulasi Gagal Login Lokal Mesin (su / sudo)
    7.6 Skenario F: Simulasi Gagal Login Windows Agent (Event ID 4625)

8.  VERIFIKASI & ANALISIS HASIL SIMULASI
    8.1 Memeriksa Alert di Wazuh Dashboard (Events & MITRE ATT&CK)
    8.2 Memeriksa Log Alert di File Sistem Server (/var/ossec/logs/alerts/)
    8.3 Memeriksa Eksekusi Active Response (/var/ossec/logs/active-responses.log)
    8.4 Memeriksa Tabel iptables / firewalld pada Endpoint

9.  PANDUAN TROUBLESHOOTING JIKA ALERT TIDAK MUNCUL
    9.1 Checklist Koneksi & Sinkronisasi Waktu (NTP)
    9.2 Memeriksa Hak Akses Pembacaan Log di Agent
    9.3 Memeriksa archives.log untuk Memastikan Log Mentah Masuk
    9.4 Refresh Index Pattern pada Wazuh Dashboard

## 1. KONSEP DASAR & ARSITEKTUR DETEKSI LOGIN WAZUH

### 1.1 Bagaimana Wazuh Mendeteksi Upaya Login Gagal

```text
1. Setiap kali pengguna mencoba login ke sistem (melalui SSH, Console, RDP, atau 
   sudo/su) dan gagal, sistem operasi mencatat event tersebut ke dalam file log auth.
2. Komponen 'wazuh-agent' membaca baris log baru tersebut secara real-time via modul
   Logcollector.
3. Baris log dienkripsi dan dikirim ke 'wazuh-manager' melalui port UDP/TCP 1514.
4. Di Wazuh Manager, alur pemrosesan berjalan melalui tahapan:
   - Pre-decoding (mengekstrak timestamp, hostname, program_name seperti sshd atau pam).
   - Decoding (mengekstrak data spesifik seperti data.srcip, data.dstuser, data.srcport).
   - Rules Engine (mencocokkan event dengan rule built-in atau custom rule di local_rules.xml).
5. Jika rule terpenuhi dan memiliki level >= 3 (default minimal alert), alert akan:
   - Ditulis ke `/var/ossec/logs/alerts/alerts.json` dan `alerts.log`.
   - Diindeks oleh Filebeat ke OpenSearch / Wazuh Indexer (`wazuh-alerts-4.x-*`).
   - Ditampilkan seketika di Wazuh Dashboard.
   - Memicu Active Response (jika dikonfigurasi) untuk memblokir IP penyerang.

1.2 Sumber Log Otentikasi Berdasarkan Sistem Operasi
```

- Amazon Linux 2 / RHEL / CentOS / AlmaLinux / Rocky Linux:
  `/var/log/secure`
- Ubuntu / Debian:
  `/var/log/auth.log`
- Microsoft Windows:
  Channel Event Viewer: `Security` (Event ID 4625: An account failed to log on)
- Web Application (Nginx / Apache / Tomcat):
  `/var/log/nginx/error.log` (HTTP 401 Unauthorized) atau access log aplikasi.

### 1.3 Rule Bawaan Wazuh (Built-in Rules) Terkait Login Gagal

| Wazuh sudah memiliki rule bawaan di `/var/ossec/ruleset/rules/` yang otomatis |  |  |
| :--- | :--- | :--- |
| mendeteksi berbagai tipe login gagal: |  |  |
| Rule ID | Level | Deskripsi Rule Bawaan |
| 5503 | 5 | PAM: User login failed. |
| 5504 | 5 | PAM: Maximum authentication attempts exceeded. |
| 5710 | 5 | sshd: Attempt to login using a non-existent user. |
| 5716 | 5 | sshd: authentication failed. |
| 5711 | 5 | sshd: authentication failed (format alternatif). |
| 5712 | 10 | sshd: brute force trying to get access to the system. |
| 5720 | 10 | sshd: Multiple failed logins in a small period of time. |
| 5760 | 5 | sshd: Failed password for root. |
| 18152 | 5 | Windows: Logon Failure - Unknown user name or bad password. |
| 60122 | 5 | Windows: Logon Failure - Substatus Bad Password. |
| Catatan: |  |  |
| Rule bawaan ini berada di grup rule: `authentication_failed`, `sshd`, `syslog`, `pam`. |  |  |
| 1.4 Pemetaan Kerangka MITRE ATT&CK |  |  |

Alert gagal login di Wazuh secara otomatis terpetakan ke:
- Tactic: Credential Access (TA0006)
- Technique: Brute Force (T1110)
  * T1110.001 - Password Guessing
  * T1110.003 - Password Spraying

## 2. KONFIGURASI AGENT: MEMASTIKAN LOG LOGIN TERKIRIM

Sebelum melakukan simulasi, pastikan Wazuh Agent pada endpoint target (target host)
sudah dikonfigurasi untuk membaca file log otentikasi.

### 2.1 Verifikasi Konfigurasi di Agent (/var/ossec/etc/ossec.conf)

```xml
Buka file konfigurasi agent:
$ sudo nano /var/ossec/etc/ossec.conf

Pastikan terdapat blok `<localfile>` berikut:

Untuk Amazon Linux 2 / RHEL / CentOS:
```

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/secure</location>
</localfile>
```

Untuk Ubuntu / Debian:
```xml
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/auth.log</location>
  </localfile>

Untuk Microsoft Windows:
```

```xml
<localfile>
  <location>Security</location>
  <log_format>eventchannel</log_format>
  <query>Event/System[EventID=4625]</query>
</localfile>
```

Jika Anda baru saja menambahkan konfigurasi di atas, restart Wazuh Agent:
$ sudo systemctl restart wazuh-agent

### 2.2 Konfigurasi SSH Daemon LogLevel (/etc/ssh/sshd_config)

---

Pastikan SSH server pada endpoint mencatat upaya login dengan detail:
1. Buka file sshd_config:
```bash
$ sudo nano /etc/ssh/sshd_config
```

2. Pastikan parameter berikut aktif (uncommented):
   LogLevel INFO
3. Jika ingin mencatat fingerprint SSH key yang gagal secara detail:
   LogLevel VERBOSE
4. Reload service SSH:
```bash
$ sudo systemctl reload sshd
```

## 3. MEMBUAT CUSTOM RULE ALERT GAGAL LOGIN (WAZUH MANAGER)

### 3.1 Mengapa Memerlukan Custom Rule?

```text
Meskipun Wazuh memiliki rule bawaan (level 5), dalam lingkungan produksi tim SOC
dan Administrator sering kali membutuhkan:
1. Escalation Level: Menaikkan severity menjadi level 10 atau 12 jika login gagal
   menargetkan akun superuser seperti 'root' atau 'administrator'.
2. Custom Threshold: Mendeteksi brute force lebih ketat (misal 3 kali gagal dalam
   60 detik) daripada batas bawaan Wazuh (default rule 5712 membutuhkan 8 kali).
3. Notifikasi Cepat: Level >= 10 otomatis memicu pengiriman email atau webhook jika
   opsi email_alert_level disetel ke level 10.
4. Jam Operasional: Memicu alert kritis jika ada login gagal di tengah malam / libur.

3.2 Struktur File /var/ossec/etc/rules/local_rules.xml
```

Semua custom rules WAJIB ditulis pada file `/var/ossec/etc/rules/local_rules.xml` 
di server Wazuh Manager. JANGAN mengubah file di `/var/ossec/ruleset/rules/` karena 
akan tertimpa saat update Wazuh.

Rentang ID untuk custom rule yang disarankan adalah: 100000 s/d 120000.

Buka file custom rule di Wazuh Manager:
$ sudo nano /var/ossec/etc/rules/local_rules.xml

Tambahkan blok-blok rule berikut di dalam tag `<group name="local,syslog,sshd,">`:

### 3.3 Contoh Rule 1: Eskalasi Alert Gagal Login Akun Root (Level 10)

```xml
Rule ini memicu alert level 10 jika ada percobaan login SSH gagal untuk user 'root':

  <!-- Deteksi spesifik upaya gagal login ke user root via SSH -->
  <rule id="100010" level="10">
    <if_sid>5716, 5710, 5503</if_sid>
    <match>root</match>
    <description>PERINGATAN: Upaya gagal login langsung ke akun root terdeteksi dari $(srcip)!</description>
    <mitre>
      <id>T1110</id>
      <id>T1078</id>
    </mitre>
    <group>authentication_failed,pci_dss_10.2.4,pci_dss_10.2.5,gpg13_7.1,</group>
  </rule>

3.4 Contoh Rule 2: Deteksi Brute Force Cepat (3x Gagal dalam 60 Detik)
```

Rule ini mendeteksi upaya brute force yang lebih agresif (3 kali gagal dari IP yang
sama dalam jangka waktu 60 detik) dan memberikan level 12 (Critical):

  <!-- Deteksi brute force cepat: 3 kegagalan dalam 60 detik -->
```xml
<rule id="100011" level="12" frequency="3" timeframe="60">
  <if_matched_sid>5716</if_matched_sid>
  <same_source_ip />
  <description>KRITIS: Terdeteksi Brute Force SSH Agresif (3x gagal dalam 60 detik) dari IP $(srcip)!</description>
  <mitre>
    <id>T1110.001</id>
  </mitre>
  <group>authentication_failures,attack,pci_dss_11.4,</group>
</rule>
```

### 3.5 Contoh Rule 3: Deteksi User Enumeration (Mencoba Banyak Username dari 1 IP)

```xml
Rule ini mendeteksi jika satu IP mencoba login menggunakan beberapa nama user yang
tidak terdaftar di sistem (serangan dictionary attack / user discovery):

  <!-- Deteksi dictionary attack / invalid user scanning -->
  <rule id="100012" level="11" frequency="4" timeframe="90">
    <if_matched_sid>5710</if_matched_sid>
    <same_source_ip />
    <description>PERINGATAN: Terdeteksi User Enumeration / Dictionary Attack dari IP $(srcip) menggunakan username fiktif!</description>
    <mitre>
      <id>T1110.003</id>
      <id>T1087</id>
    </mitre>
    <group>authentication_failures,recon,</group>
  </rule>

3.6 Contoh Rule 4: Deteksi Gagal Login di Luar Jam Kerja (Off-Hours)
```

Rule ini memicu alert level 10 jika ada kegagalan otentikasi antara jam 21:00 malam 
hingga 06:00 pagi:

  <!-- Deteksi gagal login di luar jam operasional (21:00 - 06:00) -->
```xml
<rule id="100013" level="10">
  <if_sid>5716, 5710</if_sid>
  <time>9 pm - 6 am</time>
  <description>ANOMALI: Percobaan login gagal di luar jam operasional (malam hari) untuk user $(dstuser) dari IP $(srcip)</description>
  <group>authentication_failed,anomalous_behavior,</group>
</rule>
```

### 3.7 Validasi Sintaks Rule dengan Utility wazuh-logtest

```bash
Sebelum me-restart service Wazuh Manager, SELALU uji rule Anda menggunakan utility
`wazuh-logtest` untuk memastikan tidak ada kesalahan sintaks XML atau decoding.

Jalankan wazuh-logtest di server Wazuh Manager:
$ sudo /var/ossec/bin/wazuh-logtest

Masukkan contoh baris log gagal login SSH standar (paste lalu tekan ENTER):
May 10 14:22:01 server-app sshd[12345]: Failed password for invalid user admin from 192.168.10.55 port 44322 ssh2

Output yang diharapkan:
```

**Phase 1: Completed pre-decoding.
       full event: 'May 10 14:22:01 server-app sshd[12345]: Failed password for invalid user admin from 192.168.10.55 port 44322 ssh2'
```text
timestamp: 'May 10 14:22:01'
hostname: 'server-app'
program_name: 'sshd'
```

**Phase 2: Completed decoding.
```text
name: 'sshd'
parent: 'sshd'
dstuser: 'admin'
srcip: '192.168.10.55'
srcport: '44322'
```

**Phase 3: Completed filtering (rules).
```text
id: '5710'
level: '5'
description: 'sshd: Attempt to login using a non-existent user'
groups: '['syslog', 'sshd', 'invalid_login', 'authentication_failed']'
firedtimes: '1'
```

Jika output menampilkan Phase 3 dengan benar (rule matched), tekan Ctrl + C untuk keluar.
Kemudian restart Wazuh Manager agar rule baru aktif:
$ sudo systemctl restart wazuh-manager

## 4. MEMBUAT DASHBOARD & VISUALISASI MONITORING DI WAZUH DASHBOARD

Wazuh Dashboard memiliki visualisasi bawaan, namun Anda dapat membuat filter 
pencarian khusus serta dashboard visual interaktif untuk memonitor serangan 
gagal login secara terpusat.

### 4.1 Pencarian Cepat via Modul Threat Hunting / Discover

```text
1. Buka browser dan login ke Wazuh Dashboard: `https://<ip_wazuh_dashboard>`.
2. Klik ikon menu utama (garis tiga di kiri atas / Hamburger Menu).
3. Pilih menu:
   Threat Intelligence -> Threat Hunting
   (atau klik modul 'Security Events' -> tab 'Events').
4. Pada kolom Search Bar (KQL - Kibana Query Language), masukkan salah satu query berikut:

   Query untuk semua event login gagal:
   rule.groups: "authentication_failed"

   Query spesifik SSH failed login & brute force:
   rule.id: (5710 or 5716 or 5712 or 5720 or 100010 or 100011 or 100012)

   Query spesifik kegagalan login akun root:
   data.dstuser: "root" and rule.groups: "authentication_failed"

   Query kegagalan dari IP publik tertentu:
   rule.groups: "authentication_failed" and not data.srcip: (10.* or 172.16.* or 192.168.*)

5. Atur Time Range di pojok kanan atas ke "Last 24 hours" atau "Last 15 minutes".
6. Klik "Update" / "Refresh". Semua event login gagal akan muncul berurutan.

4.2 Menambahkan Kolom Penting ke Saved View
```

Agar tabel log di Discover mudah dibaca oleh operator SOC, tambahkan field berikut 
dari kolom "Available fields" di sebelah kiri:
1. `agent.name`       (Nama server/host target)
2. `rule.description` (Keterangan rule yang terpicu)
3. `rule.level`       (Tingkat keparahan alert, misal 5, 10, 12)
4. `data.srcip`       (Alamat IP penyerang/klien)
5. `data.dstuser`     (Nama username yang dicoba)
6. `rule.id`          (Nomor rule ID)

Klik tombol "Save" di kanan atas, simpan dengan nama:
"View - SSH & System Failed Logins"

### 4.3 Membuat Visualisasi 1: Metric Total Failed Logins (24 Jam Terakhir)

```text
Visualisasi ini menampilkan angka besar total percobaan login gagal.
Langkah-langkah:
1. Klik Hamburger Menu -> Dashboard Management -> Visualize Library.
2. Klik tombol "Create visualization" (tombol biru).
3. Pilih tipe visualisasi: "Metric".
4. Pilih index pattern: `wazuh-alerts-*`.
5. Pada panel Metrics (kanan):
   - Metric Aggregation: `Count`
   - Custom Label: `Total Failed Logins`
6. Pada kolom search bar di bagian atas masukkan filter:
   `rule.groups: "authentication_failed"`
7. Klik tombol "Update". Angka total kegagalan akan muncul.
8. Klik "Save" di kanan atas -> Beri judul: `Metric - Total Failed Logins`.

4.4 Membuat Visualisasi 2: Data Table Top IP Penyerang (data.srcip)
```

Visualisasi ini menampilkan tabel daftar IP yang paling sering gagal login.
Langkah-langkah:
1. Klik Visualize Library -> "Create visualization" -> Pilih "Data Table".
2. Pilih index pattern: `wazuh-alerts-*`.
3. Filter bar: `rule.groups: "authentication_failed"`.
4. Di bagian Buckets:
   - Klik "Split rows".
   - Aggregation: `Terms`
   - Field: `data.srcip`
   - Order by: `metric: Count`
   - Order: `Descending`
   - Size: `10` (Menampilkan Top 10 IP)
   - Custom Label: `Attacker Source IP`
5. Klik "Update".
6. Klik "Save" -> Beri judul: `Table - Top 10 Attacker IPs`.

### 4.5 Membuat Visualisasi 3: Pie Chart Username Sasaran (Targeted Users)

```text
Visualisasi ini menampilkan persentase nama akun yang menjadi target serangan 
(misal root, admin, ubuntu, test, oracle).
Langkah-langkah:
1. Klik Visualize Library -> "Create visualization" -> Pilih "Pie".
2. Pilih index pattern: `wazuh-alerts-*`.
3. Filter bar: `rule.groups: "authentication_failed"`.
4. Di bagian Buckets:
   - Klik "Split slices".
   - Aggregation: `Terms`
   - Field: `data.dstuser`
   - Order by: `metric: Count`
   - Size: `10`
   - Custom Label: `Target Username`
5. Klik tab "Options" (di atas panel buckets) -> Centang "Donut" jika ingin tampilan donat.
6. Klik "Update".
7. Klik "Save" -> Beri judul: `Pie - Top Targeted Users`.

4.6 Membuat Visualisasi 4: Histogram Tren Gagal Login per Waktu
```

Visualisasi ini menampilkan grafik batang spike aktivitas serangan per waktu.
Langkah-langkah:
1. Klik Visualize Library -> "Create visualization" -> Pilih "Vertical Bar" atau "Area".
2. Pilih index pattern: `wazuh-alerts-*`.
3. Filter bar: `rule.groups: "authentication_failed"`.
4. Di bagian Buckets:
   - Klik "X-axis".
   - Aggregation: `Date Histogram`
   - Field: `timestamp`
   - Minimum interval: `Auto` (atau `Minute` / `Hour`)
5. (Opsional) Tambahkan sub-bucket "Split series" -> Terms -> `agent.name` untuk melihat
   server mana yang sedang diserang.
6. Klik "Update".
7. Klik "Save" -> Beri judul: `Chart - Failed Logins Over Time`.

### 4.7 Menyusun Custom Dashboard "Authentication Security Overview"

---

1. Klik Hamburger Menu -> pilih "Dashboard" (di bawah OpenSearch Dashboards).
2. Klik tombol "Create new dashboard".
3. Klik tombol "Add an existing" atau "Add from library".
4. Pilih 4 visualisasi yang sudah dibuat tadi:
   - `Metric - Total Failed Logins`
   - `Table - Top 10 Attacker IPs`
   - `Pie - Top Targeted Users`
   - `Chart - Failed Logins Over Time`
5. Atur tata letak (drag and resize) sesuai kebutuhan:
   - Letakkan Metric di pojok kiri atas.
   - Letakkan Chart tren waktu di kanan atas.
   - Letakkan Pie Chart di kiri bawah.
   - Letakkan Data Table di kanan bawah.
6. Klik tombol "Save" di kanan atas -> Isi Title:
   `Dashboard - Failed Login & Brute Force Monitor`
7. Simpan dashboard. Dashboard ini sekarang siap dipantau secara berkala oleh tim!

## 5. KONFIGURASI NOTIFIKASI REAL-TIME (EMAIL & WEBHOOK)

Agar administrator tidak perlu menatap dashboard 24 jam penuh, konfigurasikan
notifikasi otomatis saat rule gagal login berlevel tinggi terpicu.

### 5.1 Mengaktifkan Alert Email Otomatis di ossec.conf

```xml
Buka `/var/ossec/etc/ossec.conf` pada Wazuh Manager:
$ sudo nano /var/ossec/etc/ossec.conf

Cari blok `<ossec_config>` bagian `<global>` dan `<alerts>`:

  <global>
    <email_notification>yes</email_notification>
    <smtp_server>smtp.example.com</smtp_server>
    <email_from>wazuh-alert@example.com</email_from>
    <email_to>admin-soc@example.com</email_to>
    <email_maxperhour>100</email_maxperhour>
  </global>

  <alerts>
    <log_alert_level>3</log_alert_level>
    <!-- Hanya kirim email jika alert level >= 10 (seperti brute force / root attack) -->
    <email_alert_level>10</email_alert_level>
  </alerts>

5.2 Mengaktifkan Notifikasi via Webhook (Slack / Discord / Telegram)
```

Wazuh memiliki modul integrasi bawaan di `ossec.conf`.

Contoh integrasi ke Channel Slack:
```xml
  <integration>
    <name>slack</name>
    <hook_url>https://hooks.slack.com/services/T000/B000/XXXXXX</hook_url>
    <level>10</level>
    <group>authentication_failed,authentication_failures</group>
    <alert_format>json</alert_format>
  </integration>

Contoh integrasi kustom via script Python (misal Telegram Bot):
```

  <integration>
    <name>custom-telegram</name>
    <hook_url>https://api.telegram.org/bot<TOKEN>/sendMessage?chat_id=<CHAT_ID></hook_url>
    <level>10</level>
```xml
  <rule_id>100010, 100011, 5712</rule_id>
  <alert_format>json</alert_format>
</integration>
```

Restart Wazuh Manager setelah mengubah konfigurasi integrasi:
$ sudo systemctl restart wazuh-manager

## 6. KONFIGURASI ACTIVE RESPONSE (OTOMATIS BLOKIR IP PENYERANG)

Wazuh dapat bertindak aktif menghentikan penyerang dengan memblokir IP pengirim
secara instan di firewall endpoint (iptables / firewalld).

### 6.1 Konsep Active Response firewall-drop

```text
Ketika rule brute force (misal Rule ID 5712 atau Rule 100011) terpicu, Wazuh Manager
mengirim instruksi ke Agent untuk mengeksekusi script `firewall-drop` dengan parameter
IP penyerang (`srcip`).

6.2 Konfigurasi ossec.conf pada Wazuh Manager
```

Buka file `/var/ossec/etc/ossec.conf` di Wazuh Manager, dan tambahkan blok berikut:

  <!-- Mendefinisikan perintah yang dijalankan -->
  <command>
    <name>firewall-drop</name>
    <executable>firewall-drop</executable>
    <timeout_allowed>yes</timeout_allowed>
  </command>

  <!-- Memicu respon jika rule brute force atau custom rule terpicu -->
  <active-response>
    <command>firewall-drop</command>
    <location>local</location>
```xml
  <rules_id>5712, 100011</rules_id>
  <!-- Blokir IP selama 600 detik (10 menit) lalu unblock otomatis -->
  <timeout>600</timeout>
</active-response>
```

### 6.3 Menyetel Whitelist IP

---

Untuk mencegah IP administrator atau IP kantor terblokir secara tidak sengaja:
Tambahkan tag `<white_list>` di dalam blok `<global>` pada `ossec.conf`:

  <global>
    <white_list>127.0.0.1</white_list>
    <white_list>^localhost$</white_list>
    <white_list>192.168.1.100</white_list> <!-- IP Admin -->
    <white_list>10.0.0.0/16</white_list>   <!-- Jaringan Internal VPC -->
  </global>

Simpan dan restart Wazuh Manager:
$ sudo systemctl restart wazuh-manager

## 7. LANGKAH SIMULASI PENGUJIAN LENGKAP (SIMULATION SCENARIOS)

Lakukan pengujian dari mesin klien / remote attacker ke server endpoint (Agent)
yang sedang dimonitor. Pastikan Anda memiliki izin otorisasi untuk melakukan pengujian!

### 7.1 Skenario A: Uji Coba Single Failed Login SSH (Password Salah)

```bash
Tujuan: Menguji apakah rule dasar (Rule 5716) mendeteksi password salah.
Langkah:
1. Dari mesin laptop/klien Anda, jalankan perintah SSH ke IP Agent menggunakan
   user yang valid (misal `ec2-user` atau `ubuntu` atau user lokal Anda):
   
   $ ssh ec2-user@<IP_AGENT>

2. Saat diminta password, masukkan password yang SALAH sebanyak 1 kali.
3. Tekan Ctrl + C atau batalkan koneksi.
4. Verifikasi log lokal di Agent:
   - Amazon Linux/RHEL: `sudo tail -n 5 /var/log/secure`
   - Ubuntu/Debian:     `sudo tail -n 5 /var/log/auth.log`
   
   Akan terlihat baris seperti:
   "Failed password for ec2-user from <IP_KLIEN> port 52341 ssh2"

7.2 Skenario B: Uji Coba Login dengan User Fiktif (Non-Existent User)
```

Tujuan: Menguji deteksi login menggunakan user yang tidak ada (Rule 5710 / Rule 100012).
Langkah:
1. Dari mesin klien, lakukan SSH dengan username sembarang:
   
```bash
$ ssh hacker_percobaan@<IP_AGENT>
```

2. Masukkan sembarang password.
3. Verifikasi log di Agent:
   Akan tercatat:
   "Invalid user hacker_percobaan from <IP_KLIEN> port ..."
   "Failed password for invalid user hacker_percobaan from <IP_KLIEN>..."

### 7.3 Skenario C: Simulasi Brute Force Otomatis (Bash Loop Script)

Tujuan: Memicu rule brute force multi-attempt (Rule 5712 / Custom Rule 100011).
Langkah:
1. Dari mesin Linux klien, jalankan perintah satu baris (one-liner) loop berikut:

```bash
$ for i in {1..6}; do sshpass -p "PasswordSalah123" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 fakeuser@<IP_AGENT> "exit" 2>/dev/null; echo "Percobaan ke-$i gagal"; sleep 1; done
```

   Catatan:
   Jika tidak menginstall utility `sshpass`, Anda dapat menggunakan SSH biasa secara manual
   sebanyak 4-5 kali berturut-turut dalam waktu 30 detik, atau menggunakan script Python berikut:

   Script Python Alternatif (simulasi_bruteforce.py):
```text
-------------------------------------------------
```python
```

   import paramiko
   import time

```text
target_ip = "<IP_AGENT>"
port = 22
user = "testuser"
wrong_passwords = ["123456", "admin123", "password", "qwerty", "letmein"]

ssh = paramiko.SSHClient()
```

   ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

   for pwd in wrong_passwords:
       print(f"[*] Mencoba password: {pwd} ...")
```text
try:
```

           ssh.connect(target_ip, port=port, username=user, password=pwd, timeout=3)
       except Exception as e:
           print(f"[-] Gagal: {e}")
       time.sleep(1)
   ```

2. Jalankan script:
```bash
$ python3 simulasi_bruteforce.py
```

### 7.4 Skenario D: Simulasi Serangan Khusus Akun Root

```bash
Tujuan: Menguji eskalasi alert khusus user 'root' (Custom Rule 100010).
Langkah:
1. Dari mesin klien:
   $ ssh root@<IP_AGENT>
2. Masukkan password sembarang.
3. Ulangi 2 kali.
4. Ini akan memicu alert dengan level 10 di Wazuh Manager.

7.5 Skenario E: Simulasi Gagal Login Lokal Mesin (su / sudo)
```

Tujuan: Memverifikasi deteksi kegagalan otentikasi lokal PAM (Rule 5503).
Langkah:
1. Login ke server Agent secara normal.
2. Jalankan perintah ganti user ke root dengan password salah:
```bash
$ su -
Password: [masukkan sembarang password salah]
su: Authentication failure
```

3. Uji coba sudo dengan password salah:
```bash
$ sudo -k && sudo ls
```

   [sudo] password for user: [masukkan sembarang password salah]
   Sorry, try again.
4. Tekan Ctrl + C.

### 7.6 Skenario F: Simulasi Gagal Login Windows Agent (Event ID 4625)

---

Jika target endpoint adalah Microsoft Windows:
1. Buka PowerShell atau Command Prompt pada mesin klien:
   > net use \\<IP_WINDOWS_AGENT>\IPC$ /user:Administrator PasswordSalah123!
2. Perintah di atas akan menghasilkan error System Error 1326 (Logon failure).
3. Windows Security Log akan otomatis mencatat Event ID 4625.

## 8. VERIFIKASI & ANALISIS HASIL SIMULASI

Setelah melakukan simulasi, lakukan verifikasi menyeluruh untuk membuktikan bahwa 
alert berhasil tertangkap oleh seluruh komponen sistem.

### 8.1 Memeriksa Alert di Wazuh Dashboard (Web UI)

```text
1. Buka Wazuh Dashboard di browser.
2. Masuk ke menu:
   Threat Intelligence -> Threat Hunting -> Tab 'Events'.
3. Set time picker ke "Last 15 minutes".
4. Masukkan filter di search bar:
   `rule.groups: "authentication_failed"`
5. Anda akan melihat daftar event yang baru saja dipicu oleh simulasi:
   - Rule 5716: `sshd: authentication failed.`
   - Rule 5710: `sshd: Attempt to login using a non-existent user.`
   - Rule 100010 (jika tes root): `PERINGATAN: Upaya gagal login langsung ke akun root...`
   - Rule 5712 atau 100011 (jika tes loop): `sshd: brute force trying to get access...`
6. Buka salah satu baris event (klik tanda panah '>' di samping timestamp):
   - Periksa field `data.srcip` -> Harus sesuai dengan IP mesin penyerang/klien Anda.
   - Periksa field `data.dstuser` -> Harus sesuai dengan user yang disimulasikan.
   - Periksa field `rule.mitre.id` -> `T1110` (Brute Force).

8.2 Memeriksa Log Alert di File Sistem Wazuh Manager
```

Di server Wazuh Manager, periksa file alerts secara langsung:
$ sudo tail -n 50 /var/ossec/logs/alerts/alerts.log

Atau filter alert JSON menggunakan tool `jq`:
$ sudo tail -n 20 /var/ossec/logs/alerts/alerts.json | jq '{timestamp: .timestamp, agent: .agent.name, rule_id: .rule.id, description: .rule.description, srcip: .data.srcip, dstuser: .data.dstuser}'

Contoh output yang valid:
{
  "timestamp": "2026-09-09T15:30:12.441+0000",
  "agent": "hrptrsapprd",
  "rule_id": "5712",
  "description": "sshd: brute force trying to get access to the system.",
  "srcip": "198.51.100.24",
  "dstuser": "fakeuser"
}

### 8.3 Memeriksa Eksekusi Active Response di Agent

---

Jika Active Response aktif, periksa apakah Wazuh Agent berhasil mengeksekusi pemblokiran:
1. SSH ke endpoint Agent target.
2. Lihat log eksekusi respon aktif:
```bash
$ sudo cat /var/ossec/logs/active-responses.log
```

   Contoh isi log jika IP berhasil diblokir:
   2026/09/09 15:30:15 active-response/bin/firewall-drop: add 198.51.100.24 1725895815 5712

3. Cek tabel firewall endpoint:
   Untuk iptables:
```bash
$ sudo iptables -L INPUT -v -n | grep DROP
```

   
   Akan muncul baris drop rule dengan source IP mesin penyerang.

   Untuk firewalld:
```bash
$ sudo firewall-cmd --direct --get-all-rules
```

## 9. PANDUAN TROUBLESHOOTING JIKA ALERT TIDAK MUNCUL

Jika setelah simulasi dijalankan alert belum muncul di Wazuh Dashboard, lakukan 
investigasi bertahap berikut:

### 9.1 Periksa Status Koneksi Agent

```bash
Di server Wazuh Manager, pastikan agent dalam keadaan 'active':
$ sudo /var/ossec/bin/agent_control -l

Jika status agent 'disconnected' atau 'never_connected':
- Periksa port 1514/TCP dan 1514/UDP di Security Group AWS / Firewall jaringan.
- Periksa log agent di endpoint: `sudo tail -n 30 /var/ossec/logs/ossec.log`.

9.2 Periksa Hak Akses Pembacaan Log di Endpoint (Permission Issue)
```

Wazuh Agent berjalan dengan user `ossec`. User ossec harus memiliki izin membaca 
file log otentikasi.
- Cek permission `/var/log/secure` atau `/var/log/auth.log`:
```bash
$ ls -l /var/log/secure
Normalnya: `-rw------- 1 root root`
```

  Wazuh membaca file ini dengan hak root via proses daemon logcollector.
- Jika terdapat SELinux atau AppArmor yang memblokir pembacaan, periksa:
```bash
$ sudo ausearch -m avc -ts recent
```

### 9.3 Memeriksa archives.log (Perekaman Raw Logs) di Wazuh Manager

```xml
Untuk memastikan apakah baris log dari agent benar-benar sampai ke Manager:
1. Aktifkan opsi `logall_json` di `/var/ossec/etc/ossec.conf` Wazuh Manager:
   <ossec_config>
     <global>
       <logall_json>yes</logall_json>
     </global>
   </ossec_config>
2. Restart Wazuh Manager:
   $ sudo systemctl restart wazuh-manager
3. Jalankan simulasi login gagal lagi.
4. Periksa file `archives.json`:
   $ sudo grep "Failed password" /var/ossec/logs/archives/archives.json
   - Jika log MUNCUL di archives.json tetapi TIDAK ada di alerts.json:
     Artinya decoder membaca log tersebut, tetapi rule level di bawah ambang batas 
     alert (< 3) atau ada rule lain yang menimpanya (overwriting).
   - Jika log TIDAK MUNCUL di archives.json:
     Artinya agent belum mengirimkan baris log tersebut ke server (periksa config 
     `<localfile>` di agent).
5. CATATAN PENTING: Matikan kembali `<logall_json>no</logall_json>` setelah selesai 
   investigasi agar disk server tidak cepat penuh.

9.4 Periksa Filter dan Time Range di Wazuh Dashboard
```

- Periksa zona waktu (Timezone) pada browser Anda dan server Wazuh.
- Pastikan rentang waktu di pojok kanan atas Dashboard mencakup saat Anda melakukan 
  simulasi (misal: "Last 15 minutes" atau "Last 1 hour").
- Pastikan tidak ada filter tersembunyi yang mengecualikan event (cek baris filter KQL).

### 9.5 Refresh Index Pattern pada Wazuh Dashboard

Jika Anda baru saja menambahkan custom field:
1. Buka Hamburger Menu -> Dashboard Management -> Index Patterns.
2. Klik pattern `wazuh-alerts-*`.
3. Klik tombol "Refresh field list" (ikon panah melingkar di kanan atas).

## RINGKASAN WORKFLOW OPERASIONAL

1. LOG TERBENTUK   : Client SSH gagal -> /var/log/secure (Agent)
2. PENGIRIMAN LOG  : wazuh-agent (Logcollector) -> Port 1514 TCP -> Wazuh Manager
3. ANALISIS DATA   : Decoder (ekstrak srcip, dstuser) -> Rule matching (Rule 5716/100010)
4. ALERTING        : Ditulis ke alerts.json (Level >= 3) -> Terindeks ke OpenSearch
5. MONITORING      : Ditampilkan pada Wazuh Dashboard & Trigger Notifikasi (Email/Slack)
6. MITIGASI AKTIF  : Active Response (firewall-drop) memblokir srcip selama 10 menit

## DOKUMEN PANDUAN SELESAI
