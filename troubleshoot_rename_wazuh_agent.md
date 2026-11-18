# PANDUAN TROUBLESHOOTING: CARA RENAME (GANTI NAMA) WAZUH AGENT

KASUS:
Pada Wazuh Manager, agent terdaftar dengan nama default hostname (contoh:
ID: 004, Name: ip-172-1-12-178.ap-southeast-3.compute.internal) dan ingin
diubah namanya menjadi nama yang lebih deskriptif (contoh: hrptrsappprd-new).

CATATAN PENTING:
Wazuh TIDAK MENYEDIAKAN perintah native seperti "rename agent" secara langsung
di tool CLI `manage_agents` karena nama agent terikat secara kriptografis dengan
Agent ID dan cryptographic authentication key di database Wazuh Manager.

## METODE 1: RE-ENROLLMENT / DAFTAR ULANG (SANGAT DIREKOMENDASIKAN - AMAN & BERSIH)

#### Metode ini adalah "best practice" resmi dari Wazuh. Proses ini menghapus ID lama

dan mendaftarkan agent kembali dengan nama baru tanpa merusak integritas database.

### LANGKAH 1: Stop Service Agent di Server Client (172.1.12.178)

Jalankan di server client:
```bash
sudo systemctl stop wazuh-agent
```

### LANGKAH 2: Hapus Agent Lama (ID: 004) di Wazuh Manager

Jalankan di server Wazuh Manager (wazuh-tree-prod):
```bash
sudo /var/ossec/bin/manage_agents -r 004
```

Ketik 'y' lalu tekan Enter saat muncul konfirmasi:
  Confirm deleting it?(y/n): y

### LANGKAH 3: Daftarkan Kembali dengan Nama Baru

Pilih salah satu dari Opsi A atau Opsi B di bawah ini:

--- OPSI A: Registrasi Cepat via `agent-auth` (Langsung dari Client) ---
Jalankan di terminal server client:
```bash
sudo /var/ossec/bin/agent-auth -m <IP_WAZUH_MANAGER> -A hrptrsappprd-new
```

Contoh (jika IP Wazuh Manager adalah 172.1.12.93):
```bash
sudo /var/ossec/bin/agent-auth -m 172.1.12.93 -A hrptrsappprd-new
```

Setelah sukses mendapatkan response "Valid key received", jalankan kembali agent:
```bash
sudo systemctl start wazuh-agent
```

--- OPSI B: Registrasi Manual via `manage_agents` di Manager ---
1. Tambah agent baru di Wazuh Manager:
```bash
sudo /var/ossec/bin/manage_agents
```

   - Ketik 'A' (Add an agent)
   - Berikan nama baru: hrptrsappprd-new
   - IP Agent: any (atau masukkan IP private client 172.1.12.178)
   - Konfirmasi: y

2. Ambil (Extract) key autentikasi:
   - Ketik 'E' (Extract key for an agent)
   - Masukkan ID agent baru yang baru saja terbentuk
   - Copy seluruh teks key yang ditampilkan (string panjang)
   - Ketik 'Q' untuk keluar dari manage_agents

3. Import key di server client:
```bash
sudo /var/ossec/bin/manage_agents -i <PASTE_STRING_KEY_DI_SINI>
```

   - Ketik 'y' untuk konfirmasi import
   - Ketik 'Q' untuk keluar

4. Start service agent di client:
```bash
sudo systemctl start wazuh-agent
```

### LANGKAH 4: Verifikasi Hasil Rename

1. Cek di Wazuh Manager CLI:
```bash
sudo /var/ossec/bin/manage_agents -l
```

   Output yang diharapkan:
   Available agents:
```text
ID: 001, Name: hrptrsapprd, IP: any
ID: 002, Name: hrptrsdbprd, IP: any
ID: 003, Name: hrptrsdbprd-new, IP: any
ID: <ID_BARU>, Name: hrptrsappprd-new, IP: any
```

2. Cek koneksi aktif di Manager:
```bash
sudo /var/ossec/bin/agent_control -l
```

3. Cek log status di Client:
```bash
sudo tail -n 20 /var/ossec/logs/ossec.log
```

   (Pastikan muncul: "INFO: Connected to server" / "Valid key received")

## METODE 2: EDIT MANUAL DATABASE (JIKA WAJIB MEMPERTAHANKAN ID: 004)

PERINGATAN:
#### Metode ini adalah "workaround" tidak resmi (unsupported). Lakukan dengan hati-hati

karena jika ada kesalahan sintaks SQLite atau file client.keys, agent tidak akan
bisa terkoneksi.

Langkah-langkah:
1. Matikan service di kedua server:
   - Di Client  : sudo systemctl stop wazuh-agent
   - Di Manager : sudo systemctl stop wazuh-manager

2. Edit file client.keys di Wazuh Manager:
```bash
sudo nano /var/ossec/etc/client.keys
```

   
   Cari baris ID 004:
   004 ip-172-1-12-178.ap-southeast-3.compute.internal any <HASH_KEY>
   
   Ubah hanya bagian namanya menjadi:
   004 hrptrsappprd-new any <HASH_KEY>
   (Simpan dan keluar).

3. Update SQLite Database di Wazuh Manager:
```bash
sudo sqlite3 /var/ossec/queue/db/global.db "UPDATE agent SET name='hrptrsappprd-new' WHERE id=4;"
```

4. Edit file client.keys di Server Client:
```bash
sudo nano /var/ossec/etc/client.keys
```

   
   Ubah baris nama menjadi identik:
   004 hrptrsappprd-new any <HASH_KEY>

5. Hidupkan kembali service (Manager terlebih dahulu):
   - Di Manager : sudo systemctl start wazuh-manager
   - Di Client  : sudo systemctl start wazuh-agent

6. Cek status:
```bash
sudo /var/ossec/bin/manage_agents -l
```

================================================================================