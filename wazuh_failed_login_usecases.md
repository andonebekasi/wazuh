# USE CASES LENGKAP: DETEKSI, ALERTING & MITIGASI GAGAL LOGIN - PADA WAZUH SIEM (SOC GUIDE)

Dokumen ini berisi kumpulan Use Cases (Studi Kasus & Skenario Operasional) 
keamanan otentikasi untuk mendeteksi berbagai variasi serangan gagal login, 
brute force, credential stuffing, dan penyalahgunaan hak akses menggunakan 
Wazuh SIEM. 

Setiap use case dilengkapi dengan pemetaan MITRE ATT&CK, kontrol kepatuhan 
(Compliance), logika deteksi rule Wazuh, prosedur investigasi SOC (Triage & 
Incident Response SOP), serta skenario simulasinya.

### DAFTAR USE CASES

1.  USE CASE UC-AUTH-01: Eksternal SSH Brute Force Attack pada Public Server
2.  USE CASE UC-AUTH-02: Dictionary Attack & User Enumeration (Non-Existent Users)
3.  USE CASE UC-AUTH-03: Targeted Attack terhadap Akun Superuser ('root' / 'Administrator')
4.  USE CASE UC-AUTH-04: Password Spraying & Gerakan Lateral Internal (Lateral Movement)
5.  USE CASE UC-AUTH-05: Anomali Gagal Login di Luar Jam Operasional (Off-Hours Activity)
6.  USE CASE UC-AUTH-06: Upaya Eskalasi Hak Akses Lokal Gagal (su / sudo Brute Force)
7.  USE CASE UC-AUTH-07: Credential Stuffing pada Web Application / Reverse Proxy (HTTP 401)
8.  USE CASE UC-AUTH-08: Kepatuhan Regulasi Audit Otentikasi (PCI DSS, ISO 27001, SOC 2)
9.  MATRIKS RINGKASAN USE CASES & SEVERITY MAPPING
10. PLAYBOOK PENANGANAN INSIDEN (INCIDENT RESPONSE FLOWCHART)

## USE CASE UC-AUTH-01: EKSTERNAL SSH BRUTE FORCE ATTACK PADA PUBLIC SERVER

### 1.1 Deskripsi Skenario

```text
Server endpoint (misal EC2 instance atau VPS) memiliki port SSH (22) yang terekspos 
ke publik. Botnet atau penyerang otomatis dari internet melakukan pemindaian 
massal dan mencoba menebak kombinasi username dan password umum secara berulang-ulang 
dalam frekuensi tinggi.

1.2 Profil Ancaman
```

- Threat Actor  : Opportunistic Attacker, Automated Botnet, Script Kiddie
- Vektor Masuk  : Jaringan Publik Internet -> TCP Port 22
- Sasaran Utama : Mendapatkan akses remote shell awal (Initial Access)

### 1.3 Pemetaan Kerangka Kerja Keamanan

```text
- MITRE ATT&CK  : Tactic: Credential Access (TA0006)
                  Technique: Brute Force: Password Guessing (T1110.001)
- Compliance    : PCI DSS v3.2.1 / v4.0 (Req 8.1.6, 10.2.4, 11.4)
                  CIS Benchmark Linux (Control 5.2.x - SSH Hardening)
                  NIST 800-53 (AC-7 Unsuccessful Logon Attempts)

1.4 Indikator Log (Telemetry)
```

- Log Path   : `/var/log/secure` (RHEL/Amazon Linux) atau `/var/log/auth.log` (Ubuntu)
- Pattern Log: `Failed password for [user] from [IP] port [port] ssh2`
- Field Kunci: `data.srcip`, `data.dstuser`, `data.srcport`, `agent.name`

### 1.5 Logika Deteksi Wazuh

