# KETERANGAN TAMBAHAN & CATATAN OPERASIONAL PRODUKSI - (Pendamping Panduan Instalasi & Operasional Wazuh SIEM di AWS EC2)

Dokumen ini berisi catatan operasional mendalam, kalkulasi sizing storage & EPS, 
production readiness checklist, anti-patterns, arsitektur keamanan AWS tingkat 
lanjut, optimasi biaya, monitoring SLI/SLO, serta runbook insiden untuk deployment 
Wazuh di Amazon Web Services (AWS).

## DAFTAR ISI

1. Ringkasan Eksekutif & Aliran Data Arsitektur Wazuh
2. Formula Sizing Storage, Kapasitas RAM & Kalkulasi EPS (Events Per Second)
3. Production Readiness Checklist (Audit Sebelum Go-Live)
4. Anti-Patterns & Kesalahan Fatal di Lapangan (What NOT to Do)
5. Rekomendasi Hardening Keamanan AWS (VPC, IAM, KMS, WAF & SSM)
6. Strategi Optimasi Biaya AWS (EC2 Graviton, EBS gp3 & S3 Glacier Tiering)
7. Indikator Kinerja Utama (SLI / SLO / KPI Monitoring)
8. Runbook Respon Insiden & Pemulihan Layanan (Disaster Recovery)
9. Integrasi Notifikasi Alert (Slack, Telegram & Email)
10. Catatan Operasional & Keterangan Tambahan Deployment Agent Skala Besar (Enterprise)
    - 10.1 Otomasi Mass-Deployment (Ansible, Terraform, EC2 User-Data)
    - 10.2 Manajemen Bandwidth Jaringan & Throttling Buffer Agent
    - 10.3 Resource Capping CPU & RAM Agent (Systemd Slice & Nice Priority)
    - 10.4 Penanganan False Positive FIM & Tuning Regex Whitelist
    - 10.5 Matriks Kepatuhan Audit Regulasi (PCI-DSS, ISO 27001, CIS Benchmark)
    - 10.6 Checklist Kesiapan Agent (Agent Pre-Go-Live Audit)
11. Panduan & Catatan Khusus Operasional Amazon Linux 2023 (AL2023)
    - 11.1 Karakteristik Inti AL2023 untuk Workload Wazuh SIEM
    - 11.2 Penanganan Swapfile pada Filesystem XFS (Aturan Khusus dd vs fallocate)
    - 11.3 Paket Minimalis, Dependensi Wajib & Analisis Error Konflik curl-minimal vs curl
    - 11.4 SELinux, CGroups v2 & System-Wide Crypto Policies
    - 11.5 Optimasi Wazuh pada AWS Graviton (ARM64) dengan AL2023
    - 11.6 Native AWS Systems Manager (SSM) & Zero SSH Key Access
    - 11.7 Cheat Sheet Pemeliharaan & Troubleshooting Khusus AL2023
12. Panduan & Troubleshooting Akses Wazuh Dashboard via SSH Tunnel & Bastion Host
    - 12.1 Analisis Penyebab Gagal Akses Port 443 via SSH Tunnel
    - 12.2 Port Binding Lokal: Privileged Port (< 1024) vs Non-Privileged (> 1024)
    - 12.3 Penanganan Protokol HTTPS vs HTTP & Peringatan SSL Self-Signed
    - 12.4 Konfigurasi AWS Security Group Inbound/Outbound (Bastion ke Wazuh EC2)
    - 12.5 Konfigurasi AllowTcpForwarding pada SSH Daemon Bastion
    - 12.6 Sintaks Praktis: Local Port Forwarding, ProxyJump & AWS SSM Port Forwarding
    - 12.7 Panduan Praktis SSH Tunneling Menggunakan PuTTY (Windows GUI)
13. Catatan Khusus Autentikasi Registrasi Agent (WAZUH_REGISTRATION_PASSWORD & authd.pass)
    - 13.1 Analisis & Asal-Usul Variabel WAZUH_REGISTRATION_PASSWORD
    - 13.2 Hasil Investigasi Lapangan: Mengapa Muncul 'No such file or directory'
    - 13.3 Matriks Keputusan: Kapan Variabel Password Wajib Dipakai vs Dihilangkan
    - 13.4 Sintaks Final Rekomendasi Eksekusi di Agent Amazon Linux (AL2 & AL2023)
    - 13.5 Prosedur Pengerasan (Hardening): Cara Mengaktifkan authd.pass di Sisi Manager
14. Panduan & Troubleshooting AWS Application Load Balancer (ALB) untuk Wazuh Dashboard
    - 14.1 Analisis Masalah Unhealthy Target: HTTP 302 Found vs Success Codes
    - 14.2 Mengapa Path /app/login Tetap Mengembalikan HTTP 302
    - 14.3 Prosedur Perbaikan Konfigurasi Target Group (Success codes 200,302)
    - 14.4 Konfigurasi Kritis ALB: Stickiness, Idle Timeout, dan Security Group

## 1. RINGKASAN EKSEKUTIF & ALIRAN DATA ARSITEKTUR WAZUH

Dalam implementasi Wazuh di AWS EC2, aliran data (data pipeline) berjalan sebagai berikut:

[Endpoint/Server Target]
      │
      │ (Port 1514 TCP - Encrypted Event Stream)
      ▼
[Wazuh Manager / Server]
      │ - Decoding log mentah
      │ - Pencocokan signature & security rules
      │ - Vulnerability assessment & threat detection
      │ - Active response trigger
      ▼
[Filebeat Local Agent]
      │
      │ (Port 9200 TCP HTTPS - Bulk Indexing)
      ▼
[Wazuh Indexer (OpenSearch)]
      │ - Penyimpanan terindeks (Shards & Replicas)
      │ - Pencarian data cepat & kompresi storage
      ▼
[Wazuh Dashboard] ◄─── (Port 443 HTTPS) ─── [Security Analyst / Admin]

Pemisahan Peran Komponen:
1. Wazuh Manager: Berfokus pada CPU dan pemrosesan stream real-time.
2. Wazuh Indexer: Berfokus pada RAM (JVM Heap) dan Disk I/O (EBS IOPS/Throughput).
3. Wazuh Dashboard: Berfokus pada rendering visual UI dan interaksi API.

## 2. FORMULA SIZING STORAGE, KAPASITAS RAM & KALKULASI EPS (EVENTS PER SECOND)

### 2.1 FORMULA PERHITUNGAN STORAGE LOG HARIAN

Rata-rata ukuran 1 log event setelah didecode dan diindeks adalah ~800 Bytes s/d 1.2 KB.

Rumus Kebutuhan Disk EBS Harian:
  Storage/Hari (GB) = (Total EPS * Rata-rata Ukuran Log (KB) * 86.400 detik) 
                      / (1.024 * 1.024) * Overhead Index (~1.3x)

Tabel Estimasi Berdasarkan Skala Deployment:

| Skala Node Agent | Rata-rata EPS | Log/Hari (GB) | Kebutuhan EBS (Retensi 90 Hari) |
| :--- | :--- | :--- | :--- |
| 10 Server / EC2 | ~50 EPS | ~5 - 7 GB | 450 GB - 650 GB gp3 |
| 50 Server / EC2 | ~250 EPS | ~25 - 35 GB | 2.2 TB - 3.1 TB gp3 |
| 100 Server / EC2 | ~500 EPS | ~50 - 70 GB | 4.5 TB - 6.3 TB gp3 |
| 500 Server (Cluster) | ~2500 EPS | ~250 - 350 GB | Disarankan S3 Archiving Tier |

### 2.2 FORMULA ALOKASI RAM PADA ALL-IN-ONE NODE

Jika Anda menjalankan Wazuh All-in-One pada 1 instance EC2:
- Wazuh Indexer JVM Heap : Berikan maksimal 50% dari total RAM fisik instance.
  Contoh: Instance 16 GB RAM -> `-Xms8g -Xmx8g` di `/etc/wazuh-indexer/jvm.options`.
