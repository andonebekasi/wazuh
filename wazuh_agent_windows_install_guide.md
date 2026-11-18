# PANDUAN LENGKAP: INSTALASI & KONFIGURASI WAZUH AGENT DI MICROSOFT WINDOWS (SERVER & WORKSTATION)

> **Dibuat oleh:** Andi Pangeran  
> **Repositori:** [https://github.com/andonebekasi/wazuh](https://github.com/andonebekasi/wazuh)

Panduan teknis operasional menyeluruh untuk instalasi, registrasi (*enrollment*), konfigurasi modul keamanan (*EventChannel*, Sysmon, FIM), serta *troubleshooting* **Wazuh Agent** pada sistem operasi **Microsoft Windows**.

---

## 💻 Kompatibilitas Sistem Operasi
- **Windows Server:** 2016, 2019, 2022, 2025 (Standard, Datacenter, Core Edition)
- **Windows Desktop / Workstation:** Windows 10, Windows 11 (64-bit & 32-bit)

---

## 🌐 Prasyarat Jaringan & Port Firewall

Pastikan endpoint Windows dapat mengakses Wazuh Manager melalui port berikut (Outbound dari Agent ke Manager):
- **Port 1514/TCP (atau UDP):** Komunikasi agen ke manager (pengiriman events/logs).
- **Port 1515/TCP:** Autentikasi dan registrasi pendaftaran agen (*authd*).

---

## 🚀 METODE 1: Instalasi Cepat via PowerShell (CLI - Direkomendasikan)

Buka **PowerShell** sebagai Administrator (*Run as Administrator*) pada endpoint Windows, lalu jalankan opsi berikut:

### Opsi A: PowerShell One-Liner (Otomatis Unduh & Install)

Ganti `<IP_WAZUH_MANAGER>` dengan alamat IP atau FQDN Wazuh Manager Anda:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; `
Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.0-1.msi" -OutFile "$env:TEMP\wazuh-agent.msi"; `
msiexec.exe /i "$env:TEMP\wazuh-agent.msi" /qn WAZUH_MANAGER="<IP_WAZUH_MANAGER>" WAZUH_REGISTRATION_SERVER="<IP_WAZUH_MANAGER>"; `
Start-Sleep -Seconds 5; `
Set-Service -Name "WazuhSvc" -StartupType Automatic; `
Start-Service -Name "WazuhSvc"
```

---

### Opsi B: Instalasi Terstruktur dengan Kustomisasi Parameter

Gunakan skrip PowerShell berikut jika Anda ingin menentukan nama agen, grup, dan kata sandi registrasi:

```powershell
# 1. Konfigurasi Parameter
$WazuhManager = "172.31.10.50"             # Ganti dengan IP Wazuh Manager Anda
$AgentName    = "win-server-prod-01"       # Opsional: default menggunakan hostname
$AgentGroup   = "production,windows"       # Opsional: default grup 'default'
$AuthPassword = "PasswordRahasia123"       # Opsional: jika authd.pass diaktifkan
$MsiUrl       = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.0-1.msi"
$MsiPath      = "$env:TEMP\wazuh-agent.msi"

# 2. Aktifkan TLS 1.2 & Unduh Installer MSI
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Host "Mengunduh paket Wazuh Agent..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath

# 3. Susun Argumen Silent Install
$ArgsList = @(
    "/i", "`"$MsiPath`"",
    "/qn",
    "WAZUH_MANAGER=`"$WazuhManager`"",
    "WAZUH_REGISTRATION_SERVER=`"$WazuhManager`""
)