```xml
- Rule Bawaan: Rule ID 5716 (level 5), Rule ID 5712 (level 10)
- Custom Rule:
  ```xml
  <rule id="100011" level="12" frequency="5" timeframe="60">
    <if_matched_sid>5716</if_matched_sid>
    <same_source_ip />
    <description>KRITIS: Terdeteksi Brute Force SSH Agresif (>= 5 kali gagal dalam 60s) dari IP $(srcip)!</description>
    <mitre><id>T1110.001</id></mitre>
    <group>authentication_failures,attack,</group>
  </rule>
  ```

1.6 Severity: TINGGI / HIGH (Level 12)

1.7 Tindakan Mitigasi & Response SOP
```

1. Otomasi Active Response: Memicu skrip `firewall-drop` untuk memblokir IP penyerang 
   selama 3600 detik (1 jam) di iptables/firewalld.
2. Triage SOC:
   - Periksa apakah setelah rentetan gagal, ada log `Accepted password` atau 
     `Accepted publickey` dari IP penyerang yang sama.
   - Jika ada log login sukses setelah rentetan gagal -> Status: CRITICAL BREACH!
     Segera lakukan isolasi instance (Network Quarantine) dan kill active sessions.
3. Hardening Rekomendasi:
   - Nonaktifkan `PasswordAuthentication` di `/etc/ssh/sshd_config` (gunakan key-pair).
   - Batasi Security Group AWS port 22 hanya ke IP Bastion / VPN internal.

### 1.8 Cara Simulasi Pengujian

---

Jalankan dari mesin penguji Linux:
$ for i in {1..7}; do sshpass -p "WrongPass123" ssh -o StrictHostKeyChecking=no testuser@<IP_TARGET> "exit" 2>/dev/null; sleep 1; done

## USE CASE UC-AUTH-02: DICTIONARY ATTACK & USER ENUMERATION (NON-EXISTENT USERS)

### 2.1 Deskripsi Skenario

```text
Penyerang tidak mengetahui daftar pengguna yang sah pada server target. Mereka 
menggunakan daftar kata (wordlist) seperti `admin`, `support`, `oracle`, `git`, 
`deploy`, `test`, `postgres`, `guest` untuk mencari akun aktif sekaligus mencoba 
password default.

2.2 Profil Ancaman
```

- Threat Actor  : Cybercriminal, Reconnaissance Scanner
- Vektor Masuk  : SSH / Console Login
- Sasaran Utama : Identifikasi nama akun valid dan mengeksploitasi password lemah

### 2.3 Pemetaan Kerangka Kerja Keamanan

```text
- MITRE ATT&CK  : Tactic: Discovery (TA0007), Credential Access (TA0006)
                  Technique: Account Discovery: Local Accounts (T1087.001)
                  Technique: Brute Force: Password Spraying (T1110.003)
- Compliance    : ISO 27001 (A.9.4.2 Secure log-on procedures)
                  PCI DSS (Req 10.2.4)

2.4 Indikator Log (Telemetry)
```

- Log Path   : `/var/log/secure` atau `/var/log/auth.log`
- Pattern Log: `Invalid user [user] from [IP]`
               `Failed password for invalid user [user] from [IP]`
- Field Kunci: `rule.id: 5710`, `data.dstuser`, `data.srcip`

### 2.5 Logika Deteksi Wazuh

```xml
- Rule Bawaan: Rule ID 5710 (Level 5: Attempt to login using a non-existent user)
- Custom Rule:
  ```xml
  <rule id="100012" level="11" frequency="4" timeframe="90">
    <if_matched_sid>5710</if_matched_sid>
    <same_source_ip />
    <description>PERINGATAN: Terdeteksi User Enumeration / Dictionary Attack dari IP $(srcip) menggunakan berbagai username fiktif!</description>
    <mitre><id>T1087</id><id>T1110.003</id></mitre>
    <group>authentication_failures,recon,</group>
  </rule>
  ```

2.6 Severity: MEDIUM / HIGH (Level 11)

2.7 Tindakan Mitigasi & Response SOP
```

