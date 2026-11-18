# Wazuh SIEM & XDR Documentation & Automation Hub

> **Dibuat oleh / Created by:** [Andi Pangeran](https://github.com/andonebekasi)

🌐 **Pilih Bahasa / Language:**
- [🇮🇩 Bahasa Indonesia (Default)](#-bahasa-indonesia)
- [🇬🇧 English](#-english)

---

## 🇮🇩 Bahasa Indonesia

Hub dokumentasi komprehensif, panduan arsitektur, skrip instalasi otomatis, konfigurasi *cloud*, *use cases* keamanan, serta kumpulan *runbook troubleshooting* untuk **Wazuh SIEM & XDR**.

### 👤 Keterangan Pembuat
- **Author / Pembuat:** Andi Pangeran
- **Repository:** [https://github.com/andonebekasi/wazuh](https://github.com/andonebekasi/wazuh)

---

### ⚡ Quick Install (One-Liner)

#### 1. Install Wazuh Server v4.14 All-in-One (Linux):
Mendukung **Ubuntu, Debian, RHEL, CentOS Stream, AlmaLinux, Rocky Linux, Oracle Linux, serta Amazon Linux 2 & 2023**:
```bash
# A. Instalasi Standar All-in-One:
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_server.sh | sudo bash

# B. Instalasi + Otomatis Membuka Port Firewall (1514, 1515, 443, 55000):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_server.sh | sudo bash -s -- --open-firewall

# C. Instalasi pada VM Lab/Testing dengan RAM Terbatas (< 4 GB):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_server.sh | sudo bash -s -- --force --open-firewall
```

#### 2. Install & Enroll Wazuh Agent v4.14 (Linux):
```bash
# A. Instalasi Cepat (Otomatis hostname & grup 'default'):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m <IP_WAZUH_MANAGER>

# B. Instalasi Kustom Nama Agent, Multi-Grup & Mode Non-Interaktif:
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m 172.31.10.50 -n "web-prod-01" -g "production,web" -y

# C. Instalasi dengan Registration Password (authd.pass):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m 172.31.10.50 -p "PasswordRahasia123"
```

> [!TIP]
> Parameter `-s --` digunakan agar bash membaca skrip dari stdin dan meneruskan argumen setelah tanda `--` ke dalam skrip installer.  
> Panduan lengkap parameter CLI, konfigurasi firewall, cloud-init AWS, dan troubleshooting Linux tersedia di **[wazuh_scripts_guide.md](wazuh_scripts_guide.md)**.  
> Sinkronisasi waktu (NTP) dan penamaan server/agent sangat krusial untuk keakuratan korelasi log SIEM; panduan konfigurasi Hostname & NTP Indonesia tersedia di **[panduan_ganti_hostname_dan_ntp_indonesia.md](panduan_ganti_hostname_dan_ntp_indonesia.md)**.

#### 3. Install & Enroll Wazuh Agent di Windows (PowerShell):
Buka **PowerShell** sebagai Administrator (*Run as Administrator*) pada Windows (mendukung Windows Server 2016-2025, Windows 10 & 11):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; `
Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.0-1.msi" -OutFile "$env:TEMP\wazuh-agent.msi"; `
msiexec.exe /i "$env:TEMP\wazuh-agent.msi" /qn WAZUH_MANAGER="<IP_WAZUH_MANAGER>" WAZUH_REGISTRATION_SERVER="<IP_WAZUH_MANAGER>"; `
Start-Sleep -Seconds 5; `
Set-Service -Name "WazuhSvc" -StartupType Automatic; `
Start-Service -Name "WazuhSvc"
```

> [!NOTE]
> Panduan lengkap kustomisasi nama agent Windows, multi-grup, instalasi GUI wizard, pemantauan Windows EventChannel & Sysmon tersedia di **[wazuh_agent_windows_install_guide.md](wazuh_agent_windows_install_guide.md)**.

---

### 📑 Daftar Dokumen Berdasarkan Kategori

#### 1. Master Guide & Dokumen Utama
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

#### 2. Skrip Otomasi Bash (Installer v4.14)
- [install_wazuh_server.sh](install_wazuh_server.sh)  
  *Skrip otomasi Bash universal instalasi Wazuh Server v4.14 All-in-One (Ubuntu, Debian, RHEL, Oracle Linux, AlmaLinux, Amazon Linux 2 & 2023).*
- [install_wazuh_agent.sh](install_wazuh_agent.sh)  
  *Skrip otomasi Bash universal instalasi & enrollment Wazuh Agent v4.14 multi-OS.*
- [wazuh_scripts_guide.md](wazuh_scripts_guide.md)  
  *Panduan lengkap penggunaan skrip otomasi server dan agent, opsi CLI flag, port firewall, dan troubleshooting.*

#### 3. Instalasi & Upgrade Wazuh Server
- [wazuh_server_almalinux_install_guide.md](wazuh_server_almalinux_install_guide.md)  
  *Panduan instalasi Wazuh Server (Manager, Indexer, Dashboard) di AlmaLinux.*
- [wazuh_server_upgrade_guide.md](wazuh_server_upgrade_guide.md)  
  *Prosedur step-by-step upgrade Wazuh Server dan komponen pendukung tanpa kehilangan data.*

#### 4. Panduan Instalasi Wazuh Agent
- [wazuh_agent_windows_install_guide.md](wazuh_agent_windows_install_guide.md)  
  *Panduan instalasi dan konfigurasi Wazuh Agent di Microsoft Windows (Server 2016-2025, Windows 10/11), silent install PowerShell, GUI, Sysmon, dan EventChannel.*
- [wazuh_agent_install_guide.md](wazuh_agent_install_guide.md)  
  *Panduan instalasi standar Wazuh Agent multi-platform (Linux, Windows, macOS) dan pendaftaran ke Wazuh Manager.*
- [wazuh_agent_amazon_linux_install_guide.md](wazuh_agent_amazon_linux_install_guide.md)  
  *Panduan instalasi dan deployment Wazuh Agent khusus Amazon Linux 2 (AL2) dan Amazon Linux 2023 (AL2023).*
- [wazuh_agent_almalinux_install_guide.md](wazuh_agent_almalinux_install_guide.md)  
  *Panduan instalasi Wazuh Agent di AlmaLinux.*
- [keterangan_fresh_install_wazuh_agent.md](keterangan_fresh_install_wazuh_agent.md)  
  *Panduan fresh install Wazuh Agent dan penyesuaian versi agar kompatibel dengan server.*
- [keterangan_downgrade_wazuh_client.md](keterangan_downgrade_wazuh_client.md)  
  *Panduan downgrade paket Wazuh Agent ke versi yang sesuai (aturan: versi agent <= versi manager).*

#### 5. Integrasi Load Balancer (Cloud)
- [keterangan_tambahan_aws_lb.md](keterangan_tambahan_aws_lb.md)  
  *Panduan konfigurasi AWS Application Load Balancer (ALB) dan Target Group untuk Wazuh Dashboard (penanganan HTTP 302 redirect).*
- [keterangan_tambahan_oci_lb.md](keterangan_tambahan_oci_lb.md)  
  *Panduan konfigurasi Oracle Cloud Infrastructure (OCI) Load Balancer untuk Wazuh Dashboard (penanganan issue TLS/HTTPS 443 & backend health check).*

#### 6. Security Rules, Alerts & Use Cases
- [wazuh_failed_login_alert_and_simulation_guide.md](wazuh_failed_login_alert_and_simulation_guide.md)  
  *Panduan pembuatan alert gagal login di Wazuh Dashboard, custom rules, simulasi serangan brute force, dan verifikasi.*
- [wazuh_failed_login_usecases.md](wazuh_failed_login_usecases.md)  
  *Daftar matriks use cases deteksi insiden keamanan terkait autentikasi (SOC Guide).*

#### 7. Troubleshooting Runbooks
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

#### 8. Prasyarat & Konfigurasi Sistem Linux (Hostname & NTP)
- [panduan_ganti_hostname_dan_ntp_indonesia.md](panduan_ganti_hostname_dan_ntp_indonesia.md)  
  *Panduan komprehensif mengubah hostname, timezone (WIB/WITA/WIT), jam manual, dan sinkronisasi otomatis NTP Pool Indonesia (Chrony, timesyncd, ntpd) di semua distro Linux.*

---

## 🇬🇧 English

A comprehensive documentation repository, architecture blueprints, automated deployment scripts, cloud integration guides, security use cases, and troubleshooting runbooks for **Wazuh SIEM & XDR**.

### 👤 Author Attribution
- **Created by:** Andi Pangeran
- **Repository:** [https://github.com/andonebekasi/wazuh](https://github.com/andonebekasi/wazuh)

---

### ⚡ Quick Install (One-Liner)

#### 1. Install Wazuh Server v4.14 All-in-One (Linux):
Supports **Ubuntu, Debian, RHEL, CentOS Stream, AlmaLinux, Rocky Linux, Oracle Linux, and Amazon Linux 2 & 2023**:
```bash
# A. Standard All-in-One Installation:
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_server.sh | sudo bash

# B. Install + Automatically Open Firewall Ports (1514, 1515, 443, 55000):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_server.sh | sudo bash -s -- --open-firewall

# C. Install on Lab/Testing VMs with Limited RAM (< 4 GB):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_server.sh | sudo bash -s -- --force --open-firewall
```

#### 2. Install & Enroll Wazuh Agent v4.14 (Linux):
```bash
# A. Fast Installation (Auto-detects hostname & assigns 'default' group):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m <IP_WAZUH_MANAGER>

# B. Custom Agent Name, Multi-Group Assignment & Non-Interactive Mode:
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m 172.31.10.50 -n "web-prod-01" -g "production,web" -y

# C. Install with Registration Password (authd.pass):
curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m 172.31.10.50 -p "SecretPassword123"
```

> [!TIP]
> The `-s --` flag tells bash to read the script from standard input and pass everything after `--` as command-line arguments to the installer.  
> See **[wazuh_scripts_guide.md](wazuh_scripts_guide.md)** for a complete reference on CLI options, firewall parameters, AWS cloud-init setups, and troubleshooting.  
> Accurate system time (NTP) and proper host naming are critical for SIEM log correlation; see **[panduan_ganti_hostname_dan_ntp_indonesia.md](panduan_ganti_hostname_dan_ntp_indonesia.md)** for hostname and Indonesian NTP setup.

#### 3. Install & Enroll Wazuh Agent on Windows (PowerShell):
Open **PowerShell** as Administrator (*Run as Administrator*) on Windows (supports Windows Server 2016-2025, Windows 10 & 11):

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; `
Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.0-1.msi" -OutFile "$env:TEMP\wazuh-agent.msi"; `
msiexec.exe /i "$env:TEMP\wazuh-agent.msi" /qn WAZUH_MANAGER="<IP_WAZUH_MANAGER>" WAZUH_REGISTRATION_SERVER="<IP_WAZUH_MANAGER>"; `
Start-Sleep -Seconds 5; `
Set-Service -Name "WazuhSvc" -StartupType Automatic; `
Start-Service -Name "WazuhSvc"
```

> [!NOTE]
> A complete guide on custom agent naming, multi-group assignment, GUI wizard setup, Sysmon and Windows EventChannel logging is available at **[wazuh_agent_windows_install_guide.md](wazuh_agent_windows_install_guide.md)**.

---

### 📑 Document Directory by Category

#### 1. Master Guides & Core Documents
- [Wazuh_SIEM_XDR_Full_Detail_Master_Guide.pdf](Wazuh_SIEM_XDR_Full_Detail_Master_Guide.pdf)  
  *Complete master guide for Wazuh SIEM & XDR (PDF format).*
- [wazuh_full_detail_guide.pdf](wazuh_full_detail_guide.pdf)  
  *Comprehensive technical reference document for Wazuh (PDF format).*
- [wazuh_aws_ec2_install_guide.md](wazuh_aws_ec2_install_guide.md)  
  *End-to-end installation and configuration guide for Wazuh All-in-One / Distributed on AWS EC2 (Amazon Linux 2023 & Ubuntu), Security Groups, Golden AMIs, and user-data.*
- [wazuh_dashboard_usage_guide.md](wazuh_dashboard_usage_guide.md)  
  *Guide to navigating, visualizing, and leveraging Wazuh Dashboard (FIM, Vulnerabilities, Compliance, MITRE ATT&CK).*
- [wazuh_keterangan_tambahan.md](wazuh_keterangan_tambahan.md)  
  *Operational notes: Daily/EPS storage sizing formulas, indexer retention tuning, hardening practices, and audit checklist.*

#### 2. Bash Automation Scripts (Installer v4.14)
- [install_wazuh_server.sh](install_wazuh_server.sh)  
  *Universal Bash automation script to install Wazuh Server v4.14 All-in-One (Ubuntu, Debian, RHEL, Oracle Linux, AlmaLinux, Amazon Linux 2 & 2023).*
- [install_wazuh_agent.sh](install_wazuh_agent.sh)  
  *Universal Bash automation script for installing and enrolling Wazuh Agent v4.14 across various Linux distributions.*
- [wazuh_scripts_guide.md](wazuh_scripts_guide.md)  
  *Comprehensive manual for the automation scripts, CLI flag documentation, firewall configurations, and troubleshooting.*

#### 3. Wazuh Server Installation & Upgrades
- [wazuh_server_almalinux_install_guide.md](wazuh_server_almalinux_install_guide.md)  
  *Wazuh Server deployment guide (Manager, Indexer, Dashboard) on AlmaLinux.*
- [wazuh_server_upgrade_guide.md](wazuh_server_upgrade_guide.md)  
  *Step-by-step upgrade procedure for Wazuh Server components without data loss.*

#### 4. Wazuh Agent Installation Guides
- [wazuh_agent_windows_install_guide.md](wazuh_agent_windows_install_guide.md)  
  *Installation and configuration guide for Wazuh Agent on Microsoft Windows (Server 2016-2025, Windows 10/11), silent PowerShell deployment, GUI manager, Sysmon, and EventChannel.*
- [wazuh_agent_install_guide.md](wazuh_agent_install_guide.md)  
  *Standard multi-platform Wazuh Agent installation and enrollment guide (Linux, Windows, macOS).*
- [wazuh_agent_amazon_linux_install_guide.md](wazuh_agent_amazon_linux_install_guide.md)  
  *Dedicated deployment guide for Amazon Linux 2 (AL2) and Amazon Linux 2023 (AL2023).*
- [wazuh_agent_almalinux_install_guide.md](wazuh_agent_almalinux_install_guide.md)  
  *Installation guide for Wazuh Agent on AlmaLinux.*
- [keterangan_fresh_install_wazuh_agent.md](keterangan_fresh_install_wazuh_agent.md)  
  *Clean install guide and version alignment between Wazuh Agent and Manager.*
- [keterangan_downgrade_wazuh_client.md](keterangan_downgrade_wazuh_client.md)  
  *Guide to downgrading Wazuh Agent packages to match Server version (rule: agent version <= manager version).*

#### 5. Cloud Load Balancer Integrations
- [keterangan_tambahan_aws_lb.md](keterangan_tambahan_aws_lb.md)  
  *AWS Application Load Balancer (ALB) and Target Group setup guide for Wazuh Dashboard (handling HTTP 302 redirects).*
- [keterangan_tambahan_oci_lb.md](keterangan_tambahan_oci_lb.md)  
  *Oracle Cloud Infrastructure (OCI) Load Balancer configuration for Wazuh Dashboard (handling TLS/HTTPS 443 backend health check).*

#### 6. Security Rules, Alerts & Use Cases
- [wazuh_failed_login_alert_and_simulation_guide.md](wazuh_failed_login_alert_and_simulation_guide.md)  
  *Guide on creating failed login alerts, custom rules, brute-force simulation, and alert verification.*
- [wazuh_failed_login_usecases.md](wazuh_failed_login_usecases.md)  
  *SOC detection use cases matrix for authentication and brute-force events.*

#### 7. Troubleshooting Runbooks
- [troubleshoot_wazuh.md](troubleshoot_wazuh.md)  
  *General troubleshooting repository and solutions for Wazuh Agent and Server.*
- [troubleshoot_wazuh_agent.md](troubleshoot_wazuh_agent.md)  
  *Specific service diagnostics and connection troubleshooting for Wazuh Agent.*
- [troubleshoot_wazuh_agent_server.md](troubleshoot_wazuh_agent_server.md)  
  *Network connectivity, firewall ports, and authentication troubleshooting between Agent and Server.*
- [troubleshoot_wazuh_client_syscollector.md](troubleshoot_wazuh_client_syscollector.md)  
  *Resolution guide for Syscollector error (`No such tag 'users'`).*
- [troubleshoot_rename_wazuh_agent.md](troubleshoot_rename_wazuh_agent.md)  
  *Guide on renaming a Wazuh Agent safely without breaking `client.keys`.*
- [keterangan_tambahan_agent_baru_tidak_muncul_dashboard.md](keterangan_tambahan_agent_baru_tidak_muncul_dashboard.md)  
  *Diagnosis and solution when the agent service is active but does not appear on the Wazuh Dashboard.*

#### 8. Linux System Prerequisites & Time Synchronization (Hostname & NTP)
- [panduan_ganti_hostname_dan_ntp_indonesia.md](panduan_ganti_hostname_dan_ntp_indonesia.md)  
  *Comprehensive guide for configuring hostname, timezone (WIB/WITA/WIT), and automated Indonesian NTP pool time synchronization (Chrony, systemd-timesyncd, ntpd) across Linux distributions.*

---

## 👨‍💻 Kontributor & Lisensi / Author & Credits

Dokumentasi dan skrip ini disusun dan dikembangkan oleh:
- **Nama:** Andi Pangeran
- **GitHub:** [@andonebekasi](https://github.com/andonebekasi)
- **Repositori:** [github.com/andonebekasi/wazuh](https://github.com/andonebekasi/wazuh)