```text
CATATAN: Jangan pernah menyetel JVM heap lebih dari 31 GB karena OpenSearch 
```

  akan kehilangan optimasi Compressed OOPs (Ordinary Object Pointers).
- Wazuh Manager & Filebeat: 2 GB - 4 GB RAM.
- Wazuh Dashboard        : 1 GB - 2 GB RAM.
- OS Kernel & File Cache : Sisa RAM (3 GB - 4 GB) untuk filesystem cache Linux.

## 3. PRODUCTION READINESS CHECKLIST (AUDIT SEBELUM GO-LIVE)

[ ] 1. Infrastruktur Jaringan & AWS Security Group:
    - [ ] Port 9200 (Indexer) dan 55000 (API) TIDAK terbuka ke publik (0.0.0.0/0).
    - [ ] Port 443 (Dashboard) berada di balik ALB atau diproteksi whitelist IP.
    - [ ] Menggunakan Elastic IP (EIP) atau Route 53 Private Hosted Zone (bukan IP dinamis).
    - [ ] Port 1514 dan 1515 hanya menerima koneksi dari IP VPC / Subnet server target.

[ ] 2. Konfigurasi Sistem Operasi EC2:
    - [ ] Parameter `vm.max_map_count = 262144` permanen di `/etc/sysctl.conf`.
    - [ ] Batas file descriptors `nofile 65536` terpasang di `/etc/security/limits.conf`.
    - [ ] Swap file minimal 4 GB aktif untuk meredam lonjakan memori tak terduga.
    - [ ] Timezone disetel seragam (UTC direkomendasikan) dan NTP / chrony aktif.