1. Tinjau apakah ada username dari wordlist yang tidak sengaja terdaftar di sistem.
2. Blokir IP penyerang secara permanen pada Network Access Control List (NACL) AWS.
3. Pastikan konfigurasi OpenSSH menyembunyikan detail validitas user:
   OpenSSH modern secara default memberikan timing yang serupa untuk memitigasi 
   username enumeration.

### 2.8 Cara Simulasi Pengujian

---

Jalankan loop uji coba user fiktif dari remote machine:
$ for user in admin developer dbadmin oracle deploy tester; do ssh -o StrictHostKeyChecking=no ${user}@<IP_TARGET> 2>/dev/null; sleep 1; done

## USE CASE UC-AUTH-03: TARGETED ATTACK TERHADAP AKUN SUPERUSER ('root' / 'Administrator')

### 3.1 Deskripsi Skenario

```text
Upaya login gagal langsung diarahkan ke akun superadministrator (`root` pada Linux 
atau `Administrator` pada Windows). Karena akun ini memiliki otoritas tertinggi, 
setiap percobaan login ke akun ini dianggap sebagai indikasi ancaman prioritas 
tinggi (High-Priority Threat).

3.2 Profil Ancaman
```

- Threat Actor  : Targeted Attacker, Ransomware Operator, Rogue Insider
- Vektor Masuk  : SSH, Local Console, RDP (Port 3389)
- Sasaran Utama : Privilege Abuse & Total System Takeover

### 3.3 Pemetaan Kerangka Kerja Keamanan

```text
- MITRE ATT&CK  : Tactic: Defense Evasion, Privilege Escalation
                  Technique: Valid Accounts: Default Accounts (T1078.001)
                  Technique: Brute Force (T1110)
- Compliance    : CIS Benchmark (Disable Direct Root Login)
                  PCI DSS (Req 8.2.1, 10.2.4)
                  SOC 2 (CC6.1 Logical Access Controls)

3.4 Indikator Log (Telemetry)
```

- Log Path   : `/var/log/secure` atau Windows Security Event 4625
- Pattern Log: `Failed password for root from [IP]`
- Field Kunci: `data.dstuser: "root"`, `data.srcip`

### 3.5 Logika Deteksi Wazuh

```xml
- Custom Rule Eskalasi Langsung (Level 10 pada percobaan pertama):
  ```xml
  <rule id="100010" level="10">
    <if_sid>5716, 5710, 5503</if_sid>
    <match>root</match>
    <description>PERINGATAN TINGGI: Percobaan login langsung ke akun root gagal dari IP $(srcip)!</description>
    <mitre><id>T1078</id><id>T1110</id></mitre>
    <group>authentication_failed,privileged_access,</group>
  </rule>
  ```

3.6 Severity: TINGGI / CRITICAL (Level 10 - 12)

3.7 Tindakan Mitigasi & Response SOP
```

1. Kirim notifikasi instan (High Priority Alert) via Telegram/Slack/Email ke tim On-Call.
2. Verifikasi konfigurasi SSH Daemon pada endpoint target:
   Pastikan pada `/etc/ssh/sshd_config`:
   `PermitRootLogin no` (atau `PermitRootLogin prohibit-password`).
3. Seluruh akses administratif wajib melalui user non-root (misal `ec2-user` atau nama admin) 
   lalu eskalasi via `sudo` ber-MFA.

### 3.8 Cara Simulasi Pengujian

---

$ ssh root@<IP_TARGET>
(Masukkan password sembarang, lalu batalkan)

## USE CASE UC-AUTH-04: PASSWORD SPRAYING & GERAKAN LATERAL INTERNAL

### 4.1 Deskripsi Skenario

```text
Sebuah mesin internal (misal laptop karyawan di VPN atau server aplikasi dev) 
telah disusupi malware. Penyerang menggunakan mesin tersebut sebagai batu loncatan 
untuk melakukan "Password Spraying" (mencoba 1 password yang sama ke seluruh server 
lain di dalam VPC private subnet agar akun tidak terkunci).

4.2 Profil Ancaman
```

