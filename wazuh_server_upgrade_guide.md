# PANDUAN LENGKAP UPGRADE WAZUH SERVER (ALL-IN-ONE): DARI v4.9.2 KE v4.14.7 - Target Lingkungan: AWS EC2 (Amazon Linux 2023 / AL2 / RHEL) - wazuh-tree-prod

## DAFTAR ISI:

1. Latar Belakang Kasus & Kompatibilitas Versi
2. Catatan Kritis & Breaking Changes (v4.9 -> v4.14)
3. Urutan Wajib Upgrade (The Golden Rule of Wazuh)
4. Langkah 0: Persiapan Pra-Upgrade & Backup Menyeluruh (Wajib!)
5. Langkah 1: Pembaruan Repository Wazuh Package Manager
6. Langkah 2: Eksekusi Upgrade - Wazuh Indexer (Tahap Pertama)
7. Langkah 3: Eksekusi Upgrade - Wazuh Server / Manager & Filebeat (Tahap Kedua)
8. Langkah 4: Eksekusi Upgrade - Wazuh Dashboard (Tahap Ketiga)
9. Langkah 5: Validasi & Pengujian Registrasi Agent Client (v4.14.7)
10. Troubleshooting Masalah Pasca-Upgrade
11. Disaster Recovery & Rollback Plan (Pemulihan Snapshot EBS)
12. Alternatif Cepat Tanpa Upgrade Server: Downgrade Agent di Client

## 1. LATAR BELAKANG KASUS & KOMPATIBILITAS VERSI

Kondisi Aktual:
- Hostname Server : wazuh-tree-prod (AWS EC2)
- Versi Server    : Wazuh Server v4.9.2 (Revision 40921)
- Hostname Client : hrptrsapprd / EC2 Agent Client
- Versi Client    : Wazuh Agent v4.14.7

Masalah:
Dalam arsitektur keamanan Wazuh, terdapat aturan kompatibilitas mutlak:
"Agent version must be lower or equal to manager version (Agent <= Manager)".

Jika versi agent (v4.14.7) lebih baru dibanding versi manager (v4.9.2):
- Registrasi dan pertukaran kunci kriptografi akan DITOLAK oleh authd di server.
- Log agent menampilkan error:
  "agent-auth: ERROR: Agent version must be lower or equal to manager version (from manager)"

Untuk menyelesaikannya dengan menaikkan versi server ke level yang sama dengan 
client (v4.14.7), ikuti tahapan step-by-step di bawah ini.

## 2. CATATAN KRITIS & BREAKING CHANGES (v4.9 -> v4.14)

Sebelum menjalankan upgrade, pahami perubahan penting antara v4.9 dan v4.14:

1. Perubahan Engine OpenSearch / Apache Lucene (v4.12+):
   - Wazuh v4.12 ke atas menggunakan versi Lucene baru yang TIDAK MENDUKUNG 
     downgrade secara otomatis lewat package manager.
   - Jika proses upgrade sudah berjalan dan terjadi kendala besar, cara rollback 
     resmi adalah memulihkan instance dari AWS EBS Snapshot.

2. Pemetaan Field JSON User (v4.14.1+):
   - Mulai v4.14.1, field JSON bernama `user` otomatis dipetakan ke `dstuser` 
     selama proses decoding event.
   - Jika Anda memiliki custom dashboard, query, atau skrip integrasi kustom yang 
     mengacu ke `data.user`, perbarui menjadi `data.dstuser`.

3. Penyimpanan Kredensial Indexer di Keystore (v4.14+):
   - Wazuh Manager v4.14 mewajibkan penyimpanan kredensial Wazuh Indexer di 
     dalam internal keystore Manager (`wazuh-keystore`).

4. Pertahankan Konfigurasi Lama:
   - Saat package manager (dnf/yum) memperbarui paket, jika muncul pertanyaan 
     apakah ingin menimpa file konfigurasi (seperti `ossec.conf` atau 
     `opensearch_dashboards.yml`), SELALU pilih opsi pertahankan konfigurasi 
     lama (biasanya tekan tombol 'N' / No).

## 3. URUTAN WAJIB UPGRADE (THE GOLDEN RULE OF WAZUH)

Wazuh All-in-One terdiri dari 3 service terintegrasi. Anda TIDAK BOLEH meng-upgrade 
secara acak. Urutan resmi yang wajib diikuti adalah:

   | 1. WAZUH INDEXER (Penyimpanan database log - WAJIB PERTAMA) |
                                  |

                                  v

   | 2. WAZUH SERVER / MANAGER + FILEBEAT (Engine analisis log)  |
                                  |

                                  v

   | 3. WAZUH DASHBOARD (Antarmuka Web UI)                       |
                                  |

                                  v

   | 4. WAZUH AGENTS (Endpoint client - Terakhir)                |

