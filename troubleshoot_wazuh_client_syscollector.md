# PANDUAN TROUBLESHOOTING LENGKAP: WAZUH AGENT GAGAL START - Kasus: Error "No such tag at module 'syscollector'" & Konfigurasi Error 1202

1. KASUS & GEJALA ERROR
```bash
Ketika menjalankan perintah:
  sudo systemctl restart wazuh-agent

Layanan gagal berjalan (status: failed) dengan pesan:
  Job for wazuh-agent.service failed because the control process exited with error code.

Saat dicek dengan `sudo systemctl status wazuh-agent` atau `journalctl -xe`, muncul log:
```

Starting Wazuh agent...
wazuh-modulesd: ERROR: No such tag 'users' at module 'syscollector'.
wazuh-modulesd: ERROR: No such tag 'services' at module 'syscollector'.
wazuh-modulesd: ERROR: No such tag 'browser_extensions' at module 'syscollector'.
wazuh-modulesd: ERROR: (1202): Configuration error at 'etc/ossec.conf'.
wazuh-modulesd: Configuration error. Exiting
wazuh-agent.service: control process exited, code=exited status=1
Failed to start Wazuh agent.
Unit wazuh-agent.service entered failed state.
wazuh-agent.service failed.
### 2. AKAR MASALAH (ROOT CAUSE)

#### A. Mismatch Tag Konfigurasi Antar Versi:

   - Kasus ini terjadi setelah melakukan proses downgrade Wazuh Agent (misal dari
     v4.14.x ke v4.9.2 agar kompatibel dengan versi Wazuh Manager), di mana file 
     `ossec.conf` lama di-restore atau tetap digunakan.
   - Pada Wazuh v4.14.0, terdapat 4 tag inventori baru pada blok `<wodle name="syscollector">`:
     1. <users>
     2. <groups>
     3. <services>
     4. <browser_extensions>
   - Pada Wazuh Agent versi v4.9.2, ke-4 tag di atas BELUM ADA dan TIDAK DIDUKUNG.

#### B. Batasan Tag Modul Syscollector di Wazuh v4.9.2:

   Tag yang sah dan didukung di v4.9.2 HANYA:
   - disabled
   - interval
   - scan_on_start
   - hardware
   - os
   - network
   - packages
   - ports
   - processes
   - hotfixes (khusus Windows)
   - synchronization (database sync setting)

C. Mengapa "verify-agent-conf: command not found":
   - Binary `verify-agent-conf` hanya disediakan pada Wazuh Manager/Server (untuk 
     memvalidasi `agent.conf`).
   - Di sisi Wazuh Agent (Client), tool untuk menguji sintaks konfigurasi modul adalah:
```bash
sudo /var/ossec/bin/wazuh-modulesd -t
```

3. SOLUSI CEPAT (ONE-LINER FIX DI CLIENT)
### Jalankan langkah-langkah berikut di terminal EC2 Client (misal: ec2-user@hrptrsapprd): - LANGKAH 1: Hapus Semua Tag Tidak Kompatibel Sekaligus

Gunakan regex sed untuk menghapus ke-4 tag sekaligus dari `/var/ossec/etc/ossec.conf`:

```bash
sudo sed -i -E '/<(users|groups|services|browser_extensions)>.*<\/(users|groups|services|browser_extensions)>/d' /var/ossec/etc/ossec.conf
```

*Catatan:*
Tag grup registrasi agent pada bagian `<client>` (contoh: `<groups>production,hr-payroll</groups>`)
tetap aman dan tidak terpengaruh jika formatnya satu baris terpisah atau grup multi-nilai.

#### LANGKAH 2: Pastikan Blok Syscollector Sudah Sesuai Standar v4.9.2

```bash
Jalankan perintah ini untuk melihat isi blok syscollector:

  sudo sed -n '/<wodle name="syscollector">/,/<\/wodle>/p' /var/ossec/etc/ossec.conf

Struktur standar yang benar dan bersih untuk Wazuh Agent v4.9.2:
```

  <wodle name="syscollector">
    <disabled>no</disabled>
    <interval>1h</interval>
    <scan_on_start>yes</scan_on_start>
    <hardware>yes</hardware>
    <os>yes</os>
    <network>yes</network>
    <packages>yes</packages>
    <ports all="yes">yes</ports>
    <processes>yes</processes>

    <!-- Database synchronization settings -->
    <synchronization>
      <max_eps>10</max_eps>
    </synchronization>
  </wodle>
### LANGKAH 3: Validasi Sintaks Konfigurasi Modul

Jalankan pengujian sintaks konfigurasi modul:

```bash
sudo /var/ossec/bin/wazuh-modulesd -t
```

*Indikator Berhasil:*
Jika tidak ada output error dan kursor langsung kembali ke command prompt, berarti
seluruh konfigurasi ossec.conf sudah valid 100%.

#### LANGKAH 4: Jalankan Ulang Layanan Wazuh Agent

```bash
  sudo systemctl daemon-reload
  sudo systemctl restart wazuh-agent
  sudo systemctl status wazuh-agent

*Indikator Berhasil (Output Sukses):*
```

● wazuh-agent.service - Wazuh agent
```text
 Loaded: loaded (/usr/lib/systemd/system/wazuh-agent.service; enabled; vendor preset: disabled)
 Active: active (running) since Tue ...; 10s ago
Process: 5728 ExecStart=/usr/bin/env /var/ossec/bin/wazuh-control start (code=exited, status=0/SUCCESS)
  Tasks: 39
 CGroup: /system.slice/wazuh-agent.service
```

           ├─ /var/ossec/bin/wazuh-execd
           ├─ /var/ossec/bin/wazuh-agentd
           ├─ /var/ossec/bin/wazuh-syscheckd
           ├─ /var/ossec/bin/wazuh-logcollector
           └─ /var/ossec/bin/wazuh-modulesd
### LANGKAH 5: Verifikasi Koneksi ke Wazuh Manager

Periksa log koneksi agent ke server manager:

```bash
sudo tail -n 20 /var/ossec/logs/ossec.log
```

*Output Sukses:*
```text
wazuh-agentd: INFO: Connected to the server [<IP_WAZUH_SERVER>:1514]
wazuh-agentd: INFO: Server responded. Agent is now connected.
```

### 4. PENCEGAHAN DI MASA DEPAN (BEST PRACTICES)

1. Kunci Versi Paket (Versionlock):
   Agar paket `wazuh-agent` tidak ter-upgrade otomatis saat admin menjalankan
   `sudo yum update` atau `sudo dnf update`:

   - Amazon Linux 2 / CentOS 7:
```bash
sudo yum install yum-plugin-versionlock -y
sudo yum versionlock wazuh-agent
```

   - Amazon Linux 2023 / RHEL 8/9:
```bash
sudo dnf install python3-dnf-plugin-versionlock -y
sudo dnf versionlock add wazuh-agent
```

   - Verifikasi status kunci versi:
```bash
sudo yum versionlock list   (atau: sudo dnf versionlock list)
```

2. Hati-hati Saat Me-Restore ossec.conf:
   Jika melakukan downgrade paket agent dari versi yang lebih baru ke versi yang lebih
   lama, jangan me-restore file `ossec.conf` secara mentah-mentah tanpa membuang
   tag-tag baru yang belum didukung oleh binary versi lama.
================================================================================