- Threat Actor  : Advanced Persistent Threat (APT), Compromised Internal Host
- Vektor Masuk  : Jaringan Internal (Private IP range: 10.x.x.x / 172.16.x.x)
- Sasaran Utama : Gerakan Lateral (Lateral Movement) antar instance database & app

### 4.3 Pemetaan Kerangka Kerja Keamanan

```text
- MITRE ATT&CK  : Tactic: Lateral Movement (TA0008), Credential Access (TA0006)
                  Technique: Remote Services: SSH (T1021.004) / SMB/Windows Admin (T1021.002)
                  Technique: Brute Force: Password Spraying (T1110.003)
- Compliance    : Zero Trust Architecture Guidelines
                  PCI DSS (Req 1.3 - Restrict inbound/outbound traffic)

4.4 Indikator Log (Telemetry)
```

- Log Path   : File auth log pada seluruh instance target.
- Pola Unik  : `data.srcip` merupakan IP internal (Private IP). Percobaan gagal login 
               terjadi pada 3 atau lebih Agent yang berbeda dari 1 source IP internal.

### 4.5 Logika Deteksi Wazuh

```text
- Deteksi di Wazuh Dashboard via KQL Filter:
  `rule.groups: "authentication_failed" and data.srcip: (10.* or 172.16.* or 192.168.*)`
- Custom Correlation Rule di Wazuh Manager:
  Mendeteksi jika source IP yang sama memicu rule 5716 di beberapa agent berbeda.

4.6 Severity: TINGGI / HIGH (Level 11)

4.7 Tindakan Mitigasi & Response SOP
```

1. Identifikasi mesin sumber berdasarkan Private IP penyerang internal.
2. Lakukan Network Isolation (karantina SG AWS) terhadap mesin sumber tersebut.
3. Forensik endpoint sumber: Analisis proses mencurigakan, riwayat shell bash, 
   dan file malware yang berjalan pada host tersebut.

### 4.8 Cara Simulasi Pengujian

---

Dari satu mesin internal di VPC (misal IP 10.0.1.50):
$ ssh testuser@10.0.1.11 (masukkan pass salah)
$ ssh testuser@10.0.1.12 (masukkan pass salah)
$ ssh testuser@10.0.1.13 (masukkan pass salah)

## USE CASE UC-AUTH-05: ANOMALI GAGAL LOGIN DI LUAR JAM OPERASIONAL (OFF-HOURS)

### 5.1 Deskripsi Skenario

```text
Terjadi upaya login yang berulang kali gagal pada jam-jam tidak wajar (tengah malam, 
antara 22:00 - 05:00 pagi) terhadap akun pengguna staf operasional harian.

5.2 Profil Ancaman
```

- Threat Actor  : Insider Threat (karyawan nakal), Penyerang dari zona waktu berbeda
- Vektor Masuk  : VPN, Remote SSH, Web Portal
- Sasaran Utama : Menyerang saat tim monitoring/SOC diperkirakan lengah

### 5.3 Pemetaan Kerangka Kerja Keamanan

```text
- MITRE ATT&CK  : Tactic: Initial Access, Defense Evasion
                  Technique: Valid Accounts (T1078)
- Compliance    : NIST 800-53 (AC-2 Account Management - Temporary & Emergency)

5.4 Logika Deteksi Wazuh
```

- Menggunakan tag `<time>` pada sintaks rule Wazuh:
  ```xml
```xml
<rule id="100013" level="10">
  <if_sid>5716, 5710</if_sid>
  <time>10 pm - 5 am</time>
  <description>ANOMALI KEAMANAN: Upaya gagal login di luar jam operasional (22:00-05:00) untuk user $(dstuser) dari $(srcip)</description>
  <mitre><id>T1078</id></mitre>
  <group>authentication_failed,anomalous_activity,</group>
