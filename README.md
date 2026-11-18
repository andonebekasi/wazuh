# Wazuh SIEM & XDR Documentation Hub

Direktori ini berisi seluruh dokumentasi, panduan arsitektur, instalasi, konfigurasi, integrasi cloud, use case security, serta *troubleshooting runbooks* untuk **Wazuh SIEM & XDR**.

---

## 📑 Daftar Dokumen Berdasarkan Kategori

### 1. Master Guide & Dokumen Utama
- [Wazuh_SIEM_XDR_Full_Detail_Master_Guide.pdf](Wazuh_SIEM_XDR_Full_Detail_Master_Guide.pdf)  
  *Dokumen master panduan lengkap Wazuh SIEM & XDR (Format PDF).*
- [wazuh_full_detail_guide.pdf](wazuh_full_detail_guide.pdf)  
  *Dokumen referensi teknis komprehensif Wazuh (Format PDF).*
- [wazuh_aws_ec2_install_guide.md](wazuh_aws_ec2_install_guide.md)  
  *Panduan lengkap instalasi & konfigurasi Wazuh All-in-One / Distributed di AWS EC2 (Amazon Linux 2023 & Ubuntu), Security Group, Golden AMI, dan user-data.*
- [wazuh_dashboard_usage_guide.md](wazuh_dashboard_usage_guide.md)  
  *Panduan navigasi, visualisasi, dan pemanfaatan Wazuh Dashboard (FIM, Vulnerabilities, Compliance, MITRE ATT&CK).*
- [wazuh_keterangan_tambahan.md](wazuh_keterangan_tambahan.md)  
  *Catatan operasional tambahan: formula sizing storage EPS/harian, tuning retention indexer, hardening, dan audit checklist.*

---

### 2. Skrip Otomasi Bash (Installer v4.14)
- [install_wazuh_server.sh](install_wazuh_server.sh)  
  *Skrip otomasi Bash universal instalasi Wazuh Server v4.14 All-in-One (Ubuntu, Debian, RHEL, Oracle Linux, AlmaLinux, Amazon Linux 2 & 2023).*
- [install_wazuh_agent.sh](install_wazuh_agent.sh)  
  *Skrip otomasi Bash universal instalasi & enrollment Wazuh Agent v4.14 multi-OS.*
- [wazuh_scripts_guide.md](wazuh_scripts_guide.md)  
  *Panduan lengkap penggunaan skrip otomasi server dan agent, opsi CLI flag, port firewall, dan troubleshooting.*

#### ⚡ Quick Install via `curl | bash` (One-Liner):

Skrip otomasi ini mendukung instalasi instan pada **Ubuntu, Debian, RHEL, CentOS Stream, AlmaLinux, Rocky Linux, Oracle Linux, serta Amazon Linux 2 & 2023** tanpa perlu melakukan clone Git repository:

**A. Install Wazuh Server v4.14 All-in-One:**
```bash
# 1. Instalasi Standar All-in-One:
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_server.sh | sudo bash

# 2. Instalasi + Otomatis Membuka Port Firewall (1514, 1515, 443, 55000):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_server.sh | sudo bash -s -- --open-firewall

# 3. Instalasi pada VM Lab/Testing dengan RAM Terbatas (< 4 GB):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_server.sh | sudo bash -s -- --force --open-firewall
```

**B. Install & Enroll Wazuh Agent v4.14:**
```bash
# 1. Instalasi Cepat (Otomatis hostname & grup 'default'):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m <IP_WAZUH_MANAGER>

# 2. Instalasi Kustom Nama Agent, Multi-Grup & Mode Non-Interaktif:
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m 172.31.10.50 -n "web-prod-01" -g "production,web" -y

# 3. Instalasi dengan Registration Password (authd.pass):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m 172.31.10.50 -p "PasswordRahasia123"
```

> [!TIP]
> Parameter `-s --` digunakan agar bash membaca skrip dari stdin dan meneruskan argumen setelah tanda `--` ke dalam skrip installer.  
> Panduan lengkap parameter CLI, konfigurasi firewall, cloud-init AWS, dan troubleshooting tersedia di **[wazuh_scripts_guide.md](wazuh_scripts_guide.md)**.

