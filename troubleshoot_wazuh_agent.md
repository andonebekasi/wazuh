# PANDUAN TROUBLESHOOTING: WAZUH AGENT - ERROR "UNABLE TO ADD AGENT"

KASUS ERROR:
Ketika memeriksa log agent (`sudo tail -n 25 /var/ossec/logs/ossec.log`), muncul:
```text
wazuh-agentd: ERROR: Unable to add agent (from manager)
wazuh-agentd: INFO: Requesting a key from server: 172.1.12.93
```

1. ANALISIS MASALAH
```bash
- Arti Log:
  * Jaringan dan port 1515 TCP di AWS Security Group SUDAH BERHASIL terhubung.
  * Agent berhasil mengirim permintaan registrasi ke Wazuh Server (172.1.12.93).
  * Kata kunci "(from manager)" berarti Wazuh Manager MENOLAK penambahan agent.

- Penyebab Utama:
  * 1. Version Mismatch (Error: "Agent version must be lower or equal to manager version"):
    Aturan arsitektur Wazuh: Versi Wazuh Agent TIDAK BOLEH lebih tinggi dari Manager.
    Jika versi Agent di client lebih baru dari Manager, registrasi DITOLAK seketika.
  * 2. Duplicate Agent Name / IP:
    Nama hostname agent (contoh: `hrptrsapprd`) atau IP-nya sudah terdaftar 
    sebelumnya di database Manager.
  * 3. Password Authd:
    Wazuh Manager dikonfigurasi dengan authd password, tetapi agent mendaftar tanpa password.

2. LANGKAH DIAGNOSA DARI SISI CLIENT (EC2 AGENT)
```

Jalankan perintah registrasi manual untuk melihat pesan penolakan spesifik:

sudo /var/ossec/bin/agent-auth -m 172.1.12.93

Contoh pesan error yang akan muncul di layar:
- "ERROR: Duplicate agent name: hrptrsapprd" -> Berarti nama agent sudah ada di Manager.
- "ERROR: Duplicate IP" -> Berarti IP client sudah terdaftar pada ID lain.
- "ERROR: Agent version must be lower or equal to manager version" 
  -> Versi agent lebih tinggi dari server (Contoh: hrptrsapprd v4.14.7 vs wazuh-tree-prod v4.9.2).
- "ERROR: Invalid password" -> Manager memerlukan password autentikasi authd.

3. SOLUSI ERROR VERSION MISMATCH (DOWNGRADE AGENT KE v4.9.2)
```bash
Jalankan langsung di terminal Client (hrptrsapprd):

1. Hapus agent v4.14.7:
   sudo systemctl stop wazuh-agent
   sudo yum remove wazuh-agent -y
   sudo rm -f /var/ossec/etc/client.keys

2. Install versi 4.9.2-1 (sesuai versi Manager wazuh-tree-prod):
   sudo WAZUH_MANAGER='172.1.12.93' yum install -y wazuh-agent-4.9.2-1
   # Atau jika AL2023:
   sudo WAZUH_MANAGER='172.1.12.93' dnf install -y wazuh-agent-4.9.2-1

3. Start service:
   sudo systemctl daemon-reload
   sudo systemctl enable wazuh-agent
   sudo systemctl start wazuh-agent

4. Verifikasi versi & koneksi:
   sudo /var/ossec/bin/wazuh-agentd -V
   sudo tail -n 20 /var/ossec/logs/ossec.log

4. SOLUSI DI SISI WAZUH SERVER JIKA DUPLIKASI AGENT (172.1.12.93)
```

Login via SSH ke Wazuh Server, pilih salah satu metode berikut:

#### METODE A: Hapus Data Agent Lama (Paling Cepat)

1. Cek ID dari agent `hrptrsapprd` yang sudah ada:
```bash
sudo /var/ossec/bin/agent_control -l
```

   Contoh output:
```text
ID: 001, Name: hrptrsapprd, IP: 172.1.x.x, Active
```

2. Hapus agent lama tersebut berdasarkan ID-nya:
```bash
sudo /var/ossec/bin/manage_agents -r 001
```

```xml
METODE B: Aktifkan Fitur Timpa Otomatis (force_insert) - REKOMENDASI TERBAIK
Dengan fitur ini, jika server client di-reinstall atau ganti agent, Manager akan 
otomatis menimpa pendaftaran lama tanpa perlu menghapus manual.

1. Buka file konfigurasi di Wazuh Server:
   sudo nano /var/ossec/etc/ossec.conf

2. Cari blok `<auth>` di dalam `<ossec_config>` (atau tambahkan jika belum ada):
   <auth>
     <disabled>no</disabled>
     <port>1515</port>
     <use_source_ip>no</use_source_ip>
     <force_insert>yes</force_insert>
     <force_time>0</force_time>
     <purge>yes</purge>
   </auth>

3. Restart Wazuh Manager:
   sudo systemctl restart wazuh-manager

4. PENDAFTARAN ULANG DI SISI CLIENT (EC2 AGENT: hrptrsapprd)
```

