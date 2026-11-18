# PANDUAN STEP-BY-STEP DOWNGRADE & CARA INSTALL WAZUH CLIENT (AGENT) v4.9.2

1. LATAR BELAKANG & ATURAN KOMPATIBILITAS WAZUH

---

- Kondisi:
  * Server (Wazuh Manager): v4.9.2 (wazuh-tree-prod)
  * Client (Wazuh Agent)  : v4.14.x (hrptrsapprd)
- Aturan Utama Wazuh:
  Versi Wazuh Agent TIDAK BOLEH lebih tinggi dari versi Wazuh Manager/Server.
  Jika versi Agent lebih baru dibandingkan Server/Manager, agent tidak dapat
  berkomunikasi secara normal dengan manager (dapat terjadi error protokol,
  koneksi terputus, atau data telemetry tidak terbaca).
- Solusi:
  Turunkan (downgrade) versi Wazuh Agent di client yang sudah ada, atau saat
  menambah client baru, pastikan menginstal paket spesifik versi v4.9.2.

## 2. LANGKAH-LANGKAH DOWNGRADE WAZUH AGENT KE v4.9.2 (AGENT YANG SUDAH ADA)

Semua perintah di bawah ini dijalankan di server Client (ec2-user@hrptrsapprd).

### LANGKAH 1: Stop Service Wazuh Agent

Hentikan service agent yang sedang berjalan:

```bash
sudo systemctl stop wazuh-agent
```

### LANGKAH 2: Backup File Registrasi (client.keys) dan Konfigurasi (ossec.conf)

File 'client.keys' berisi identitas dan cryptographic key registrasi agent ke server.
Backup file ini agar Anda TIDAK PERLU meregistrasi ulang agent di Wazuh Manager:

```bash
sudo cp /var/ossec/etc/client.keys /tmp/client.keys.bak
sudo cp /var/ossec/etc/ossec.conf /tmp/ossec.conf.bak
```

### LANGKAH 3: Proses Downgrade Paket ke Versi 4.9.2-1

#### PILIHAN A (Menggunakan yum / dnf):

  1. Cek ketersediaan versi 4.9.2 pada repositori:
```bash
sudo yum --showduplicates list wazuh-agent
```

  2. Jalankan downgrade:
```bash
sudo yum downgrade wazuh-agent-4.9.2-1 -y
```

  Catatan jika perintah downgrade gagal karena dependensi atau cache:
```bash
sudo yum remove wazuh-agent -y
sudo yum install wazuh-agent-4.9.2-1 -y
```

#### PILIHAN B (Menggunakan direct RPM jika repo mengalami kendala):

  - Untuk arsitektur x86_64 (Intel / AMD 64-bit):
```bash
sudo rpm -Uvh --oldpackage https://packages.wazuh.com/4.x/yum/wazuh-agent-4.9.2-1.x86_64.rpm
```

  - Untuk arsitektur aarch64 (AWS Graviton / ARM 64-bit):
```bash
sudo rpm -Uvh --oldpackage https://packages.wazuh.com/4.x/yum/wazuh-agent-4.9.2-1.aarch64.rpm
```

### LANGKAH 4: Restore / Pastikan File Konfigurasi & Permission Sesuai

Pastikan file 'client.keys' dan 'ossec.conf' tidak terhapus atau tertimpa saat
proses install ulang paket:

```xml
# Kembalikan file dari backup jika terhapus/kosong
sudo cp /tmp/client.keys.bak /var/ossec/etc/client.keys
sudo cp /tmp/ossec.conf.bak /var/ossec/etc/ossec.conf

# Atur kepemilikan dan hak akses (permission) yang benar
sudo chown root:wazuh /var/ossec/etc/client.keys
sudo chmod 640 /var/ossec/etc/client.keys

sudo chown root:wazuh /var/ossec/etc/ossec.conf
sudo chmod 640 /var/ossec/etc/ossec.conf

# PERINGATAN PENTING jika restore ossec.conf dari versi 4.14.x:
# Wazuh v4.9.2 BELUM mendukung tag inventori baru 4.14+ (<users>, <groups>, <services>, <browser_extensions>)!
# Hapus semua tag tersebut sekaligus dengan perintah:
sudo sed -i -E '/<(users|groups|services|browser_extensions)>.*<\/(users|groups|services|browser_extensions)>/d' /var/ossec/etc/ossec.conf

# Validasi konfigurasi:
sudo /var/ossec/bin/wazuh-modulesd -t
```

### LANGKAH 5: Kunci Versi Paket (Versionlock) - Disarankan

Kunci paket wazuh-agent agar tidak ter-upgrade otomatis secara tidak sengaja
ketika admin menjalankan 'yum update' di kemudian hari:

  - Untuk Amazon Linux 2 / CentOS 7 / RHEL 7 (yum):
```bash
sudo yum install yum-plugin-versionlock -y
sudo yum versionlock wazuh-agent
```

  - Untuk Amazon Linux 2023 / RHEL 8/9 / Fedora (dnf):
```bash
sudo dnf install python3-dnf-plugin-versionlock -y
sudo dnf versionlock add wazuh-agent
```

### LANGKAH 6: Jalankan Service Wazuh Agent & Verifikasi