## 4. LANGKAH 0: PERSIAPAN PRA-UPGRADE & BACKUP MENYELURUH (WAJIB!)

Jangan pernah melakukan upgrade pada server produksi tanpa backup!

#### A. Buat AWS EBS Snapshot (Safety Net Utama)

1. Buka AWS Management Console -> EC2 -> Instances.
2. Cari instance server Wazuh: `wazuh-tree-prod`.
3. Buka tab "Storage" -> klik Volume ID (root volume).
4. Klik "Actions" -> "Create snapshot".
5. Berikan Deskripsi: `Backup-Pre-Upgrade-Wazuh-4.9-to-4.14-wazuh-tree-prod`.
6. Klik "Create snapshot" dan tunggu hingga statusnya `Completed`.

#### B. Backup File Konfigurasi & Sertifikat Lokal di Server

Login via SSH ke `wazuh-tree-prod`:
   ssh -i your-key.pem ec2-user@<IP_WAZUH_SERVER>

Jalankan perintah backup arsip:
```bash
sudo mkdir -p /opt/wazuh_backup_pre_upgrade
sudo tar -czvf /opt/wazuh_backup_pre_upgrade/wazuh_configs_$(date +%F).tar.gz \
  /var/ossec/etc \
```

     /etc/filebeat \
     /etc/wazuh-indexer \
     /etc/wazuh-dashboard

#### C. Periksa Kapasitas Disk & Kesehatan Cluster Saat Ini

1. Pastikan kapasitas disk masih tersisa minimal 15% - 20%:
```text
df -h /
```

2. Periksa status kesehatan Wazuh Indexer (OpenSearch):
```bash
curl -k -u admin:admin https://127.0.0.1:9200/_cluster/health?pretty
# (Ganti password admin jika Anda menggunakan password custom)
# Pastikan status cluster adalah "green" atau "yellow".
```

## 5. LANGKAH 1: PEMBARUAN REPOSITORY WAZUH PACKAGE MANAGER

Pastikan repository Wazuh di server mengarah ke channel 4.x yang menyediakan 
paket versi 4.14.7.

1. Impor kunci GPG resmi Wazuh:
```bash
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
```

2. Konfigurasi file repository Wazuh:
```bash
cat << 'REPO_EOF' | sudo tee /etc/yum.repos.d/wazuh.repo
```

[wazuh]
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
REPO_EOF

3. Bersihkan cache metadata package manager:
```bash
# Jika menggunakan Amazon Linux 2023 (AL2023):
sudo dnf clean all
sudo dnf makecache

# Jika menggunakan Amazon Linux 2 / RHEL / CentOS:
# sudo yum clean all
# sudo yum makecache
```

4. Verifikasi ketersediaan paket v4.14.7:
```bash
sudo dnf list --showduplicates wazuh-indexer wazuh-manager wazuh-dashboard | grep 4.14.7
# (Output harus menampilkan paket dengan versi 4.14.7-1)
```

## 6. LANGKAH 2: EKSEKUSI UPGRADE - WAZUH INDEXER (TAHAP PERTAMA)

Komponen penyimpanan data harus di-upgrade terlebih dahulu.

1. Hentikan service wazuh-indexer:
```bash
sudo systemctl stop wazuh-indexer
```

2. Jalankan perintah upgrade paket wazuh-indexer:
```bash
# Pada AL2023:
sudo dnf install -y wazuh-indexer-4.14.7-1

# Pada AL2 / RHEL / CentOS:
# sudo yum install -y wazuh-indexer-4.14.7-1

CATATAN: Jika sistem menanyakan apakah ingin menimpa file konfigurasi 
`/etc/wazuh-indexer/opensearch.yml`, ketik `N` (No) untuk mempertahankan 
```

   konfigurasi node dan cluster yang sudah ada.

3. Muat ulang systemd daemon dan aktifkan kembali service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-indexer
sudo systemctl start wazuh-indexer
```

4. Tunggu sekitar 20 - 30 detik untuk inisialisasi Java OpenSearch, lalu verifikasi:
```bash
sudo systemctl status wazuh-indexer
```

5. Uji API Indexer lokal:
```bash
curl -k -u admin:admin https://127.0.0.1:9200
# Output JSON harus menampilkan versi modul Wazuh Indexer yang baru.
```

## 7. LANGKAH 3: EKSEKUSI UPGRADE - WAZUH MANAGER & FILEBEAT (TAHAP KEDUA)

Setelah Indexer berjalan normal, upgrade Wazuh Server (Manager) dan Filebeat.

1. Hentikan service wazuh-manager dan filebeat:
```bash
sudo systemctl stop wazuh-manager
sudo systemctl stop filebeat
```

2. Jalankan perintah upgrade paket wazuh-manager:
```bash
# Pada AL2023:
sudo dnf install -y wazuh-manager-4.14.7-1