---

### 3. Instalasi & Upgrade Wazuh Server
- [wazuh_server_almalinux_install_guide.md](wazuh_server_almalinux_install_guide.md)  
  *Panduan instalasi Wazuh Server (Manager, Indexer, Dashboard) di AlmaLinux.*
- [wazuh_server_upgrade_guide.md](wazuh_server_upgrade_guide.md)  
  *Prosedur step-by-step upgrade Wazuh Server dan komponen pendukung tanpa kehilangan data.*

---

### 4. Panduan Instalasi Wazuh Agent
- [wazuh_agent_install_guide.md](wazuh_agent_install_guide.md)  
  *Panduan instalasi standar Wazuh Agent dan pendaftaran ke Wazuh Manager.*
- [wazuh_agent_amazon_linux_install_guide.md](wazuh_agent_amazon_linux_install_guide.md)  
  *Panduan instalasi dan deployment Wazuh Agent khusus Amazon Linux 2 (AL2) dan Amazon Linux 2023 (AL2023).*
- [wazuh_agent_almalinux_install_guide.md](wazuh_agent_almalinux_install_guide.md)  
  *Panduan instalasi Wazuh Agent di AlmaLinux.*
- [keterangan_fresh_install_wazuh_agent.md](keterangan_fresh_install_wazuh_agent.md)  
  *Panduan fresh install Wazuh Agent dan penyesuaian versi agar kompatibel dengan server.*
- [keterangan_downgrade_wazuh_client.md](keterangan_downgrade_wazuh_client.md)  
  *Panduan downgrade paket Wazuh Agent ke versi yang sesuai (aturan: versi agent <= versi manager).*

---

### 5. Integrasi Load Balancer (Cloud)
- [keterangan_tambahan_aws_lb.md](keterangan_tambahan_aws_lb.md)  
  *Panduan konfigurasi AWS Application Load Balancer (ALB) dan Target Group untuk Wazuh Dashboard (penanganan HTTP 302 redirect).*
- [keterangan_tambahan_oci_lb.md](keterangan_tambahan_oci_lb.md)  
  *Panduan konfigurasi Oracle Cloud Infrastructure (OCI) Load Balancer untuk Wazuh Dashboard (penanganan issue TLS/HTTPS 443 & backend health check).*

---

### 6. Security Rules, Alerts & Use Cases
- [wazuh_failed_login_alert_and_simulation_guide.md](wazuh_failed_login_alert_and_simulation_guide.md)  
  *Panduan pembuatan alert gagal login di Wazuh Dashboard, custom rules, simulasi serangan brute force, dan verifikasi.*
- [wazuh_failed_login_usecases.md](wazuh_failed_login_usecases.md)  
  *Daftar matriks use cases deteksi insiden keamanan terkait autentikasi (SOC Guide).*

---

### 7. Troubleshooting Runbooks
- [troubleshoot_wazuh.md](troubleshoot_wazuh.md)  
  *Kompilasi umum solusi kendala teknis Wazuh Agent dan Wazuh Server.*
- [troubleshoot_wazuh_agent.md](troubleshoot_wazuh_agent.md)  
  *Troubleshooting spesifik service dan koneksi Wazuh Agent.*
- [troubleshoot_wazuh_agent_server.md](troubleshoot_wazuh_agent_server.md)  
  *Troubleshooting komunikasi jaringan, port firewall, dan autentikasi antar Agent dan Server.*
- [troubleshoot_wazuh_client_syscollector.md](troubleshoot_wazuh_client_syscollector.md)  
  *Solusi penanganan error modul Syscollector (`No such tag 'users'`).*
- [troubleshoot_rename_wazuh_agent.md](troubleshoot_rename_wazuh_agent.md)  
  *Panduan mengganti nama (rename) Wazuh Agent tanpa merusak registrasi `client.keys`.*
- [keterangan_tambahan_agent_baru_tidak_muncul_dashboard.md](keterangan_tambahan_agent_baru_tidak_muncul_dashboard.md)  
  *Diagnosa dan solusi ketika service agent sudah running namun belum muncul di Wazuh Dashboard.*
# wazuh