1. Reload systemd daemon dan aktifkan service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl restart wazuh-agent
```

2. Cek status service:
```bash
sudo systemctl status wazuh-agent
```

3. Verifikasi versi Wazuh Agent saat ini:
```bash
sudo /var/ossec/bin/wazuh-control info
```

   atau
```bash
sudo /var/ossec/bin/wazuh-agentd -V
```

   (Pastikan output menampilkan versi v4.9.2)

4. Cek log koneksi ke Wazuh Manager:
```bash
sudo grep -i "connected" /var/ossec/logs/ossec.log | tail -n 10
```

   Indikasi berhasil jika log menampilkan:
   "wazuh-agentd: INFO: Connected to the server (<IP_WAZUH_SERVER>:1514)..."

## 3. CARA INSTALL & MENAMBAHKAN CLIENT AGENT BARU DENGAN VERSI v4.9.2

Gunakan panduan ini jika Anda memiliki server/VM baru (client baru) dan ingin
menginstal Wazuh Agent dengan versi yang sama persis seperti server (v4.9.2).

### METODE 1: Auto-Enrollment (Paling Mudah & Direkomendasikan)

#### Metode ini otomatis mengunduh versi 4.9.2, meregistrasikan agent ke server,

dan mengonfigurasi IP server dalam satu baris perintah.

#### Langkah di server Client baru:

1. Import GPG Key Wazuh:
```bash
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
```

2. Tambahkan Repositori Wazuh:
```bash
cat << EOF | sudo tee /etc/yum.repos.d/wazuh.repo
```

   [wazuh]
```text
gzip=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
EOF
```

3. Install paket dengan variabel registrasi (KUNCI PENTING: sertakan versi -4.9.2-1):
```bash
sudo WAZUH_MANAGER="<IP_ATAU_DNS_WAZUH_SERVER>" \
     WAZUH_AGENT_NAME="<NAMA_CLIENT_AGENT>" \
     yum install wazuh-agent-4.9.2-1 -y
```

   *Catatan:*
   - Ganti <IP_ATAU_DNS_WAZUH_SERVER> dengan IP Private server Wazuh Anda.
   - Ganti <NAMA_CLIENT_AGENT> dengan nama hostname/identitas client ini.
   - Jika menggunakan Amazon Linux 2023 / DNF, ganti 'yum' dengan 'dnf'.

4. Kunci versi paket agar tidak ter-upgrade otomatis:
```bash
sudo yum install yum-plugin-versionlock -y
sudo yum versionlock wazuh-agent
```

5. Aktifkan dan jalankan service agent:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

### METODE 2: Registrasi Manual (Via agent-auth)

Jika auto-enrollment tidak digunakan atau ingin mengatur registrasi terpisah:

1. Tambahkan repository dan pasang paket versi 4.9.2-1:
```bash
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
cat << EOF | sudo tee /etc/yum.repos.d/wazuh.repo
```

   [wazuh]
```bash
gzip=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
EOF
sudo yum install wazuh-agent-4.9.2-1 -y
```

2. Registrasikan agent ke server:
```bash
sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_SERVER> -A <NAMA_CLIENT_AGENT>
```

   (Jika server menggunakan password pendaftaran/authd: tambahkan opsi -P <PASSWORD>)

3. Masukkan IP server pada file /var/ossec/etc/ossec.conf:
   Cari blok <client><server>:
```text
-----------------------------------------
<client>
  <server>
    <address><IP_WAZUH_SERVER></address>
    <port>1514</port>
    <protocol>tcp</protocol>
  </server>
</client>
-----------------------------------------
```

4. Kunci versi dan start service:
```bash
sudo yum install yum-plugin-versionlock -y && sudo yum versionlock wazuh-agent
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

### METODE 3: Menggunakan Wazuh Dashboard (UI Deployment)

Jika Anda membuat command instalasi lewat Web Dashboard Wazuh:
1. Buka Wazuh Dashboard -> Menu -> Server management -> Endpoints Summary.
2. Klik tombol "Deploy new agent".
3. Pilih OS: Red Hat / CentOS / Amazon Linux.
4. Pilih Arsitektur: x86_64 (atau ARM/aarch64).
5. Masukkan Wazuh server address (IP Private server Wazuh).
6. Masukkan Agent name (nama instance client).
7. Dashboard akan men-generate satu baris perintah instalasi.
   PERHATIAN (PENTING):
   Secara default dashboard akan mengenerate:
```bash
WAZUH_MANAGER="..." yum install wazuh-agent -y
```

   Ubah baris tersebut menjadi:
```bash
WAZUH_MANAGER="..." yum install wazuh-agent-4.9.2-1 -y
```

   (Wajib tambahkan '-4.9.2-1' agar sistem mengunduh versi yang sama persis
    dengan server Anda, bukan versi terbaru yang ada di repo).

## 4. VERIFIKASI AKHIR KONEKSI SERVER DAN CLIENT

1. Di sisi Client:
```bash
sudo systemctl status wazuh-agent
sudo grep -i "connected" /var/ossec/logs/ossec.log | tail -n 5
```

2. Di sisi Server Wazuh (wazuh-tree-prod):
   Jalankan perintah ini untuk melihat seluruh agent yang aktif:
```bash
sudo /var/ossec/bin/agent_control -l
```

   Atau cari agent tertentu:
```bash
sudo /var/ossec/bin/agent_control -i <ID_AGENT_ATAU_NAMA>
```

   (Pastikan statusnya "Active" dan versinya tertulis "Wazuh v4.9.2")

3. Pastikan Security Group / Firewall Mengizinkan Port:
   - Port 1514 (TCP/UDP) : Agent connection & events (Client -> Server)
   - Port 1515 (TCP)     : Agent registration / enrollment (Client -> Server)
================================================================================