[ ] 3. Keamanan & Kredensial:
    - [ ] Password default user 'admin' telah diganti menggunakan `indexer-security-admin.sh`.
    - [ ] File arsip `wazuh-install-files.tar` dipindahkan ke lokasi aman / dienkripsi.
    - [ ] Sertifikat SSL Dashboard menggunakan sertifikat valid (AWS ACM atau Let's Encrypt), 
          bukan self-signed certificate bawaan installer.

[ ] 4. Retensi Data & Disaster Recovery:
    - [ ] Index State Management (ISM) diaktifkan untuk auto-delete / rollover index > 30-90 hari.
    - [ ] AWS Data Lifecycle Manager (DLM) aktif untuk membuat snapshot harian EBS volume.
    - [ ] Backup konfigurasi `/var/ossec/etc/` berjalan terjadwal via cron.

## 4. ANTI-PATTERNS & KESALAHAN FATAL DI LAPANGAN (WHAT NOT TO DO)

1. Menjalankan Wazuh All-in-One pada EC2 dengan RAM Kurang dari 8 GB
   - Kesalahan: Menggunakan t3.small (2GB) atau t3.medium (4GB).
   - Akibat: JVM Indexer akan terkena Linux OOM-Killer (`dmesg | grep oom-killer`), 
     menyebabkan database crash berulang kali dan data log korup.

2. Menggunakan Dynamic Public IP untuk Konfigurasi Wazuh Agent
   - Kesalahan: Mendaftarkan agent ke IP publik bawaan EC2 tanpa Elastic IP.
   - Akibat: Saat instance EC2 di-stop dan di-start kembali, IP publik berubah, 
     menyebabkan seluruh agent di seluruh armada server berstatus "Disconnected".
   - Solusi: Selalu gunakan Elastic IP (EIP), DNS Name (Route 53), atau IP Private VPC.

3. Mengabaikan Index Watermark Disk EBS
   - Kesalahan: Membiarkan disk EBS terisi hingga > 90% tanpa pembersihan.
   - Akibat: OpenSearch memiliki flood-stage disk watermark (default 95%). Saat tercapai, 
     seluruh index terkunci menjadi READ-ONLY (`read_only_allow_delete = true`). 
     Log baru ditolak dan sistem berhenti beroperasi.

4. Menyimpan Semua Log Mentah di Indexer untuk Retensi Multi-Tahun
   - Kesalahan: Menyimpan 3 tahun log aktif di OpenSearch Indexer.
   - Akibat: Biaya EBS gp3 membengkak drastis dan search query dashboard menjadi sangat lambat.
   - Solusi: Simpan log aktif 30-90 hari di Indexer; log mentah kepatuhan (compliance) 
     dikompresi dan dikirim ke AWS S3 Glacier Deep Archive (hemat biaya hingga 90%).

5. Mengekspos API Port 55000 dan Port 9200 ke Internet Publik
   - Kesalahan: Membuka port 55000 atau 9200 ke `0.0.0.0/0`.
   - Akibat: Membuka celah brute force API credential dan eksposur metadata keamanan internal.

## 5. REKOMENDASI HARDENING KEAMANAN AWS (VPC, IAM, KMS, WAF & SSM)

1. Deployment di Private Subnet:
   - Letakkan EC2 Wazuh di Private Subnet tanpa IP Publik langsung.
   - Akses Web UI (Port 443) melalui AWS Application Load Balancer (ALB) di Public Subnet.
   - Untuk komunikasi Agent dari luar VPC, gunakan AWS Transit Gateway, Site-to-Site VPN, 
     atau Network Load Balancer (NLB) khusus port 1514/1515.

2. Akses SSH Tanpa Kunci Menggunakan AWS Systems Manager (SSM):
   - Pasang IAM Role dengan managed policy `AmazonSSMManagedInstanceCore` pada EC2 Wazuh.
   - Tutup total port SSH 22 pada Security Group.
   - Akses terminal secara aman melalui AWS CLI:
```bash
aws ssm start-session --target <INSTANCE_ID>
```

3. Enkripsi At-Rest dengan AWS KMS:
   - Pastikan seluruh EBS Volume (root dan data volume) dienkripsi menggunakan KMS Customer 
     Managed Key (CMK) atau `aws/ebs`.

4. Proteksi Web Dashboard dengan AWS WAF:
   - Pasang AWS WAF pada Application Load Balancer (ALB) di depan Wazuh Dashboard.
   - Aktifkan aturan:
     * AWSManagedRulesCommonRuleSet (proteksi OWASP Top 10).
     * AWSManagedRulesKnownBadInputsRuleSet.
     * Rate-based rule: Batasi maksimal 200 request per 5 menit per IP untuk mencegah brute-force login.

## 6. STRATEGI OPTIMASI BIAYA AWS (EC2 GRAVITON, EBS GP3 & S3 GLACIER TIERING)

1. Gunakan EC2 Berbasis Prosesor AWS Graviton (ARM64):
   - Wazuh Manager dan OpenSearch Indexer mendukung arsitektur ARM64.
   - Gunakan instance tipe `m7g.xlarge` atau `c7g.xlarge`.
   - Manfaat: Menghemat biaya hingga ~20% dibandingkan x86_64 dengan performa komputasi lebih tinggi.

2. Optimasi EBS Storage (gp3 Volume Tuning):
   - Gunakan tipe `gp3` (jangan gunakan `gp2` yang lebih mahal dan tidak fleksibel).
   - Baseline gp3 menyediakan 3.000 IOPS dan 125 MB/s throughput gratis tanpa biaya tambahan.
   - Jika disk melebihi 1 TB, throughput 125 MB/s sudah sangat cukup untuk menangani 500 EPS.

3. Arsitektur Cold Storage Hemat Biaya ke AWS S3:
   - Wazuh Manager menyimpan arsip log terkompresi di:
     `/var/ossec/logs/archives/archives.json`
   - Buat script sinkronisasi harian ke S3 Bucket:
```bash
aws s3 sync /var/ossec/logs/archives/ s3://wazuh-cold-archive-perusahaan/
```

   - Buat S3 Lifecycle Rule:
     * Pindahkan ke S3 Standard-Infrequent Access (IA) setelah 30 hari.
     * Pindahkan ke S3 Glacier Flexible Archive setelah 90 hari.
     * Hapus permanen setelah 365 hari (atau sesuai audit compliance).

## 7. INDIKATOR KINERJA UTAMA (SLI / SLO / KPI MONITORING)

Pantau metrik-metrik berikut secara berkala menggunakan CloudWatch Agent atau Prometheus:

1. Status Kesehatan Cluster Indexer (Cluster Health):
   - Nilai: GREEN (Semua primary dan replica shard teralokasi).
   - YELLOW: Replica shard tidak teralokasi (normal pada single-node All-in-One).
   - RED: Primary shard korup / hilang (KRITIKAL - segera ambil tindakan).
   - Cek via CLI:
```bash
curl -k -u admin:<password> https://127.0.0.1:9200/_cluster/health?pretty
```

2. Utilisasi JVM Memory Indexer:
   - Target SLO: < 75% penggunaan heap.
   - Alert Threshold: > 85% selama 10 menit terus-menerus.

3. Utilisasi Kapasitas EBS Storage:
   - Warning Threshold: 75% pemakaian partisi `/var`.
   - Critical Alert: 85% pemakaian (sebelum menyentuh flood-stage 95%).

4. Status Koneksi Agent (Agent Status):
   - Target SLO: 98% agent aktif berstatus "Active".
   - Deteksi dini agent down:
```bash
/var/ossec/bin/agent_control -l | grep -c "Disconnected"
```

## 8. RUNBOOK RESPON INSIDEN & PEMULIHAN LAYANAN (DISASTER RECOVERY)

--- INSIDEN 1: CLUSTER STATUS RED ATAU SHARD UNASSIGNED ---
Gejala: Dashboard lambat, alert log tidak muncul, API Indexer menampilkan status "red".
#### Langkah Pemulihan:

1. Cek shard yang bermasalah:
```bash
curl -k -u admin:<password> https://127.0.0.1:9200/_cat/shards?v | grep -i unassigned
```

2. Cek alasan kegagalan alokasi shard:
```bash
curl -k -u admin:<password> https://127.0.0.1:9200/_cluster/allocation/explain?pretty
```

3. Jika pada All-in-One node terdapat replica shard unassigned:
   Set jumlah replica menjadi 0 untuk semua index:
```bash
curl -k -u admin:<password> -X PUT "https://127.0.0.1:9200/*/_settings" \
```

     -H 'Content-Type: application/json' -d '{"index": {"number_of_replicas": 0}}'

--- INSIDEN 2: DISK FULL (READ-ONLY LOCK WATERMARK TERCAPAI) ---
Gejala: Error `index_create_block_exception` atau `FORBIDDEN/12/index read-only / allow delete`.
#### Langkah Pemulihan:

1. Hapus index lama untuk membebaskan ruang disk (misal index 3 bulan lalu):
```bash
curl -k -u admin:<password> -X DELETE "https://127.0.0.1:9200/wazuh-alerts-4.x-2026.06.*"
```

2. Lepaskan kunci read-only pada seluruh index:
```bash
curl -k -u admin:<password> -X PUT "https://127.0.0.1:9200/*/_settings" \
```

     -H 'Content-Type: application/json' \
     -d '{"index.blocks.read_only_allow_delete": null}'
3. Pastikan service kembali normal:
```bash
sudo systemctl restart filebeat
```

--- INSIDEN 3: LOG STORM / LONJAKAN TRAFIK LOG TINGGI (HIGH CPU) ---
Gejala: CPU EC2 100%, ossec-analysisd memakan seluruh resource.
#### Langkah Pemulihan:

1. Identifikasi agent penghasil log terbesar:
```bash
sudo tail -n 1000 /var/ossec/logs/archives/archives.json | jq -r '.agent.name' | sort | uniq -c | sort -nr | head -n 5
```

2. Batasi EPS per agent di sisi server (`/var/ossec/etc/ossec.conf`):
   Tambahkan di blok `<remote>`:
   <eps>500</eps>
3. Restart Wazuh Manager:
```bash
sudo systemctl restart wazuh-manager
```

## 9. INTEGRASI NOTIFIKASI ALERT (SLACK, TELEGRAM & EMAIL)

Wazuh Manager mendukung pengiriman notifikasi otomatis langsung ke kanal komunikasi tim DevOps/SecOps.

#### A. INTEGRASI SLACK WEBHOOK:

1. Buat Incoming Webhook URL di aplikasi Slack workspace Anda.
2. Edit `/var/ossec/etc/ossec.conf` pada Wazuh Manager:
```xml
<ossec_config>
  <integration>
    <name>slack</name>
    <hook_url>https://hooks.slack.com/services/T000/B000/XXXXXX</hook_url>
    <level>10</level> <!-- Hanya alert tingkat keparahan level 10 ke atas -->
    <alert_format>json</alert_format>
  </integration>
</ossec_config>
```

3. Restart Wazuh Manager:
```bash
sudo systemctl restart wazuh-manager
```

#### B. INTEGRASI TELEGRAM BOT:

1. Buat custom script integration di `/var/ossec/integrations/custom-telegram.py`.
2. Pasang script dan panggil via tag `<integration>` dengan nama `custom-telegram`.

## 10. CATATAN OPERASIONAL & KETERANGAN TAMBAHAN DEPLOYMENT AGENT SKALA BESAR (ENTERPRISE)

### 10.1 OTOMASI MASS-DEPLOYMENT AGENT (ANSIBLE, TERRAFORM, EC2 USER-DATA)

Ketika mengelola puluhan hingga ribuan instance di cloud AWS, deployment manual 
adalah anti-pattern. Gunakan salah satu metode otomasi berikut:

#### A. Via AWS EC2 User-Data (Otomatis saat Launch Instance Baru):

   A.1 Untuk Target Ubuntu / Debian:
   #!/bin/bash
```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
```

   apt-get update -y
```bash
WAZUH_MANAGER="10.0.1.50" WAZUH_AGENT_GROUP="production-nodes" apt-get install -y wazuh-agent
systemctl enable --now wazuh-agent
```

   A.2 Untuk Target Amazon Linux 2023 (AL2023):
   #!/bin/bash
```bash
rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
cat > /etc/yum.repos.d/wazuh.repo << 'EOF'
```

[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF
```bash
dnf update -y
WAZUH_MANAGER="10.0.1.50" WAZUH_AGENT_GROUP="al2023-production-nodes" dnf install -y wazuh-agent
systemctl enable --now wazuh-agent
```

#### B. Via Ansible Playbook (Untuk Armada Server yang Sudah Berjalan):

   B.1 Untuk Armada Ubuntu / Debian:
   - name: Deploy Wazuh Agent di Ubuntu/Debian
```text
hosts: ubuntu_servers
become: yes
vars:
  wazuh_manager_ip: "10.0.1.50"
  wazuh_group: "production-servers"
tasks:
```

       - name: Download GPG Key
```text
apt_key:
  url: https://packages.wazuh.com/key/GPG-KEY-WAZUH
  state: present
```

       - name: Add Repository
```text
apt_repository:
  repo: "deb https://packages.wazuh.com/4.x/apt/ stable main"
  state: present
```

       - name: Install Wazuh Agent
```text
apt:
  name: wazuh-agent
  state: present
environment:
  WAZUH_MANAGER: "{{ wazuh_manager_ip }}"
  WAZUH_AGENT_GROUP: "{{ wazuh_group }}"
```

       - name: Start & Enable Agent Service
```text
systemd:
  name: wazuh-agent
  enabled: yes
  state: started
```

   B.2 Untuk Armada Amazon Linux 2023 (AL2023):
   - name: Deploy Wazuh Agent di Amazon Linux 2023
```text
hosts: al2023_servers
become: yes
vars:
  wazuh_manager_ip: "10.0.1.50"
  wazuh_group: "al2023-production-servers"
tasks:
```

       - name: Import Wazuh GPG Key
```text
rpm_key:
  key: https://packages.wazuh.com/key/GPG-KEY-WAZUH
  state: present
```

       - name: Add Wazuh YUM/DNF Repository
```text
yum_repository:
  name: wazuh
  description: EL-$releasever - Wazuh
  baseurl: https://packages.wazuh.com/4.x/yum/
  gpgcheck: yes
  gpgkey: https://packages.wazuh.com/key/GPG-KEY-WAZUH
  enabled: yes
```

       - name: Install Wazuh Agent via DNF
```text
dnf:
  name: wazuh-agent
  state: present
environment:
  WAZUH_MANAGER: "{{ wazuh_manager_ip }}"
  WAZUH_AGENT_GROUP: "{{ wazuh_group }}"
```

       - name: Start & Enable Agent Service
```text
systemd:
  name: wazuh-agent
  enabled: yes
  state: started
```

### 10.2 MANAJEMEN BANDWIDTH JARINGAN & THROTTLING BUFFER AGENT

Secara default, jika sebuah aplikasi mengalami crash loop atau serangan DDoS, 
volume log lokal dapat melonjak tajam (log burst). Tanpa throttling, ini dapat 
menghabiskan bandwidth VPC dan membanjiri antrean Wazuh Manager.

Konfigurasi Throttling Buffer di Agent (`/var/ossec/etc/ossec.conf`):
  <client_buffer>
    <!-- Aktifkan antrean buffer lokal di disk/memory jika koneksi ke server padat -->
    <disabled>no</disabled>
    <!-- Maksimal EPS yang dikirim oleh agent ke manager per detik -->
    <events_per_second>500</events_per_second>
    <!-- Kapasitas buffer antrean lokal sebelum mendrop event lama -->
    <queue_size>5000</queue_size>
  </client_buffer>

### 10.3 RESOURCE CAPPING CPU & RAM PADA AGENT (SYSTEMD & CGROUPS)

Wazuh Agent dirancang sangat ringan (< 1-2% CPU dan ~50-100 MB RAM). Namun, saat 
FIM (syscheck) melakukan pemindaian awal atau hashing SHA-256 pada disk yang lambat, 
penggunaan CPU dapat melonjak sesaat.

Untuk melindungi aplikasi bisnis (seperti Java / Nginx / Database) agar tidak 
terganggu oleh aktivitas security agent:

1. Buat Systemd Override untuk Wazuh Agent:
```bash
sudo systemctl edit wazuh-agent
```

2. Tambahkan konfigurasi pembatasan resource:
```ini
[Service]
# Batasi CPU maksimal agent hanya 20% dari 1 Core CPU
CPUQuota=20%
# Batasi RAM maksimal agent 256 MB (cegah memory leak lokal)
MemoryMax=256M
# Berikan prioritas scheduling rendah (Nice) agar proses bisnis didahulukan
Nice=19
```

3. Terapkan:
```bash
sudo systemctl daemon-reload
sudo systemctl restart wazuh-agent
```

### 10.4 PENANGANAN FALSE POSITIVE FIM & TUNING REGEX WHITELIST

Masalah umum: Alert FIM membanjiri dashboard karena file log berputar (logrotate) 
atau file cache aplikasi terus diperbarui.

Solusi: Konfigurasikan ignore regex di `/var/ossec/etc/ossec.conf` (atau via `agent.conf`):
  <syscheck>
    <!-- Abaikan direktori cache dinamis dan node_modules -->
    <ignore type="sregex">^/var/www/.*/storage/framework/cache</ignore>
    <ignore type="sregex">^/var/www/.*/node_modules</ignore>
    <ignore type="sregex">^/var/log/.*\.gz$</ignore>
    <ignore type="sregex">^/var/log/.*\.1$</ignore>
    <ignore type="sregex">^/tmp/.*</ignore>
    
    <!-- Jangan laporkan perubahan timestamp (hanya laporkan jika isi hash berubah) -->
    <nodiff>/etc/ssl/certs</nodiff>
  </syscheck>

### 10.5 MATRIKS KEPATUHAN AUDIT REGULASI (PCI-DSS, ISO 27001, CIS BENCHMARK)

Wazuh Agent secara otomatis memetakan deteksi keamanan ke standar audit regulasi:

Standar Regulasi   | Modul Wazuh Agent Terkait         | Fungsi & Kontrol

| PCI-DSS v4.0 Req 10 | Log Analysis & Audit Logs | Mencatat dan memantau seluruh akses jaringan & sistem |
| :--- | :--- | :--- |
| PCI-DSS v4.0 Req 11 | Syscheck (FIM) & Whodata | Verifikasi integritas file biner, library, dan file config |
| ISO 27001 (A.12.4) | Log Collection & Localfile | Pemantauan aktivitas log pengguna dan proteksi tampering |
| CIS Benchmark | SCA (Security Config Assessment) | Audit konfigurasi OS (disable root login, password complexity) |
| MITRE ATT&CK | Rule Engine & Rootcheck | Deteksi teknik serangan (T1059 Command Execution, T1078 Valid Accounts) |

### 10.6 CHECKLIST KESIAPAN AGENT (AGENT PRE-GO-LIVE AUDIT)

[ ] 1. Agent terdaftar dengan nama hostname yang jelas dan masuk ke grup yang tepat.
[ ] 2. Status di Dashboard: "Active" (bukan "Disconnected" atau "Never Connected").
[ ] 3. FIM memonitor direktori kritikal (`/etc`, `/usr/bin`, `/root/.ssh`) tanpa memonitor cache/tmp.
[ ] 4. Filebeat & analysisd tidak mengalami drop event akibat throttling.
[ ] 5. Client buffer aktif dengan batas 500 EPS untuk mencegah log storm.
[ ] 6. Resource CPUQuota pada systemd terpasang agar tidak merebut CPU aplikasi produksi.
[ ] 7. Uji Active Response: Jalankan simulasi 5x gagal login SSH dari IP uji coba dan 
       pastikan IP terblokir otomatis di firewall.

## 11. PANDUAN & CATATAN KHUSUS OPERASIONAL AMAZON LINUX 2023 (AL2023)

### 11.1 KARAKTERISTIK INTI AL2023 UNTUK WORKLOAD WAZUH SIEM

Amazon Linux 2023 (AL2023) dirancang khusus oleh AWS untuk performa cloud tinggi, 
integrasi native dengan layanan AWS, dan footprint keamanan minimal:
- Siklus Rilis Deterministik: Pembaruan versi utama setiap 2 tahun dengan dukungan 5 tahun. 
  Repository terkunci ke versi rilis (version locking) untuk stabilitas produksi.
- Modern Toolchain: Kernel 6.1 LTS, GCC 11, Glibc 2.34, Systemd 252, OpenSSL 3.0.
- DNF Package Manager: Menggantikan YUM lama dengan performa parsing metadata lebih cepat.
- Footprint Minimal: Tidak ada dependensi usang (legacy Python 2 atau init.d scripts), 
  menjadikan instance lebih aman dari celah keamanan pihak ketiga.

### 11.2 PENANGANAN SWAPFILE PADA FILESYSTEM XFS (ATURAN KHUSUS DD VS FALLOCATE)

Di AWS EC2, instance Amazon Linux 2023 secara default menggunakan partisi root 
bertipe XFS (bukan ext4).
- MASALAH: Pembuatan file swap menggunakan perintah `fallocate` pada filesystem XFS 
  modern akan menghasilkan error saat diaktifkan:
```text
# fallocate -l 4G /swapfile
# swapon /swapfile
swapon: /swapfile: swapon failed: Invalid argument
```

    (atau log dmesg: "swapon: swapfile has holes")
  Hal ini terjadi karena alokasi unwritten extents dan fitur reflink pada XFS 
  dianggap oleh kernel Linux sebagai file yang berlubang ("holes").
- SOLUSI RESMI: Di AL2023, file swap WAJIB dialokasikan menggunakan `dd` untuk 
  memastikan seluruh blok data benar-benar ditulis secara contiguous:
```bash
sudo dd if=/dev/zero of=/swapfile bs=128M count=32 status=progress
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
```

### 11.3 PAKET MINIMALIS, DEPENDENSI WAJIB & ANALISIS ERROR KONFLIK CURL-MINIMAL VS CURL

Image standar Amazon Linux 2023 (AL2023) dirancang oleh AWS dengan prinsip "minimal footprint" 
untuk memangkas surface area kerentanan keamanan serta mempercepat durasi booting EC2. 
Hal ini menimbulkan perbedaan signifikan dibandingkan distribusi tradisional (AL2, CentOS 7, 
atau Ubuntu) terkait ketersediaan paket bawaan.

#### A. Matriks Status Paket Bawaan AL2023 vs Prasyarat Wazuh:

```text
-----------------------------------------------------------------------------
```

   Nama Paket       | Status Bawaan AL2023  | Keterangan & Tindakan
```bash
-----------------------------------------------------------------------------
curl             | SUDAH TERPASANG       | Terpasang via package 'curl-minimal'.
```

                    |                       | Binary '/usr/bin/curl' sudah aktif.
                    |                       | JANGAN instal 'curl' tanpa flag khusus!
```text
tar              | SUDAH TERPASANG       | Pre-installed di AL2023 AMI.
gzip             | SUDAH TERPASANG       | Pre-installed di AL2023 AMI.
unzip            | SUDAH TERPASANG       | Pre-installed di AL2023 AMI.
```

   coreutils        | SUDAH TERPASANG       | Pre-installed di AL2023 AMI.
   findutils        | SUDAH TERPASANG       | Pre-installed di AL2023 AMI.
   jq               | SUDAH TERPASANG       | Pre-installed di AL2023 rilis baru.
   libxcrypt-compat | BELUM TERPASANG       | WAJIB DIINSTAL MANUAL (Dependensi Kritis).
```text
-----------------------------------------------------------------------------
```

B. Studi Kasus & Bedah Teknis Error: "Conflict with curl-minimal"
   1. Pesan Error yang Muncul:
```text
Error: Problem: problem with installed package curl-minimal-8.17.0-1.amzn2023.0.3.x86_64
```

       - package curl-minimal-... from @System conflicts with curl provided by curl-...
       - conflicting requests
      (try to add '--allowerasing' to command line to replace conflicting packages)

   2. Akar Penyebab Teknis (Root Cause Analysis):
      a. Arsitektur Paket curl-minimal:
         AWS mengemas `curl-minimal` yang hanya memiliki fitur esensial HTTP/HTTPS dasar 
         tanpa protokol warisan/jarang terpakai (seperti LDAP, RTMP, brotli, dll).
      b. Deklarasi Konflik RPM (RPM Mutual Exclusion):
         Di dalam metadata RPM spec file, paket `curl-minimal` mendeklarasikan tag 
         `Conflicts: curl` dan paket `curl` standar mendeklarasikan tag `Conflicts: curl-minimal`.
      c. Mekanisme Safe-Resolution DNF:
         Package manager DNF secara default memblokir operasi swap paket yang sedang 
         terpasang di `@System` jika ada konflik langsung, demi mencegah penghapusan 
         dependensi sistem yang tidak disengaja.
      d. Dampak Fatal pada EC2 Cloud-Init / User Data:
         Script User Data EC2 yang menggunakan `set -e` (hentikan script jika ada error) 
         akan langsung GAGAL (aborted) saat baris `dnf install -y curl ...` mengalami konflik. 
         Akibatnya, proses unduh installer Wazuh tidak pernah dieksekusi dan instance 
         berakhir dalam kondisi kosong tanpa Wazuh.

#### C. Solusi & Rekomendasi Eksekusi:

   - Solusi 1 (Sangat Direkomendasikan - Paling Cepat & Bersih):
     Cukup instal dependensi yang memang belum ada di AL2023:
```bash
sudo dnf install -y libxcrypt-compat
```

     Atau jika ingin mendaftarkan semua tool tanpa memicu konflik:
```bash
sudo dnf install -y tar gzip unzip jq coreutils findutils libxcrypt-compat
```

   - Solusi 2 (Jika Benar-Benar Membutuhkan Paket curl Lengkap):
     Gunakan flag `--allowerasing` agar DNF diizinkan mengganti `curl-minimal` dengan `curl`:
```bash
sudo dnf install -y --allowerasing curl tar gzip unzip jq coreutils findutils libxcrypt-compat
```

#### D. Mengapa `libxcrypt-compat` Sangat Kritis untuk Wazuh di AL2023?

   - AL2023 mengadopsi glibc modern yang secara default memutus kompatibilitas libcrypt versi lama 
     (berpindah dari libcrypt.so.1 ke libcrypt.so.2).
   - Paket `libxcrypt-compat` menyediakan shared object `libcrypt.so.1`.
   - Tanpa library ini, modul hash password OpenSearch Indexer, binary autentikasi Wazuh Server, 
     dan script internal Wazuh akan mengalami error:
     `error while loading shared libraries: libcrypt.so.1: cannot open shared object file`.

### 11.4 SELINUX, CGROUPS V2 & SYSTEM-WIDE CRYPTO POLICIES

#### A. Status SELinux di AL2023:

   - AL2023 hadir dengan SELinux secara default dalam mode `permissive`.
   - Cek status: `getenforce`
   - Dalam mode permissive, event pelanggaran dicatat di log audit tanpa memblokir 
     proses Wazuh.
   - PENTING: Jika kebijakan kepatuhan internal mewajibkan SELinux disetel ke `enforcing`, 
     Anda harus memberikan label port SELinux untuk Wazuh:
```bash
sudo dnf install -y policycoreutils-python-utils
sudo semanage port -a -t unreserved_port_t -p tcp 1514
sudo semanage port -a -t unreserved_port_t -p 1515
sudo semanage port -a -t unreserved_port_t -p 55000
```

#### B. Adopsi CGroups v2 (Unified Hierarchy):

   - AL2023 berjalan murni pada CGroups v2 (`/sys/fs/cgroup`).
   - Wazuh Manager dan Indexer dapat memanfaatkan Cgroup v2 secara optimal untuk 
     pembatasan memori (`MemoryMax`, `MemoryHigh`) dan CPU quota tanpa konflik hierarchy v1.

#### C. System-Wide Crypto Policies:

   - AL2023 menerapkan kebijakan kriptografi `DEFAULT` yang menonaktifkan TLS 1.0, 
     TLS 1.1, 3DES, dan kunci RSA di bawah 2048-bit.
   - Pastikan sertifikat SSL Wazuh Dashboard dan API menggunakan kunci RSA minimal 2048-bit 
     atau ECC secp256r1/secp384r1 agar tidak ditolak saat proses handshake internal.

### 11.5 OPTIMASI WAZUH PADA AWS GRAVITON (ARM64) DENGAN AL2023

Kombinasi Amazon Linux 2023 dan AWS Graviton (prosesor Graviton 3 / Graviton 4) 
merupakan arsitektur paling efisien biaya dan performa tinggi untuk Wazuh:
- Arsitektur Kompatibel: Wazuh Indexer (berbasis OpenSearch Java 17) dan Wazuh Manager 
  memiliki binary native 64-bit ARM (`aarch64`).
- Efisiensi Biaya: Tipe instance `m7g.xlarge` (4 vCPU, 16 GiB RAM) atau `c7g.xlarge` 
  memiliki harga ~20% lebih murah per jam dibanding Intel/AMD x86_64 (`m6i`/`m6a`).
- Throughput Komputasi: Core Graviton adalah dedicated physical core (bukan SMT / hyperthread), 
  sehingga pemrosesan regex rule di `ossec-analysisd` berjalan tanpa degradasi cache contention.
- SSM Parameter AMI AL2023 Graviton:
```bash
aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  --query 'Parameter.Value' --output text
```

### 11.6 NATIVE AWS SYSTEMS MANAGER (SSM) & ZERO SSH KEY ACCESS

Keunggulan utama AL2023 di AWS adalah agen SSM (`amazon-ssm-agent`) sudah terpasang 
dan langsung aktif saat pertama kali booting:
1. Menghilangkan File Kunci Private (.pem):
   - Tidak perlu membuat atau mendistribusikan SSH key pair untuk tim DevOps/SecOps.
   - Mengeliminasi risiko kebocoran file `.pem` administrator.
2. Port 22 SSH Ditutup Sepenuhnya:
   - Security Group EC2 tidak perlu membuka port 22 ke IP mana pun (Zero Inbound SSH).
   - Akses terminal dilakukan melalui tunnel terenkripsi AWS SSM Session Manager:
```bash
aws ssm start-session --target i-0123456789abcdef0
```

3. Integrasi IAM Role:
   - Pasang IAM Managed Policy `AmazonSSMManagedInstanceCore` pada IAM Role instance EC2.
   - Akses audit log sesi tercatat lengkap di AWS CloudTrail dan AWS S3.

### 11.7 CHEAT SHEET PEMELIHARAAN & TROUBLESHOOTING KHUSUS AL2023

- Cek pembaruan khusus keamanan:
```bash
sudo dnf check-update --security
```

- Terapkan hanya patch keamanan (tanpa mengupgrade versi package non-security):
```bash
sudo dnf update-minimal --security -y
```

- Cek status swap aktif:
    swapon --show
```text
free -h
```

- Verifikasi repository Wazuh di DNF:
```bash
dnf repolist -v | grep -i wazuh
```

- Membersihkan metadata repository DNF jika terjadi error checksum GPG:
```bash
sudo dnf clean all && sudo dnf makecache
```

- Menangani error konflik paket 'curl-minimal' vs 'curl' saat dnf install:
```bash
# Solusi 1 (Disarankan): Cukup pasang dependensi yang kurang
sudo dnf install -y libxcrypt-compat
# Solusi 2: Izinkan penggantian curl-minimal dengan curl penuh
sudo dnf install -y --allowerasing curl
```

- Cek log boot User-Data saat deployment pertama:
```bash
sudo tail -n 100 /var/log/user-data.log
```

## 12. PANDUAN & TROUBLESHOOTING AKSES WAZUH DASHBOARD VIA SSH TUNNEL & BASTION HOST

### 12.1 ANALISIS PENYEBAB GAGAL AKSES PORT 443 VIA SSH TUNNEL

Akses Web UI Wazuh Dashboard (Port 443 HTTPS) yang berada di Private Subnet sering kali 
diakses menggunakan SSH Tunnel melalui Bastion Host (Jump Host). 
Secara teknis, port 443 SANGAT BISA diakses melalui SSH Tunneling.

Jika akses port 443 gagal atau koneksi ditolak/reset/timeout, kegagalan tersebut 
hampir selalu disebabkan oleh salah satu dari lima faktor berikut:
1. Port lokal yang digunakan bernilai < 1024 (Privileged Port) tanpa izin root/sudo.
2. Akses via browser menggunakan protokol HTTP (`http://`), bukan HTTPS (`https://`).
3. Security Group AWS Wazuh EC2 belum mengizinkan Inbound TCP 443 dari Bastion Host.
4. Konfigurasi SSH Daemon di Bastion Host mematikan fitur `AllowTcpForwarding`.
5. Service Wazuh Dashboard belum berjalan atau binding ke interface yang salah.

### 12.2 PORT BINDING LOKAL: PRIVILEGED PORT (< 1024) VS NON-PRIVILEGED (> 1024)

- Masalah:
  Banyak administrator mencoba menjalankan perintah forward langsung ke port 443 lokal:
    ssh -i key.pem -L 443:<IP_PRIVATE_WAZUH>:443 user@<BASTION_IP>
  Pada sistem operasi Unix-like (Linux & macOS), seluruh port di bawah 1024 adalah 
  "Privileged Ports" yang hanya boleh dibuka oleh user root/superuser.
  Jika dijalankan oleh user biasa tanpa `sudo`, SSH lokal akan gagal melakukan binding:
    "bind [127.0.0.1]:443: Permission denied"
    atau "Privileged ports can only be forwarded by root."
- Solusi:
  Lakukan pemetaan (mapping) port lokal ke port non-privileged di atas 1024 (misal: 8443 atau 10443):
    ssh -i /path/to/bastion-key.pem -N -L 8443:<IP_PRIVATE_WAZUH>:443 ec2-user@<IP_PUBLIK_BASTION>
  Setelah tunnel aktif, akses di browser melalui: `https://localhost:8443`

### 12.3 PENANGANAN PROTOKOL HTTPS VS HTTP & PERINGATAN SSL SELF-SIGNED

- Masalah HTTP vs HTTPS:
  Wazuh Dashboard secara bawaan dikonfigurasi menggunakan sertifikat SSL/TLS internal (HTTPS).
  Jika di address bar browser Anda mengetik `localhost:8443` atau `http://localhost:8443`, 
  koneksi akan langsung di-reset atau browser menampilkan error:
    "ERR_EMPTY_RESPONSE"
    atau "Client sent an HTTP request to an HTTPS server"
- Solusi:
  Wajib mengetikkan awalan protokol `https://` secara eksplisit:
```text
https://localhost:8443   (atau https://127.0.0.1:8443)
```

- Penanganan Peringatan SSL Self-Signed:
  Browser modern akan memunculkan layar peringatan keamanan "Your connection is not private".
  Hal ini normal karena sertifikat dibuat oleh root CA internal Wazuh installer.
```text
Langkah: Klik "Advanced" (Lanjutan) -> Klik "Proceed to localhost (unsafe)" 
```

  untuk masuk ke halaman login dashboard.

### 12.4 KONFIGURASI AWS SECURITY GROUP INBOUND/OUTBOUND (BASTION KE WAZUH EC2)

Dalam arsitektur AWS VPC:
- Bastion Host bertindak sebagai pemrakarsa koneksi keluar menuju IP Private Wazuh EC2.
- Aturan Inbound Security Group Wazuh EC2 (`sg-wazuh-siem`):
  Pastikan ada aturan Inbound Rule yang mengizinkan port 443 dari Bastion:
  * Type        : HTTPS (TCP)
  * Port Range  : 443
  * Source      : Security Group ID milik Bastion (`sg-bastion-xxxx`) 
                  ATAU IP Private Bastion Host (`10.x.x.x/32`).
```text
PERHATIAN: Jika Security Group Wazuh hanya membuka port 443 ke IP publik admin/kantor, 
```

  maka koneksi internal dari Bastion Host di dalam VPC akan di-DROP oleh firewall AWS, 
  menyebabkan status "Connection Timed Out".
- Aturan Outbound Security Group Bastion Host:
  Pastikan Outbound SG Bastion mengizinkan trafik TCP 443 menuju ke IP private Wazuh 
  (secara default, Outbound AWS SG mengizinkan `All traffic 0.0.0.0/0`).

### 12.5 KONFIGURASI ALLOWTCPFORWARDING PADA SSH DAEMON BASTION

Pada server Bastion yang diterapkan security hardening, opsi TCP Forwarding pada OpenSSH 
sering kali dinonaktifkan secara sengaja.
- Gejala Error:
  SSH tunnel langsung ditutup saat browser mencoba membuka halaman dengan pesan:
    "channel 2: open failed: administratively prohibited: open failed"
- Solusi di Sisi Bastion Host:
  1. Periksa file konfigurasi SSH Daemon di Bastion:
```bash
sudo grep -i AllowTcpForwarding /etc/ssh/sshd_config
```

  2. Pastikan nilainya diizinkan:
     AllowTcpForwarding yes
  3. Restart service SSH daemon di Bastion:
```bash
sudo systemctl restart sshd
```

### 12.6 SINTAKS PRAKTIS: LOCAL PORT FORWARDING, PROXYJUMP & AWS SSM PORT FORWARDING

--- METODE A: LOCAL PORT FORWARDING STANDAR VIA BASTION (PALING UMUM) ---
Jalankan dari terminal komputer lokal Anda:
  ssh -i ~/.ssh/my-bastion-key.pem \
      -N -f \
      -L 8443:<IP_PRIVATE_WAZUH>:443 \
      ec2-user@<IP_PUBLIK_BASTION>

Keterangan Flag:
```text
-N : Hanya membuat tunnel koneksi port tanpa membuka shell interaktif.
-f : Menjalankan proses SSH di latar belakang (background process).
```

  -L 8443:<IP_PRIVATE>:443 : Memetakan port lokal 8443 ke port 443 instance Wazuh.
Buka browser: https://localhost:8443

--- METODE B: SSH PROXYJUMP (-J) DENGAN DIRECT LOCALHOST FORWARDING ---
Gunakan jika file private key Wazuh tersimpan di komputer lokal dan Anda tidak ingin 
menaruh private key tersebut di dalam Bastion Host:
  ssh -i ~/.ssh/my-wazuh-key.pem \
      -J ec2-user@<IP_PUBLIK_BASTION> \
      -N -L 8443:127.0.0.1:443 \
      ec2-user@<IP_PRIVATE_WAZUH>
Buka browser: https://localhost:8443

--- METODE C: AWS SYSTEMS MANAGER (SSM) PORT FORWARDING (TANPA BASTION & ZERO SSH KEY) ---
Jika instance EC2 Wazuh dipasangi IAM Role dengan policy 'AmazonSSMManagedInstanceCore', 
Anda DAPAT MEMBUKA TUNNEL LANGSUNG DARI TERMINAL LOKAL TANPA BASTION SAMA SEKALI 
dan tanpa membuka port 22 ataupun 443 ke internet:
```bash
aws ssm start-session \
  --target <INSTANCE_ID_WAZUH> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["443"],"localPortNumber":["8443"]}'
```

Buka browser: https://localhost:8443

### 12.7 PANDUAN PRAKTIS SSH TUNNELING MENGGUNAKAN PUTTY (WINDOWS GUI)

Jika administrator atau tim operasional menggunakan workstation Windows dan aplikasi 
PuTTY GUI (bukan CLI OpenSSH), berikut langkah konfigurasi lengkapnya:

1. Persiapan Kunci Kriptografi (.pem ke .ppk):
   - PuTTY tidak mendukung format file key pair `.pem` AWS secara langsung.
   - Buka aplikasi 'PuTTYgen' (bawaan installer PuTTY).
   - Klik tombol 'Load' -> ubah filter file ke 'All Files (*.*)' -> pilih file `.pem` Bastion.
   - Klik tombol 'Save private key' (bisa abaikan passphrase jika diinginkan).
   - Simpan dengan ekstensi `.ppk` (misal: `bastion-key.ppk`).

2. Konfigurasi Sesi Bastion Host di PuTTY:
   - Buka aplikasi 'PuTTY'.
   - Masuk ke kategori 'Session' (panel navigasi kiri paling atas):
     * Host Name (or IP address): Masukkan IP Publik Bastion (atau `ec2-user@<IP_PUBLIK_BASTION>`).
     * Port: 22
     * Connection type: SSH
   - Masukkan kunci privat:
     * Navigasi ke 'Connection' -> 'SSH' -> 'Auth' -> 'Credentials' (atau cukup 'Auth' pada PuTTY lama).
     * Pada field 'Private key file for authentication', klik 'Browse...' lalu pilih file `bastion-key.ppk`.

3. Konfigurasi Port Forwarding (SSH Tunnel):
   - Di panel navigasi kiri, masuk ke 'Connection' -> 'SSH' -> 'Tunnels'.
   - Di bagian 'Add new forwarded port', isi parameter berikut:
     * Source port : 8443 (Gunakan port non-privileged > 1024 sesuai Bab 12.2).
     * Destination : <IP_PRIVATE_WAZUH>:443 (Contoh: 10.0.1.50:443).
     * Radio Button: Pilih 'Local' dan 'Auto' (atau IPv4).
   - PENTING: Klik tombol 'Add'.
   - Pastikan entri mapping muncul di kotak daftar 'Forwarded ports':
     L8443    <IP_PRIVATE_WAZUH>:443

4. Menyimpan Sesi (Saved Sessions):
   - Kembali ke kategori 'Session' di panel kiri atas.
   - Di kolom 'Saved Sessions', ketik nama sesi (misal: 'Wazuh-Bastion-Tunnel').
   - Klik tombol 'Save' agar konfigurasi tersimpan permanen dan tidak perlu diulang.

5. Membuka Tunnel & Mengakses Wazuh Dashboard:
   - Klik tombol 'Open' di bagian bawah PuTTY untuk memulai koneksi SSH.
   - Jika muncul peringatan host key fingerprint baru, klik 'Accept'.
   - Masukkan username login jika diminta (misal: `ec2-user` atau `ubuntu`).
   - PENTING: Biarkan jendela terminal PuTTY tetap terbuka atau di-minimize (jangan di-close).
   - Buka web browser di workstation Windows Anda dan akses URL:
```text
https://localhost:8443   (atau https://127.0.0.1:8443)
```

   - Pada layar peringatan sertifikat SSL self-signed ("Your connection is not private"), 
     klik 'Advanced' -> 'Proceed to localhost (unsafe)'.
   - Halaman login Wazuh Dashboard akan terbuka. Masukkan username 'admin' dan password Anda.

## 13. CATATAN KHUSUS AUTENTIKASI REGISTRASI AGENT (WAZUH_REGISTRATION_PASSWORD & AUTHD.PASS)

### 13.1 ANALISIS & ASAL-USUL VARIABEL WAZUH_REGISTRATION_PASSWORD

Pada panduan instalasi agent ('wazuh_agent_amazon_linux_install_guide.txt'), terdapat 
baris konfigurasi opsional:
```text
WAZUH_REGISTRATION_PASSWORD='PasswordRahasiaWazuh123'
```

PENTING DIPAHAMI:
1. String 'PasswordRahasiaWazuh123' HANYALAH CONTOH (DUMMY / PLACEHOLDER).
2. Nilai sebenarnya BUKAN password default Wazuh, BUKAN password user Linux ('ec2-user'), 
   dan BUKAN password login web dashboard Wazuh ('admin').
3. Nilai ini murni berasal dari file autentikasi service daemon registrasi (wazuh-authd) 
   di server WAZUH MANAGER, yaitu:
```text
/var/ossec/etc/authd.pass
```

### 13.2 HASIL INVESTIGASI LAPANGAN: MENGAPA MUNCUL 'NO SUCH FILE OR DIRECTORY'

Saat dilakukan pengujian langsung pada terminal server Wazuh Manager ('wazuh-tree-prod'):
  [ec2-user@wazuh-tree-prod ~]$ sudo cat /var/ossec/etc/authd.pass
```text
cat: /var/ossec/etc/authd.pass: No such file or directory
```

- Makna & Kesimpulan Hasil Tersebut:
  1. File 'authd.pass' TIDAK DIBUAT secara default saat Wazuh Manager selesai diinstal.
  2. Ketiadaan file ini menandakan bahwa layanan daemon 'wazuh-authd' di Wazuh Manager 
     Anda beroperasi dalam mode DEFAULT (Open Registration via Port TCP 1515).
  3. Wazuh Manager Anda saat ini TIDAK MENERAPKAN dan TIDAK MEMERLUKAN password autentikasi 
     apapun dari agent yang mendaftar.

- Catatan Teknis Error Permission Denied:
  Perintah awal `[ec2-user@wazuh-tree-prod ~]$ /var/ossec/etc/authd.pass` menghasilkan 
  pesan "Permission denied" karena shell Linux mencoba mengeksekusi path file tersebut 
  sebagai binary program / skrip yang dapat dijalankan (karena tidak didahului command 
  seperti 'cat' atau 'less'). Setelah dieksekusi dengan `sudo cat /var/ossec/etc/authd.pass`, 
  terkonfirmasi bahwa file tersebut memang belum ada di server Manager.

### 13.3 MATRIKS KEPUTUSAN: KAPAN VARIABEL PASSWORD WAJIB DIPAKAI VS DIHILANGKAN

| KONDISI DI WAZUH MANAGER | STATUS AUTHD | TINDAKAN DI SISI AGENT (AMAZON LINUX) |
| :--- | :--- | :--- |
| File /var/ossec/etc/authd.pass TIDAK | Buka / Bebas | HAPUS / ABAIKAN parameter |
| ADA (No such file or directory) | (Default) | WAZUH_REGISTRATION_PASSWORD. |
| [KONDISI SERVER ANDA SAAT INI] |  | Gunakan Langkah 4.3 (Metode Standar). |

File /var/ossec/etc/authd.pass ADA    | Terproteksi   | WAJIB menyertakan:
dan berisi string kata sandi          | Password      | WAZUH_REGISTRATION_PASSWORD='<ISI_FILE>'
                                      |               | Nilai harus sama persis dengan di file.

---

### 13.4 SINTAKS FINAL REKOMENDASI EKSEKUSI DI AGENT AMAZON LINUX

Karena pada server Wazuh Manager Anda file '/var/ossec/etc/authd.pass' TIDAK ADA, 
maka eksekusi instalasi di instance target EC2 adalah sebagai berikut:

A. Pada Target 1: Amazon Linux 2 (Contoh Host: hrptrsapprd)
   Ganti <IP_PRIVATE_WAZUH_MANAGER> dengan IP VPC Private dari server wazuh-tree-prod:

```bash
sudo WAZUH_MANAGER='<IP_PRIVATE_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='production,hr-payroll' \
     WAZUH_AGENT_NAME='hrptrsapprd' \
     yum install -y wazuh-agent

# Aktifkan dan jalankan service:
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

B. Pada Target 2: Amazon Linux 2023 (Contoh Host: ip-172-1-12-178)
```bash
sudo WAZUH_MANAGER='<IP_PRIVATE_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='production,backend-vpc' \
     WAZUH_AGENT_NAME='ip-172-1-12-178' \
     dnf install -y wazuh-agent

# Aktifkan dan jalankan service:
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

### 13.5 PROSEDUR PENGERASAN (HARDENING): CARA MENGAKTIFKAN AUTHD.PASS DI SISI MANAGER

Jika di masa mendatang tim Information Security (InfoSec) atau Administrator Anda 
mewajibkan setiap agent harus diautentikasi dengan password registrasi agar instance 
liar di VPC tidak bisa mendaftarkan diri secara ilegal ke Manager:

1. Di Server Wazuh Manager ('wazuh-tree-prod'):
```bash
# Buat string password kuat (contoh: P@ssw0rdProdWazuh2026!)
echo "P@ssw0rdProdWazuh2026!" | sudo tee /var/ossec/etc/authd.pass
sudo chmod 640 /var/ossec/etc/authd.pass
sudo chown root:wazuh /var/ossec/etc/authd.pass
sudo systemctl restart wazuh-manager
```

2. Di Sisi Seluruh Agent Baru yang Akan Diinstal:
   Setiap kali instalasi agent baru, parameter WAZUH_REGISTRATION_PASSWORD wajib disisipkan:
```bash
sudo WAZUH_MANAGER='<IP_PRIVATE_WAZUH_MANAGER>' \
     WAZUH_REGISTRATION_PASSWORD='P@ssw0rdProdWazuh2026!' \
     WAZUH_AGENT_GROUP='production,hr-payroll' \
     WAZUH_AGENT_NAME='hrptrsapprd' \
     yum install -y wazuh-agent
```

3. Catatan Penting Saat Mengaktifkan Password:
   - Agent yang sudah terdaftar sebelumnya (yang sudah memiliki key di '/var/ossec/etc/client.keys') 
     TIDAK AKAN terputus, karena password authd HANYA diperiksa saat pendaftaran awal (Port 1515).
   - Setelah pendaftaran awal sukses, komunikasi rutin beralih menggunakan symmetric key di Port 1514.

## 14. PANDUAN & TROUBLESHOOTING AWS APPLICATION LOAD BALANCER (ALB) UNTUK WAZUH

### 14.1 ANALISIS MASALAH UNHEALTHY TARGET: HTTP 302 FOUND VS SUCCESS CODES

Dalam implementasi AWS Application Load Balancer (ALB) di depan Wazuh Dashboard 
(OpenSearch Dashboards), sering dijumpai status Target Group berstatus 'Unhealthy' 
dengan pesan:
  "Health checks failed with these codes: [302]"

Penyebab Utama:
1. Arsitektur Wazuh Dashboard menerapkan autentikasi berbasis cookie sesi. Request GET 
   apapun yang datang tanpa session cookie (seperti probe health check ALB) akan 
   otomatis di-redirect oleh server dengan kode HTTP '302 Found' menuju portal login.
2. Respons 302 tersebut adalah respon NORMAL dan SEHAT dari Wazuh Dashboard.
3. Secara default, AWS Target Group hanya menetapkan angka '200' pada parameter 
   'Success codes'. Akibatnya, ALB menganggap respon redirect 302 sebagai target gagal/unhealthy.

### 14.2 MENGAPA PATH /app/login TETAP MENGEMBALIKAN HTTP 302

- Wazuh Dashboard adalah aplikasi Single Page Application (SPA). Endpoint '/app/login' 
  melakukan evaluasi parameter URL (?nextUrl=...) dan internal routing redirect sebelum 
  halaman login selesai di-render.
- Mengubah path ke '/app/login' TIDAK AKAN menyelesaikan masalah jika nilai 
  'Success codes' pada Target Group tetap dibiarkan '200'.

### 14.3 PROSEDUR PERBAIKAN KONFIGURASI TARGET GROUP (SUCCESS CODES 200,302)

1. Masuk ke EC2 Console -> Target Groups -> Pilih Target Group Wazuh ('trees-wazuh-prod-tg').
2. Buka tab 'Health checks' -> Klik 'Edit'.
3. Ubah parameter berikut:
   - Health check path : '/' (kembalikan ke root agar fleksibel saat upgrade versi)
   - Success codes     : '200,302' (atau rentang '200-399')
   - Healthy threshold : 2 (default 5, ubah ke 2 agar status cepat pulih)
   - Interval          : 10 seconds (default 30s)
4. Klik 'Save changes'. Target akan berubah menjadi HEALTHY dalam waktu ~20 detik.

### 14.4 KONFIGURASI KRITIS ALB: STICKINESS, IDLE TIMEOUT, DAN SECURITY GROUP

1. Target Group Stickiness:
   Wajib diaktifkan (Duration-based: 1 hari) pada tab Attributes Target Group 
   agar pengguna tidak mengalami logout paksa saat browsing log atau refresh tab.
2. ALB Idle Timeout:
   Naikkan nilai Idle Timeout pada Attributes ALB dari 60 detik menjadi 120-300 detik 
   agar query agregasi log berat di Wazuh Indexer tidak terkena error 504 Gateway Timeout.
3. Security Group Chain:
   - Security Group EC2 Wazuh HANYA boleh mengizinkan inbound Port 443 dari 
     Security Group ID milik ALB, bukan dari 0.0.0.0/0.
4. SSL Handshake Target Group:
   ALB tidak memvalidasi validitas sertifikat backend. Protokol Target HTTPS 443 
   berfungsi normal meskipun Wazuh EC2 menggunakan self-signed SSL bawaan.

## AKHIR KETERANGAN TAMBAHAN