</rule>
```
```

### 5.5 Severity: MEDIUM / HIGH (Level 10)

### 5.6 Tindakan Mitigasi & Response SOP

---

1. Cek tiket perubahan (Change Request / Maintenance Window) resmi. Apakah ada 
   pekerjaan maintenance terjadwal di jam tersebut?
2. Jika tidak ada jadwal maintenance, hubungi pemilik akun untuk konfirmasi.
3. Jika pemilik akun sedang tidur / tidak mengakses, asumsikan kredensial telah bocor; 
   segera lakukan force-lock akun dan reset password.

## USE CASE UC-AUTH-06: UPAYA ESKALASI HAK AKSES LOKAL GAGAL (su / sudo BRUTE FORCE)

### 6.1 Deskripsi Skenario

```bash
Penyerang telah berhasil masuk ke server menggunakan user biasa (misal akun service 
aplikasi, web shell, atau compromised developer user). Penyerang kemudian mencoba 
menebak password root atau mencoba menjalankan command sudo berulang-ulang tanpa izin.

6.2 Profil Ancaman
```

- Threat Actor  : Compromised Local Process, Malicious Insider
- Vektor Masuk  : Local Shell / SSH Session yang sudah aktif
- Sasaran Utama : Privilege Escalation (Meningkatkan hak dari user biasa ke ROOT)

### 6.3 Pemetaan Kerangka Kerja Keamanan

```bash
- MITRE ATT&CK  : Tactic: Privilege Escalation (TA0004)
                  Technique: Abuse Elevation Control Mechanism: Sudo and Sudo Caching (T1548.003)
- Compliance    : PCI DSS (Req 10.2.5 - Log all use of administrative privileges)
                  CIS Benchmark (Audit sudo & su events)

6.4 Indikator Log (Telemetry)
```

- Log Path   : `/var/log/secure` atau `/var/log/auth.log`
- Pattern Log: `pam_unix(sudo:auth): authentication failure; logname=... uid=1001`
               `su: pam_unix(su-l:auth): authentication failure; logname=...`
- Field Kunci: `rule.id: 5503`, `rule.id: 5504`, `rule.groups: "pam"`

### 6.5 Logika Deteksi Wazuh

```xml
- Rule Bawaan:
  * Rule 5503: PAM: User login failed.
  * Rule 5504: PAM: Maximum authentication attempts exceeded.
- Custom Escalation Rule:
  ```xml
  <rule id="100014" level="11" frequency="3" timeframe="60">
    <if_matched_sid>5503</if_matched_sid>
    <description>KRITIS: Terdeteksi upaya eskalasi hak akses lokal berulang (su/sudo fail >= 3x) pada host $(agent.name)!</description>
    <mitre><id>T1548.003</id></mitre>
    <group>privilege_escalation,syslog,pam,</group>
  </rule>
  ```

6.6 Severity: TINGGI / CRITICAL (Level 11)

6.7 Tindakan Mitigasi & Response SOP
```

1. Identifikasi user login awal yang mencoba perintah `su`/`sudo` (`data.srcuser`).
2. Tinjau `/etc/sudoers` dan `/etc/sudoers.d/*` untuk memastikan hak sudo dibatasi ketat.
3. Periksa riwayat perintah shell:
```bash
$ history | tail -n 50
```

   atau periksa log auditd (`/var/log/audit/audit.log`).
4. Matikan koneksi session user yang bersangkutan:
```bash
$ pkill -KILL -u <username>
```

### 6.8 Cara Simulasi Pengujian

---

Login ke host target dengan user non-root, lalu jalankan:
$ sudo -k && sudo ls
(Masukkan sembarang password salah 3 kali berturut-turut)

## USE CASE UC-AUTH-07: CREDENTIAL STUFFING PADA WEB APP / REVERSE PROXY

### 7.1 Deskripsi Skenario