if ($AgentName) {
    $ArgsList += "WAZUH_AGENT_NAME=`"$AgentName`""
}
if ($AgentGroup) {
    $ArgsList += "WAZUH_AGENT_GROUP=`"$AgentGroup`""
}
if ($AuthPassword) {
    $ArgsList += "WAZUH_REGISTRATION_PASSWORD=`"$AuthPassword`""
}

# 4. Eksekusi Instalasi MSI
Write-Host "Menginstal Wazuh Agent secara silent..." -ForegroundColor Cyan
$Process = Start-Process -FilePath "msiexec.exe" -ArgumentList $ArgsList -Wait -PassThru

if ($Process.ExitCode -eq 0) {
    Write-Host "Instalasi MSI berhasil!" -ForegroundColor Green
} else {
    Write-Host "Instalasi MSI selesai dengan kode: $($Process.ExitCode)" -ForegroundColor Yellow
}

# 5. Konfigurasi dan Jalankan Service Wazuh
Set-Service -Name "WazuhSvc" -StartupType Automatic
Start-Service -Name "WazuhSvc"

# 6. Verifikasi Service
Get-Service -Name "WazuhSvc" | Format-Table -AutoSize
```

---

## 🖥️ METODE 2: Instalasi Interaktif via Graphical User Interface (GUI)

Cocok untuk pengguna desktop atau workstation Windows:

1. **Unduh Paket Installer:**
   - Kunjungi repositori resmi Wazuh: `https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.0-1.msi`.
2. **Jalankan Installer Wizard:**
   - Klik ganda file `.msi` yang telah diunduh.
   - Ikuti petunjuk di layar hingga proses instalasi selesai (default direktori: `C:\Program Files (x86)\ossec-agent\`).
3. **Konfigurasi Agen via GUI Manager:**
   - Buka menu Start -> cari dan jalankan aplikasi **Wazuh Agent Manager** (`win32ui.exe`) dengan hak Administrator (*Run as Administrator*).
   - Masukkan informasi:
     - **Manager IP:** Masukkan alamat IP / domain Wazuh Server.
     - **Authentication key:** Dapat diisi otomatis jika melakukan registrasi via Manager.
4. **Jalankan Layanan:**
   - Pilih menu **Manage** -> **Restart Service**.
   - Perhatikan indikator di pojok kanan bawah jendela aplikasi, status akan berubah menjadi **Connected**.

---

## 🛡️ Konfigurasi Modul Keamanan Windows (`ossec.conf`)

Lokasi file konfigurasi agent Windows berada di:
```text
C:\Program Files (x86)\ossec-agent\ossec.conf
```

### 1. Monitoring Windows EventChannel & Sysmon
Tambahkan blok berikut di dalam tag `<ossec_config>` untuk menyadap event modern Windows dan Sysmon:

```xml
<ossec_config>
  <localfile>
    <location>Security</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>System</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <localfile>
    <location>Application</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <!-- Jika Sysmon terpasang -->
  <localfile>
    <location>Microsoft-Windows-Sysmon/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>

  <!-- Monitoring Script Block Logging PowerShell -->
  <localfile>
    <location>Microsoft-Windows-PowerShell/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
</ossec_config>
```

### 2. File Integrity Monitoring (FIM) Direktori Kritis Windows
Pastikan FIM memonitor direktori sistem penting:

```xml
<syscheck>
  <directories check_all="yes" realtime="yes">C:\Windows\System32\drivers\etc</directories>
  <directories check_all="yes">C:\Program Files\Wazuh Agent</directories>
  <windows_registry>HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run</windows_registry>
  <windows_registry>HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\RunOnce</windows_registry>
</syscheck>
```

Setelah mengubah `ossec.conf`, restart service Wazuh melalui PowerShell:
```powershell
Restart-Service -Name "WazuhSvc"
```

---

## 🔍 Perintah Manajemen & Verifikasi (PowerShell)

| Aksi | Perintah PowerShell |
| :--- | :--- |
| **Cek Status Service** | `Get-Service -Name "WazuhSvc"` |
| **Mulai Service** | `Start-Service -Name "WazuhSvc"` |
| **Hentikan Service** | `Stop-Service -Name "WazuhSvc"` |
| **Restart Service** | `Restart-Service -Name "WazuhSvc"` |
| **Pantau Log Agen (Real-time)** | `Get-Content -Path "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 30 -Wait` |
| **Cek Koneksi ke Manager (Port 1514)** | `Test-NetConnection -ComputerName <IP_WAZUH_MANAGER> -Port 1514` |
| **Cek Kunci Enkripsi Registrasi** | `Get-Content "C:\Program Files (x86)\ossec-agent\client.keys"` |

---

## 🛠️ Troubleshooting Kasus Lapangan Windows

### 1. Status Service Running namun Tidak Konek ke Manager
- **Penyebab:** Port 1514/TCP diblokir oleh Windows Firewall atau Network Security Group (NSG / AWS Security Group).
- **Solusi:**
  Uji koneksi port dari PowerShell:
  ```powershell
  Test-NetConnection -ComputerName <IP_WAZUH_MANAGER> -Port 1514
  ```
  Jika `TcpTestSucceeded : False`, periksa rute jaringan dan pastikan firewall mengizinkan *outbound traffic* ke port 1514.

### 2. File `client.keys` Kosong
- **Penyebab:** Pendaftaran (*enrollment*) gagal saat instalasi MSI, port 1515 tertutup, atau kata sandi registrasi salah.
- **Solusi:** Daftarkan ulang agen secara manual via perintah bawaan:
  ```powershell
  & "C:\Program Files (x86)\ossec-agent\agent-auth.exe" -m <IP_WAZUH_MANAGER> -p 1515
  Restart-Service -Name "WazuhSvc"
  ```

### 3. Uninstall / Hapus Wazuh Agent
Jika ingin menghapus instalasi agen secara bersih (*clean uninstall*):
```powershell
Stop-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
msiexec.exe /x "$env:TEMP\wazuh-agent.msi" /qn
Remove-Item -Recurse -Force "C:\Program Files (x86)\ossec-agent" -ErrorAction SilentlyContinue
```