# Pada AL2 / RHEL / CentOS:
# sudo yum install -y wazuh-manager-4.14.7-1

CATATAN: Jika ditanya overwrite `/var/ossec/etc/ossec.conf`, pilih `N` (No).
```

3. Perbarui Filebeat Template & Wazuh Module:
   Filebeat bertugas mengirim event dari Manager ke Indexer. Perbarui template 
   alert agar sesuai dengan versi v4.14.7:
   
```bash
sudo curl -so /etc/filebeat/wazuh-template.json \
  https://raw.githubusercontent.com/wazuh/wazuh/v4.14.7/extensions/elasticsearch/7.x/wazuh-template.json
sudo chmod 644 /etc/filebeat/wazuh-template.json
```

4. Muat ulang daemon dan jalankan kembali service Manager & Filebeat:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-manager filebeat
sudo systemctl start wazuh-manager
sudo systemctl start filebeat
```

5. Verifikasi status service:
```bash
sudo systemctl status wazuh-manager
sudo systemctl status filebeat
```

6. Verifikasi versi baru Wazuh Server via binary wazuh-control:
```bash
sudo /var/ossec/bin/wazuh-control info
```

   Contoh Output Berhasil:
```text
--------------------------------------------------
WAZUH_VERSION="v4.14.7"
WAZUH_REVISION="41470"
WAZUH_TYPE="server"
--------------------------------------------------
```

## 8. LANGKAH 4: EKSEKUSI UPGRADE - WAZUH DASHBOARD (TAHAP KETIGA)

Terakhir, perbarui antarmuka web (Wazuh Dashboard).

1. Hentikan service wazuh-dashboard:
```bash
sudo systemctl stop wazuh-dashboard
```

2. Jalankan perintah upgrade paket wazuh-dashboard:
```bash
# Pada AL2023:
sudo dnf install -y wazuh-dashboard-4.14.7-1

# Pada AL2 / RHEL / CentOS:
# sudo yum install -y wazuh-dashboard-4.14.7-1

CATATAN: Jika ditanya overwrite `/etc/wazuh-dashboard/opensearch_dashboards.yml`, 
```

   pilih `N` (No) agar sertifikat SSL dan domain yang sudah diatur tidak hilang.

3. Muat ulang daemon dan jalankan kembali service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-dashboard
sudo systemctl start wazuh-dashboard
```

4. Verifikasi status service:
```bash
sudo systemctl status wazuh-dashboard
```

5. Verifikasi akses Web UI:
   - Buka browser Anda: `https://<IP_PUBLIC_ATAU_DOMAIN_WAZUH>`
   - Login menggunakan akun admin Anda.
   - Buka menu navigasi kiri -> Scroll ke bawah -> Klik "About" / "Server management".
   - Pastikan versi yang tertera adalah Wazuh v4.14.7.

## 9. LANGKAH 5: VALIDASI & PENGUJIAN REGISTRASI AGENT CLIENT (v4.14.7)

Sekarang kedua sisi (Server dan Client) sudah sama-sama berada di versi v4.14.7.

#### A. Pengujian di Sisi Client (Mesin Agent):

1. Login via SSH ke mesin client tempat agent v4.14.7 berada.
2. Jalankan registrasi ulang ke server:
```bash
sudo /var/ossec/bin/agent-auth -m <IP_PRIVATE_WAZUH_SERVER>
```

   Output Sukses:
```text
--------------------------------------------------
INFO: Connected to <IP_WAZUH_SERVER>:1515
INFO: Using agent name: <nama-client>
INFO: Key received for agent '<nama-client>'
INFO: Valid key received
--------------------------------------------------
```

3. Restart wazuh-agent:
```bash
sudo systemctl restart wazuh-agent
sudo systemctl status wazuh-agent
```

4. Periksa log koneksi agent:
```bash
sudo tail -n 25 /var/ossec/logs/ossec.log
# Pastikan terdapat pesan:
# "INFO: Connected to server (<IP_WAZUH_SERVER>:1514/tcp)"
```

#### B. Verifikasi dari Sisi Wazuh Server:

Kembali ke terminal `wazuh-tree-prod`:
```bash
sudo /var/ossec/bin/agent_control -l
```

   Contoh Output:
```text
--------------------------------------------------
```

   Wazuh agent_control. List of available agents:
```text
   ID: 001, Name: hrptrsapprd, IP: 172.1.x.x, Active
--------------------------------------------------
```

Lihat detail versi agent:
```bash
sudo /var/ossec/bin/agent_control -i 001
# Periksa baris: "Version: Wazuh v4.14.7"
```