```text
Aplikasi web atau API gateway yang dilindungi reverse proxy (Nginx / HAProxy / Apache) 
menggunakan HTTP Basic Auth atau endpoint otentikasi login API. Penyerang menggunakan 
database bocoran akun dari internet (credential stuffing) untuk menyerang form login.

7.2 Profil Ancaman
```

- Threat Actor  : Fraudsters, Credential Stuffing Botnet
- Vektor Masuk  : HTTP/HTTPS Port 80/443
- Sasaran Utama : Account Takeover (ATO) pada portal web atau API

### 7.3 Pemetaan Kerangka Kerja Keamanan

```text
- MITRE ATT&CK  : Tactic: Credential Access (TA0006)
                  Technique: Brute Force: Credential Stuffing (T1110.004)
- OWASP Top 10  : A07:2021 - Identification and Authentication Failures

7.4 Indikator Log (Telemetry)
```

- Log Path   : `/var/log/nginx/error.log` atau `/var/log/nginx/access.log`
- Pattern Log: `user "[user]": password mismatch` atau HTTP Status Code `401 Unauthorized`
- Field Kunci: `rule.groups: "web,accesslog"`, `data.status: "401"`, `data.srcip`

### 7.5 Logika Deteksi Wazuh

```xml
- Konfigurasi log di Agent:
  ```xml
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/nginx/error.log</location>
  </localfile>
  ```
- Wazuh Built-in Rule ID: 31101 (HTTP status 401), Rule 31106 (Multiple 401 errors).
- Custom Rule:
  ```xml
  <rule id="100015" level="10" frequency="10" timeframe="60">
    <if_matched_sid>31101</if_matched_sid>
    <same_source_ip />
    <description>PERINGATAN: Terdeteksi Web Credential Stuffing / Brute Force (10x HTTP 401) dari IP $(srcip)!</description>
    <mitre><id>T1110.004</id></mitre>
    <group>web,app_attack,</group>
  </rule>
  ```

7.6 Severity: MEDIUM / HIGH (Level 10)

7.7 Tindakan Mitigasi & Response SOP
```

1. Integrasikan Wazuh Active Response untuk memblokir IP di tingkat edge atau host.
2. Implementasikan Rate Limiting pada Nginx (`limit_req_zone`).
3. Aktifkan CAPTCHA pada portal login web.

### 7.8 Cara Simulasi Pengujian

---

Gunakan utility `curl` dalam loop:
$ for i in {1..12}; do curl -s -o /dev/null -w "%{http_code}\n" -u testuser:WrongPass https://<IP_WEB_APP>/api/auth; sleep 0.5; done

## USE CASE UC-AUTH-08: KEPATUHAN REGULASI AUDIT OTENTIKASI (COMPLIANCE)

### 8.1 Deskripsi Skenario

```text
Perusahaan wajib memenuhi standar kepatuhan industri (PCI DSS untuk transaksi kartu, 
ISO 27001 untuk sistem manajemen keamanan informasi, atau HIPAA/SOC 2). Auditor 
memerlukan bukti sistematis bahwa setiap kegagalan login terekam, dianalisis, 
dan dapat dilaporkan secara berkala.

8.2 Standar & Kontrol Terkait
```

1. PCI DSS v4.0 Requirement 10.2.4:
   "Log all invalid logical access attempts, including attempts to logon to accounts, 
   and all attempts to elevate administrative access."
2. ISO/IEC 27001:2022 Control 8.15 (Logging) & 8.16 (Monitoring Activities):
   Pencatatan dan analisis anomali akses otentikasi.
3. Bank Indonesia / OJK Cybersecurity Guidelines:
   Kewajiban pencatatan log audit otentikasi minimal 6 bulan s/d 1 tahun.

### 8.3 Penerapan di Wazuh

- Setiap rule bawaan dan custom rule diberi tag group regulasi:
  `<group>pci_dss_10.2.4,pci_dss_10.2.5,gdpr_IV_35.7.d,tsc_CC6.1,</group>`