Setelah melakukan perbaikan di server:

1. Daftarkan ulang agent secara manual:
```bash
sudo /var/ossec/bin/agent-auth -m 172.1.12.93
```

   Output sukses:
```text
INFO: Valid key received
```

2. Restart service Wazuh Agent:
```bash
sudo systemctl restart wazuh-agent
```

3. Verifikasi file kunci enkripsi sudah terbuat:
```bash
sudo cat /var/ossec/etc/client.keys
```

   (Akan muncul 1 baris berisi ID, nama host hrptrsapprd, IP, dan token).

4. Pantau log koneksi:
```bash
sudo tail -n 20 /var/ossec/logs/ossec.log
```

   Output sukses:
```text
wazuh-agentd: INFO: Connected to the server [172.1.12.93:1514]
wazuh-agentd: INFO: Server responded. Agent is now connected.
```

5. VERIFIKASI AKHIR

---

- Di Server:
```bash
sudo /var/ossec/bin/agent_control -l
```

  Pastikan agent `hrptrsapprd` berstatus "Active".

- Di Wazuh Dashboard:
  Buka menu "Agents" -> pastikan client `hrptrsapprd` berwarna hijau (Active).

## 6. KETERANGAN TAMBAHAN: ERROR "NO SUCH TAG 'USERS' / 'SERVICES' / 'BROWSER_EXTENSIONS'"

#### A. Gejala & Log Error:

Saat menjalankan `sudo systemctl restart wazuh-agent`, service gagal start 
(Active: failed) atau saat cek `sudo /var/ossec/bin/wazuh-modulesd -t` muncul error:
```text
wazuh-modulesd: ERROR: No such tag 'users' at module 'syscollector'.
(atau 'groups', 'services', 'browser_extensions')
wazuh-modulesd: ERROR: (1202): Configuration error at 'etc/ossec.conf'.
wazuh-modulesd: Configuration error. Exiting
```

#### B. Penyebab Masalah:

- Error ini terjadi setelah proses downgrade versi agent (dari v4.14.x ke v4.9.2), 
  di mana file konfigurasi `ossec.conf` lama dari versi 4.14 masih digunakan/direstore.
- Pada Wazuh v4.14.0 diperkenalkan 4 tag inventori baru di modul `syscollector`:
  1. `<users>`
  2. `<groups>`
  3. `<services>`
  4. `<browser_extensions>`
- Keempat tag ini BELUM ADA dan TIDAK DIDUKUNG pada Wazuh Agent versi v4.9.2.
- Tag yang didukung pada v4.9.2 di dalam `<wodle name="syscollector">` HANYALAH:
  interval, scan_on_start, disabled, network, os, hardware, packages, ports, 
  processes, hotfixes, dan synchronization.
- Adanya salah satu dari 4 tag tersebut akan menyebabkan `wazuh-modulesd` gagal validasi 
  (Error 1202) dan service langsung crash saat start.

#### C. Langkah Solusi & Perbaikan di Client (hrptrsapprd):

1. Hapus ke-4 tag yang tidak didukung sekaligus:
```bash
sudo sed -i -E '/<(users|groups|services|browser_extensions)>.*<\/(users|groups|services|browser_extensions)>/d' /var/ossec/etc/ossec.conf
```

2. Pastikan isi blok syscollector sudah bersih sesuai standar v4.9.2:
```text
sed -n '/<wodle name="syscollector">/,/<\/wodle>/p' /var/ossec/etc/ossec.conf
```

   Standar syscollector yang benar di v4.9.2:
   <wodle name="syscollector">
     <disabled>no</disabled>
     <interval>1h</interval>
     <scan_on_start>yes</scan_on_start>
     <hardware>yes</hardware>
     <os>yes</os>
     <network>yes</network>
     <packages>yes</packages>
     <ports all="no">yes</ports>
     <processes>yes</processes>
   </wodle>

3. Verifikasi validitas sintaks konfigurasi:
```bash
sudo /var/ossec/bin/wazuh-modulesd -t
```

   *Jika perintah di atas sukses tanpa error (kembali ke prompt kosong), artinya 
   konfigurasi ossec.conf sudah 100% valid.*

4. Restart service Wazuh Agent:
```bash
sudo systemctl daemon-reload
sudo systemctl restart wazuh-agent
sudo systemctl status wazuh-agent
```

   (Service sekarang akan berstatus: Active: active (running)).

5. Pantau log agent untuk memastikan koneksi ke server normal:
```bash
sudo tail -n 20 /var/ossec/logs/ossec.log
```

================================================================================