## 10. TROUBLESHOOTING MASALAH PASCA-UPGRADE

1. Wazuh Dashboard menampilkan "Wazuh server is not available" atau API Error:
   - Cek apakah service wazuh-manager berjalan normal:
```bash
sudo systemctl status wazuh-manager
```

   - Cek apakah port 55000 aktif:
```bash
sudo ss -tulpn | grep 55000
```

   - Cek log API:
```bash
sudo tail -n 50 /var/ossec/logs/api.log
```

2. Wazuh Indexer gagal start (Status: Failed / Crashed):
   - Masalah paling sering: batas parameter kernel mmapfs terlalu rendah.
```bash
Jalankan:
sudo sysctl -w vm.max_map_count=262144
sudo systemctl restart wazuh-indexer
```

   - Cek log detail:
```bash
sudo tail -n 50 /var/log/wazuh-indexer/wazuh-cluster.log
```

3. Filebeat gagal mengirim data ke Indexer:
   - Uji konektivitas Filebeat:
```bash
sudo filebeat test output
```

   - Jika response error, pastikan sertifikat root CA di `/etc/filebeat/certs` 
     masih valid dan cocok dengan sertifikat di `/etc/wazuh-indexer/certs`.

4. Error Pendaftaran Agent "Duplicate Name / IP":
   - Jika registrasi gagal karena nama agent lama masih tersimpan di DB server, 
     aktifkan fitur penimpaan otomatis (force_insert) di `wazuh-tree-prod`:
```bash
sudo nano /var/ossec/etc/ossec.conf
```

   - Pastikan di dalam blok `<auth>` terdapat:
     <auth>
       <disabled>no</disabled>
       <port>1515</port>
       <use_source_ip>no</use_source_ip>
       <force_insert>yes</force_insert>
       <force_time>0</force_time>
       <purge>yes</purge>
     </auth>
   - Restart manager:
```bash
sudo systemctl restart wazuh-manager
```

## 11. DISASTER RECOVERY & ROLLBACK PLAN (PEMULIHAN SNAPSHOT EBS)

Jika selama proses upgrade terjadi kegagalan fatal yang tidak dapat diperbaiki:

1. Matikan instance server (Stop Instance):
   Di AWS Management Console -> EC2 -> Pilih `wazuh-tree-prod` -> Instance State -> Stop instance.

2. Buat Volume dari Snapshot Pre-Upgrade:
   - Buka EC2 -> Snapshots -> Cari Snapshot yang Anda buat di Langkah 0.
   - Klik "Actions" -> "Create volume from snapshot".
   - Pastikan Availability Zone (AZ) sama persis dengan AZ instance `wazuh-tree-prod` 
     (misal: ap-southeast-1a).

3. Tukar Volume Root:
   - Masuk ke menu "Volumes".
   - Detach volume yang rusak dari `wazuh-tree-prod`.
   - Attach volume baru hasil restore tadi ke `wazuh-tree-prod` dengan 
     device name: `/dev/xvda` (untuk Amazon Linux).

4. Nyalakan Kembali Instance:
   - Start instance `wazuh-tree-prod`.
   - Server akan kembali 100% ke kondisi awal v4.9.2 tanpa ada data yang rusak.

## 12. ALTERNATIF CEPAT TANPA UPGRADE SERVER: DOWNGRADE AGENT DI CLIENT

Jika tim DevOps / Sysadmin memutuskan bahwa upgrade server `wazuh-tree-prod` 
terlalu berisiko atau belum memiliki jadwal maintenance window produksi, 
solusi terbaik dan tercepat adalah MENURUNKAN VERSI AGENT DI CLIENT ke v4.9.2.

#### Langkah Downgrade di Client (Hanya butuh 2 menit, zero downtime):

1. Login SSH ke Client (hrptrsapprd).
2. Hentikan dan hapus agent v4.14.7:
```bash
sudo systemctl stop wazuh-agent
sudo yum remove -y wazuh-agent    # Atau: sudo dnf remove -y wazuh-agent
sudo rm -f /var/ossec/etc/client.keys
```

3. Pasang wazuh-agent versi 4.9.2-1 yang cocok dengan Manager:
```bash
# Ganti 172.1.12.93 dengan IP private Wazuh Manager Anda:
sudo WAZUH_MANAGER='172.1.12.93' yum install -y wazuh-agent-4.9.2-1
# (Jika OS AL2023 gunakan dnf):
# sudo WAZUH_MANAGER='172.1.12.93' dnf install -y wazuh-agent-4.9.2-1
```

4. Aktifkan dan jalankan service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

5. Verifikasi:
```bash
sudo /var/ossec/bin/wazuh-agentd -V
sudo tail -n 20 /var/ossec/logs/ossec.log
```

================================================================================