- Di Wazuh Dashboard:
  Tim GRC/Auditor langsung membuka modul **Regulatory Compliance** -> **PCI DSS** -> 
  melihat widget visual pemenuhan Requirement 10.2.4 tanpa perlu kueri manual.
- Menyusun laporan otomatis PDF via tombol "Generate Report" di pojok kanan atas Dashboard.

## 9. MATRIKS RINGKASAN USE CASES & SEVERITY MAPPING

| Use Case ID | Nama Skenario Ancaman | Rule ID | Alert Lvl | Respon Utama |
| :--- | :--- | :--- | :--- | :--- |
| UC-AUTH-01 | SSH External Brute Force | 5712 / | Level 12 | Active Response |
|  |  | 100011 | (Kritis) | firewall-drop |
| UC-AUTH-02 | User Enumeration / Dict Scan | 5710 / | Level 11 | IP Blocking & |
|  |  | 100012 | (Tinggi) | Firewall review |
| UC-AUTH-03 | Targeted Root Attack | 100010 | Level 10 | Instant Alert |
|  |  |  | (Tinggi) | Telegram/Slack |
| UC-AUTH-04 | Internal Password Spraying | Custom / | Level 11 | Host Isolation |
|  | (Lateral Movement) | 5716 | (Tinggi) | & User Reset |
| UC-AUTH-05 | Off-Hours Anomalous Login | 100013 | Level 10 | User Contact & |
|  |  |  | (Sedang) | Verification |
| UC-AUTH-06 | Local su / sudo Brute Force | 5503 / | Level 11 | Kill session & |
|  |  | 100014 | (Tinggi) | Process audit |
| UC-AUTH-07 | Web App Credential Stuffing | 31101 / | Level 10 | WAF / Nginx |
|  | (HTTP 401) | 100015 | (Sedang) | Rate Limiting |
| UC-AUTH-08 | Regulatory Audit & Log Arch | All Auth | Lvl >= 3 | Scheduled PDF |
|  |  | Rules | (Audit) | Compliance Rep. |

## 10. PLAYBOOK PENANGANAN INSIDEN (INCIDENT RESPONSE FLOWCHART)

Berikut alur kerja (Playbook) standar saat tim SOC menerima Alert Login Gagal:

[ ALERT DITERIMA DARI WAZUH DASHBOARD / SLACK ]
                    |
                    v
    [ Tahap 1: Validasi Sumber (Source Triage) ]
       * Apakah IP sumber adalah IP Internal (VPC/VPN) atau Eksternal Publik?
       * Apakah IP sumber ada dalam whitelist maintenance?
                    |

          |                   |

    [ Eksternal ]       [ Internal ]
          |                   |
          v                   v
   Cek Reputasi IP      Periksa Host Internal:
   (AbuseIPDB/VT)       * Siapa pemilik IP tersebut?
          |             * Apakah malware / script berjalan?
          |                   |

                    |

                    v
    [ Tahap 2: Cek Apakah Ada Keberhasilan Login (Success Verification) ]
       Query Dashboard: `data.srcip: "<IP_TERDAKWA>" and rule.id: 5715`
                    |

          |                   |

     [ ADA SUKSES ]      [ SEMUA GAGAL ]
          |                   |
          v                   v
   [ STATUS: BREACH! ]   [ STATUS: MITIGATED ]
   1. Segera ubah status 1. Pastikan IP terblokir di
      tiket ke SEV-1.       Active Response (iptables).
   2. Isolasi instance.  2. Jika IP publik persisten,
   3. Kill session aktif    tambahkan ke NACL AWS.
      penyerang.         3. Tutup tiket dengan catatan
   4. Force reset pass      serangan berhasil dicegah.
      dan revokasi key.
   5. Mulai investigasi
      forensik mendalam.

## DOKUMEN USE CASES SELESAI
