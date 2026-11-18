# PANDUAN LENGKAP: INSTALASI & KONFIGURASI WAZUH SIEM DI AWS EC2 / AMI

## Daftar Isi:

1. Pengenalan Wazuh & Arsitektur Komponen
2. Rekomendasi Spesifikasi AWS EC2 & EBS Storage
3. Step-by-Step Provisioning EC2 via AWS Management Console (AL2023 & Ubuntu)
4. Step-by-Step Provisioning EC2 via AWS CLI (AL2023 & Ubuntu)
5. Opsi AMI: Clean OS AMI vs AWS Marketplace Pre-Built Wazuh AMI
6. Konfigurasi AWS Networking & Security Group (Port Matrix)
7. Persiapan Sistem Operasi: OS Hardening & Prasyarat Kernel (AL2023 & Ubuntu)
8. Metode 1: Instalasi Cepat (Wazuh All-in-One Quick Installation di AL2023 / Ubuntu)
9. Metode 2: Instalasi Manual / Step-by-Step (Amazon Linux 2023 & Ubuntu 22.04)
10. Metode 3: Zero-Touch Deployment Menggunakan EC2 User Data (Cloud-Init AL2023 & Ubuntu)
11. Akses Wazuh Dashboard & Manajemen Kredensial
12. Konfigurasi SSL/TLS, Custom Domain & Reverse Proxy Nginx / AWS ALB (AL2023 & Ubuntu)
13. Pembuatan Custom Golden AMI dari Instance Wazuh (Sysprep AL2023 & Ubuntu)
14. Instalasi & Registrasi Wazuh Agent Multi-Platform (Full Detail)
15. Integrasi Wazuh dengan Layanan AWS (CloudTrail & GuardDuty)
16. Maintenance, Backup Data & Log Rotation
17. Troubleshooting Masalah Umum
18. Cheat Sheet Perintah CLI & Lokasi Log Penting

## 1. PENGENALAN WAZUH & ARSITEKTUR KOMPONEN

Wazuh adalah platform keamanan open-source untuk Threat Prevention, Detection, 
dan Response (SIEM & XDR).

Komponen Utama Wazuh:
1. Wazuh Indexer:
   - Search & analytics engine berbasis OpenSearch.
   - Bertugas mengindeks, menyimpan, dan melakukan pencarian log keamanan 
     dalam jumlah besar secara cepat dan terenkripsi.
   
2. Wazuh Server (Wazuh Manager):
   - Menerima data dari agent, menganalisis log terhadap signature/rules, 
     menjalankan threat intelligence (Vulnerability Detection, FIM, Rootcheck),
     dan memicu active response jika terdeteksi ancaman.
   - Menyediakan RESTful API (Port 55000) untuk manajemen.

3. Wazuh Dashboard:
   - Antarmuka web (UI) berbasis OpenSearch Dashboards untuk visualisasi 
     data keamanan, konfigurasi alerts, compliance reporting (PCI-DSS, 
     GDPR, HIPAA, NIST, CIS), dan status agent.

4. Wazuh Agent:
   - Service ringan yang diinstal pada endpoint/server target (Linux, Windows, 
     macOS, Kubernetes, Docker) untuk memonitor integritas file, log sistem, 
     dan postur keamanan.

## 2. REKOMENDASI SPESIFIKASI AWS EC2 & EBS STORAGE

Wazuh mengolah data log secara real-time dan memiliki komponen berbasis Java 
(Indexer) yang membutuhkan memori yang cukup agar tidak terkena OOM (Out Of Memory).

#### A. Lingkungan Uji Coba / Lab / POC (1 - 25 Agent):

   - EC2 Instance Type : t3.xlarge / t3a.xlarge / c6i.xlarge
   - vCPU              : 4 vCPU
   - RAM               : 16 GB (Minimum absolut jika resource ketat: 8 GB pada t3.large)
   - EBS Storage       : Minimal 50 GB - 100 GB (gp3, 3000 IOPS, 125 MB/s)
   - OS                : Ubuntu 22.04 LTS (x86_64) / Amazon Linux 2023

#### B. Lingkungan Produksi Menengah (25 - 100 Agent, All-in-One):

   - EC2 Instance Type : m6i.xlarge / m6a.xlarge / m7g.xlarge (Graviton ARM64)
   - vCPU              : 4 vCPU
   - RAM               : 16 GB - 32 GB
   - EBS Storage       : 200 GB - 500 GB (gp3) dengan alokasi retensi log ~90 hari

#### C. Lingkungan Skala Besar (> 100 Agent):

   - Arsitektur Terdistribusi (Multi-Node):
     * Wazuh Indexer Cluster (3 node t3.xlarge / m6i.large)
     * Wazuh Server Cluster (Master + Worker)
     * Wazuh Dashboard (1 node c6i.large)

## 3. STEP-BY-STEP PROVISIONING EC2 VIA AWS MANAGEMENT CONSOLE (AL2023 & UBUNTU)

Berikut adalah panduan lengkap membuat instance EC2 untuk Wazuh dari AWS Console:

#### Langkah 1: Masuk ke AWS EC2 Dashboard

- Buka AWS Management Console: https://console.aws.amazon.com/ec2/
- Pastikan Region AWS di pojok kanan atas sesuai (contoh: ap-southeast-1 / Singapore, 
  ap-southeast-3 / Jakarta).
- Klik tombol oranye: "Launch instance".

#### Langkah 2: Tentukan Nama & Tag Instance

- Name: `wazuh-siem-al2023` (atau `wazuh-siem-production`)
- Tags (Opsional): `Environment=Production`, `Application=Wazuh-SIEM`

#### Langkah 3: Pilih AMI (Amazon Machine Image)

- OPSI A: AMAZON LINUX 2023 (AL2023) - DIREKOMENDASIKAN UNTUK EKOSISTEM NATIVE AWS
  * Pilih tab "Quick Start" -> Klik "Amazon Linux".
  * Amazon Machine Image (AMI): Pilih `Amazon Linux 2023 AMI` (HVM, SSD Volume Type).
  * Architecture: 
    - Pilih `64-bit (x86)` jika menggunakan tipe instans Intel/AMD (t3.xlarge / m6i.xlarge).
    - Pilih `64-bit (Arm)` jika menggunakan tipe instans AWS Graviton (t4g.xlarge / m7g.xlarge).
  * Default SSH User: `ec2-user`.

- OPSI B: UBUNTU SERVER 22.04 LTS
  * Pilih tab "Quick Start" -> Klik "Ubuntu".
  * Amazon Machine Image (AMI): Pilih `Ubuntu Server 22.04 LTS (HVM), SSD Volume Type`.
  * Architecture: 
    - Pilih `64-bit (x86)` untuk Intel/AMD atau `64-bit (Arm)` untuk AWS Graviton.
  * Default SSH User: `ubuntu`.

#### Langkah 4: Pilih Instance Type

- Pilih `t3.xlarge` (4 vCPU, 16 GiB Memory) untuk tahap PoC/Menengah, atau 
  `m6i.xlarge` / `m7g.xlarge` untuk beban produksi intensif.

#### Langkah 5: Konfigurasi Key Pair (Login SSH)

- Key pair name: Pilih key pair yang sudah ada, atau klik "Create new key pair".
  * Key pair type: ED25519 (disarankan) atau RSA.
  * Private key file format: `.pem` (untuk OpenSSH di Linux/macOS atau PuTTY baru).
- Unduh dan simpan file `.pem` tersebut secara aman.

#### Langkah 6: Konfigurasi Network Settings

- Klik "Edit" di bagian Network settings:
  * VPC: Pilih VPC tujuan (VPC CIDR: `172.1.0.0/16`).
  * Subnet: Pilih Subnet dalam VPC 172.1.0.0/16.
  * Auto-assign public IP: "Enable" (jika standalone di public subnet) atau "Disable" (jika di private subnet).
  * Firewall (Security groups): Pilih "Create security group".
    - Security group name: `sg-wazuh-siem`
    - Description: `Security group for Wazuh SIEM Server (Manager, Indexer, Dashboard)`
    - Tambahkan HANYA 5 aturan Inbound (HTTPS 443, Custom TCP 1514, All ICMP, Custom TCP 1515, SSH 22) dari Source `172.1.0.0/16` sesuai rincian Bab 6 di bawah ini.

#### Langkah 7: Konfigurasi Storage (EBS Volume)

- Klik bagian "Configure storage":
  * Ukuran: Ubah dari 8 GiB ke minimal `100 GiB` (atau 200 GiB untuk produksi).
  * Tipe Volume: Pilih `General Purpose SSD (gp3)`.
  * Baseline gp3: 3000 IOPS, 125 MB/s (cukup tanpa biaya tambahan).
  * Delete on termination: Centang (Yes) atau Uncheck jika ingin volume persisten saat instance dihapus.
  * Encrypted: Pilih `Encrypted` (KMS Key: `aws/ebs` default atau Custom CMK).
  * Catatan Device Name:
    - Amazon Linux 2023 (AL2023): Root volume menggunakan `/dev/xvda`.
    - Ubuntu 22.04 LTS: Root volume menggunakan `/dev/sda1`.

#### Langkah 8: Advanced Details

- IAM instance profile: Pilih IAM Role yang memiliki akses ke SSM dan S3 CloudTrail 
  (contoh: `Role-Wazuh-Server`).
- Metadata version: Pilih `V2 only (token required)` untuk keamanan IMDSv2.
- User data (Opsional): Anda dapat menempelkan script dari Bab 10 untuk instalasi otomatis.
- Klik tombol "Launch instance".

#### Langkah 9: Alokasikan Elastic IP (Sangat Direkomendasikan)

- Masuk ke menu EC2 -> Elastic IPs -> Klik "Allocate Elastic IP address".
- Pilih IP yang terbuat -> Actions -> "Associate Elastic IP address".
- Pilih Instance: `wazuh-siem-al2023` -> Klik "Associate".
  * CATATAN: Ini memastikan IP publik Wazuh tidak berubah saat server di-reboot.

## 4. STEP-BY-STEP PROVISIONING EC2 VIA AWS CLI (AL2023 & UBUNTU)

Jika Anda menggunakan terminal atau script CI/CD / Bash untuk membuat instance EC2:

1. Buat Security Group:
```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name "sg-wazuh-siem" \
  --description "Wazuh SIEM Security Group" \
  --vpc-id "vpc-xxxxxxxx" \
  --query 'GroupId' --output text)
```

2. Buka Port Inbound pada Security Group (Hanya 5 Inbound Rules dari 172.1.0.0/16):
```bash
VPC_CIDR="172.1.0.0/16"

# Rule 1: Port HTTPS (443) - Wazuh Web Dashboard
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 443 \
  --cidr $VPC_CIDR

# Rule 2: Port Custom TCP (1514) - Wazuh Agent Events & Logs
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 1514 \
  --cidr $VPC_CIDR

# Rule 3: All ICMP - IPv4 - Ping & Uji Diagnostik Jaringan Antar-EC2
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol icmp \
  --port -1 \
  --cidr $VPC_CIDR

# Rule 4: Port Custom TCP (1515) - Wazuh Agent Enrollment & Registration (authd)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 1515 \
  --cidr $VPC_CIDR

# Rule 5: Port SSH (22) - Akses SSH & Komunikasi / Install Agent
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --ip-permissions '[{
    "IpProtocol": "tcp",
    "FromPort": 22,
    "ToPort": 22,
    "IpRanges": [{
      "CidrIp": "172.1.0.0/16",
      "Description": "untuk nanti bisa install agent dan komunikasi ec2 agent akan di install dengan wazuhnya"
    }]
  }]'
```

3. Jalankan Instance EC2:

```bash
--- OPSI A: MENGGUNAKAN AMAZON LINUX 2023 (AL2023 x86_64) ---
# Dapatkan AMI ID terbaru secara otomatis via AWS Systems Manager Parameter Store:
AL2023_AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' --output text)

# (Opsional) Jika menggunakan AWS Graviton (ARM64, misal: t4g.xlarge / m7g.xlarge):
# AL2023_AMI_ID=$(aws ssm get-parameter \
#   --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
#   --query 'Parameter.Value' --output text)

aws ec2 run-instances \
  --image-id $AL2023_AMI_ID \
  --instance-type t3.xlarge \
  --key-name "my-keypair" \
  --security-group-ids $SG_ID \
  --subnet-id "subnet-xxxxxxxx" \
  --block-device-mappings '[
    {
      "DeviceName": "/dev/xvda",
      "Ebs": {
        "VolumeSize": 100,
        "VolumeType": "gp3",
        "Iops": 3000,
        "Throughput": 125,
        "Encrypted": true,
        "DeleteOnTermination": true
      }
    }
  ]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=wazuh-siem-al2023}]' \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled"

--- OPSI B: MENGGUNAKAN UBUNTU SERVER 22.04 LTS (x86_64) ---
UBUNTU_AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameter.Value' --output text)

aws ec2 run-instances \
  --image-id $UBUNTU_AMI_ID \
  --instance-type t3.xlarge \
  --key-name "my-keypair" \
  --security-group-ids $SG_ID \
  --subnet-id "subnet-xxxxxxxx" \
  --block-device-mappings '[
    {
      "DeviceName": "/dev/sda1",
      "Ebs": {
        "VolumeSize": 100,
        "VolumeType": "gp3",
        "Iops": 3000,
        "Throughput": 125,
        "Encrypted": true,
        "DeleteOnTermination": true
      }
    }
  ]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=wazuh-siem-ubuntu}]' \
  --metadata-options "HttpTokens=required,HttpEndpoint=enabled"
```

## 5. OPSI AMI: CLEAN OS AMI VS AWS MARKETPLACE PRE-BUILT WAZUH AMI

Anda memiliki dua opsi utama dalam menentukan image dasar:

#### OPSI 1: MENGGUNAKAN CLEAN OS AMI (UBUNTU 22.04 / AL2023) - DIREKOMENDASIKAN

- Kelebihan:
  * Kontrol penuh atas seluruh dependensi, partisi disk, dan versi Wazuh.
```text
* Tidak ada lisensi atau biaya software tambahan (hanya biaya EC2 & EBS murni).
```

  * Dapat diperbarui langsung mengikuti repository official Wazuh.
  * Sangat mudah disesuaikan untuk compliance audit perusahaan.
- Kekurangan:
  * Membutuhkan waktu 5-10 menit untuk menjalankan script instalasi pertama kali.

#### OPSI 2: MENGGUNAKAN AWS MARKETPLACE PRE-BUILT WAZUH AMI

- Cara Deploy:
  1. Pada wizard "Launch instance", ketik "Wazuh" di search bar "Other non-free AMIs" / "Community AMIs" / "AWS Marketplace".
  2. Pilih image resmi dari vendor Wazuh (misal: "Wazuh - The Open Source Security Platform").
  3. Lanjutkan wizard dengan spesifikasi minimal `t3.xlarge`.
- Kelebihan:
  * Siap pakai langsung dalam hitungan menit tanpa proses instalasi manual.
- Kekurangan:
  * Password default dan konfigurasi awal harus direset secara manual via CLI saat pertama login.
  * Versi minor paket sering kali tertinggal dibanding repository resmi apt/yum.

## 6. KONFIGURASI AWS NETWORKING & SECURITY GROUP (PORT MATRIX)

Pada Security Group AWS EC2 (`sg-wazuh-siem`), konfigurasi HANYA mengizinkan 
5 Aturan Inbound (Inbound rules) dari subnet VPC `172.1.0.0/16`.

Tabel berikut merefleksikan konfigurasi Inbound Rules persis sebagaimana 
tampil pada AWS EC2 Management Console (Menu: Edit inbound rules):

| Name | Security group rule ID | IP version | Type | Protocol | Port range | Source | Description |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| – | sgr-0ff249443e5db6867 | IPv4 | HTTPS | TCP | 443 | 172.1.0.0/16 | – |
| – | sgr-04f5d04027d589e5a | IPv4 | Custom TCP | TCP | 1514 | 172.1.0.0/16 | – |
| – | sgr-0b79d4f4dc0801292 | IPv4 | All ICMP - IPv4 | ICMP | All | 172.1.0.0/16 | – |
| – | sgr-0bee8d8aa48b8a1f9 | IPv4 | Custom TCP | TCP | 1515 | 172.1.0.0/16 | – |
| – | sgr-00bd042b36b18d1ad | IPv4 | SSH | TCP | 22 | 172.1.0.0/16 | untuk nanti bisa install agent dan komunikasi ec2 agent akan di install dengan wazuhnya |

PENJELASAN 5 ATURAN INBOUND YANG DIIZINKAN (ALLOW RULES):

1. Rule 1: HTTPS (Port 443 / TCP)
   - Rule ID    : sgr-0ff249443e5db6867
   - Protocol   : TCP
   - Port       : 443
   - Source     : 172.1.0.0/16
   - Deskripsi  : Akses antarmuka web (Wazuh Dashboard Web UI) secara aman via HTTPS 
                  dari browser administrator / bastion host di dalam subnet VPC 172.1.0.0/16.

2. Rule 2: Custom TCP (Port 1514 / TCP)
   - Rule ID    : sgr-04f5d04027d589e5a
   - Protocol   : TCP
   - Port       : 1514
   - Source     : 172.1.0.0/16
   - Deskripsi  : Pengiriman aliran event log terenkripsi secara terus-menerus (Agent event stream) 
                  dari seluruh EC2 target yang telah dipasang Wazuh Agent menuju Wazuh Manager.

3. Rule 3: All ICMP - IPv4 (Protocol ICMP / Port range: All)
   - Rule ID    : sgr-0b79d4f4dc0801292
   - Protocol   : ICMP
   - Port range : All
   - Source     : 172.1.0.0/16
   - Deskripsi  : Mengizinkan request ICMP (Echo Request / Ping, MTU Path Discovery) dari 
                  subnet 172.1.0.0/16 untuk healthcheck dan uji latensi/konektivitas antar-instans.

4. Rule 4: Custom TCP (Port 1515 / TCP)
   - Rule ID    : sgr-0bee8d8aa48b8a1f9
   - Protocol   : TCP
   - Port       : 1515
   - Source     : 172.1.0.0/16
   - Deskripsi  : Port registrasi / enrollment otomatis agent baru (layanan authd). Digunakan saat 
                  pertama kali server target mendaftarkan diri dan meminta enkripsi key ke Manager.

5. Rule 5: SSH (Port 22 / TCP)
   - Rule ID    : sgr-00bd042b36b18d1ad
   - Protocol   : TCP
   - Port       : 22
   - Source     : 172.1.0.0/16
   - Deskripsi  : untuk nanti bisa install agent dan komunikasi ec2 agent akan di install dengan wazuhnya
   - Fungsi     : Akses remote shell SSH dari workstation / bastion internal VPC untuk kebutuhan 
                  administrasi server, eksekusi script deployment agent, instalasi agent secara remote, 
                  dan komunikasi aman antar EC2 instance.

CATATAN PENTING ARSITEKTUR KEAMANAN (SECURITY GROUP HARDENING):
1. HANYA 5 Port Inbound Ini yang Dibuka:
   Semua trafik masuk di luar 5 aturan di atas secara default di-DROP oleh firewall stateful AWS.
2. Mengapa Port 9200 (Indexer) & 55000 (API) TIDAK Ada di Security Group?
   - Port 9200 (Wazuh Indexer REST API) dan Port 55000 (Wazuh API) hanya berjalan pada interface 
     localhost (`127.0.0.1`) di dalam instance EC2 untuk komunikasi antar-layanan internal 
     (Filebeat -> Indexer, Dashboard -> API).
   - Menutup kedua port ini dari Inbound Security Group adalah BEST PRACTICE WAJIB untuk mencegah 
     serangan brute-force dan eksposur data log keamanan mentah ke jaringan luar.
3. Mengapa Port 9300 - 9400 TIDAK Dibuka?
   - Port komunikasi cluster OpenSearch hanya dibutuhkan jika mengoperasikan Indexer multi-node. 
     Pada instalasi All-in-One (Single Node EC2), port ini berjalan murni di localhost tanpa 
     memerlukan rule Inbound di AWS Security Group.
4. Outbound Rules (Egress):
   - Gunakan aturan default AWS Security Group Outbound: `All traffic (0.0.0.0/0)`.
   - Diperlukan agar EC2 Wazuh dapat mengunduh update package OS (dnf / apt), mengunduh update 
     database vulnerability feeds dari internet, dan mengirim data log ke AWS S3 / CloudWatch.

## 7. PERSIAPAN SISTEM OPERASI: OS HARDENING & PRASYARAT KERNEL (AL2023 & UBUNTU)

--- A. PERSIAPAN PADA AMAZON LINUX 2023 (AL2023) ---
Hubungkan via SSH menggunakan user default `ec2-user`:
  ssh -i my-keypair.pem ec2-user@<EC2_PUBLIC_IP>

1. Update sistem dan instal paket utilitas pendukung:
```bash
sudo dnf update -y
# Catatan Penting AL2023: curl sudah terpasang bawaan via 'curl-minimal'.
# Jangan menambahkan 'curl' ke 'dnf install' tanpa flag '--allowerasing' karena akan memicu konflik paket.
sudo dnf install -y tar gzip unzip jq coreutils findutils libxcrypt-compat
# (Atau cukup: sudo dnf install -y libxcrypt-compat karena utilitas lainnya sudah ada secara default di AL2023)
```

2. Konfigurasi Kernel Parameter (Wajib untuk Wazuh Indexer / OpenSearch):
   Wazuh Indexer memerlukan batas mmapfs yang tinggi agar tidak terjadi crash:
```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-wazuh.conf
sudo sysctl --system
```

3. Konfigurasi Batas File Handle (File Descriptors & Memlock):
   Buat file konfigurasi limits khusus untuk Wazuh:
```bash
sudo tee /etc/security/limits.d/99-wazuh.conf << 'EOF'
wazuh-indexer soft nofile 65536
wazuh-indexer hard nofile 65536
wazuh-indexer soft memlock unlimited
wazuh-indexer hard memlock unlimited
EOF
```

4. Konfigurasi Swap Memory (Disarankan untuk stabilitas EC2):
   Jika RAM pas-pasan (8GB - 16GB), buat swap file 4GB untuk mencegah crash OOM:
```bash
sudo dd if=/dev/zero of=/swapfile bs=128M count=32
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
```

--- B. PERSIAPAN PADA UBUNTU SERVER 22.04 LTS ---
Hubungkan via SSH menggunakan user default `ubuntu`:
  ssh -i my-keypair.pem ubuntu@<EC2_PUBLIC_IP>

1. Update sistem dan instal paket utilitas:
```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl apt-transport-https lsb-release gnupg2 tar unzip jq ufw
```

2. Konfigurasi Kernel Parameter (Wajib untuk Wazuh Indexer):
```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

3. Konfigurasi Batas File Handle (File Descriptors):
```bash
sudo tee -a /etc/security/limits.conf << 'EOF'
wazuh-indexer soft nofile 65536
wazuh-indexer hard nofile 65536
wazuh-indexer soft memlock unlimited
wazuh-indexer hard memlock unlimited
EOF
```

4. Konfigurasi Swap (Opsional namun disarankan untuk stabilitas EC2):
```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

## 8. METODE 1: INSTALASI CEPAT (WAZUH ALL-IN-ONE QUICK INSTALLATION DI AL2023 / UBUNTU)

#### Metode ini adalah metode resmi tercepat dan paling stabil yang direkomendasikan

oleh Wazuh untuk arsitektur All-in-One pada satu node EC2.

Script installer `wazuh-install.sh` secara otomatis mendeteksi distribusi Linux, 
baik Amazon Linux 2023 (AL2023) maupun Ubuntu 22.04 LTS, dan mengonfigurasi repository 
serta paket yang sesuai.

Langkah-langkah:

1. Prasyarat Paket:
   - Pada Amazon Linux 2023 (AL2023):
```bash
# Catatan: curl sudah terpasang bawaan via curl-minimal
sudo dnf install -y tar gzip findutils jq libxcrypt-compat
```

   - Pada Ubuntu 22.04 LTS:
```bash
sudo apt-get install -y curl tar gzip jq
```

2. Unduh installer script resmi Wazuh:
```bash
curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
curl -sO https://packages.wazuh.com/4.9/config.yml
```

3. Jalankan installer dengan opsi All-in-One (-a):
```bash
sudo bash ./wazuh-install.sh -a
```

   Catatan: Proses ini memakan waktu sekitar 5 - 10 menit. Script akan otomatis:
   - Mengunduh dan mengonfigurasi root CA dan SSL Certificate lokal.
   - Menginstal Wazuh Indexer & membentuk cluster single-node.
   - Menginstal Wazuh Server & API.
   - Menginstal Wazuh Dashboard.
   - Mengaktifkan dan menjalankan semua systemd service.

4. Menyimpan Kredensial Admin:
   Setelah instalasi selesai, script akan menampilkan informasi login di layar:
   - Web URL : https://<IP_EC2_ATAU_DOMAIN>
   - User    : admin
   - Password: <RANDOM_GENERATED_PASSWORD>

   File kredensial tersimpan dalam arsip terkompresi `wazuh-install-files.tar`.
   Untuk melihat kembali password tanpa mengekstrak seluruh file:
```bash
sudo tar -O -xf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt
```

   SIMPAN PASSWORD INI DI TEMPAT YANG AMAN (misal: AWS Secrets Manager / 1Password).

## 9. METODE 2: INSTALASI MANUAL / STEP-BY-STEP (AMAZON LINUX 2023 & UBUNTU 22.04)

Gunakan metode ini jika Anda membutuhkan kustomisasi mendalam pada konfigurasi 
cluster multi-node, partisi disk terpisah untuk data indexer, atau sertifikat TLS kustom.

```text
--- TAHAP 1: PEMBUATAN SERTIFIKAT SSL (WAZUH CERTS TOOL) ---
```

(Tahap ini berlaku sama baik untuk Amazon Linux 2023 maupun Ubuntu 22.04)

1. Unduh tool sertifikat:
```bash
curl -sO https://packages.wazuh.com/4.9/wazuh-certs-tool.sh
curl -sO https://packages.wazuh.com/4.9/config.yml
```

2. Edit config.yml untuk memasukkan IP Private atau DNS EC2 Anda:
   nano config.yml
   (Isikan node IP untuk indexer, server, dan dashboard).

3. Generate sertifikat:
```bash
bash ./wazuh-certs-tool.sh -A
tar -cvf ./wazuh-certificates.tar ./wazuh-certificates
```

```bash
--- TAHAP 2: INSTALASI MANUAL PADA AMAZON LINUX 2023 (AL2023 - DNF / RPM) ---
```

1. Tambahkan Repository Resmi Wazuh (YUM/DNF) & GPG Key:
```bash
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
sudo tee /etc/yum.repos.d/wazuh.repo << 'EOF'
```

[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

2. Instalasi & Konfigurasi Wazuh Indexer di AL2023:
   a. Instal paket wazuh-indexer:
```bash
sudo dnf install -y wazuh-indexer
```

   b. Salin sertifikat SSL Indexer:
```bash
NODE_NAME="node-1" # Sesuaikan dengan nama di config.yml
sudo mkdir -p /etc/wazuh-indexer/certs
sudo tar -xf ./wazuh-certificates.tar -C /etc/wazuh-indexer/certs/ \
```

        ./wazuh-certificates/${NODE_NAME}.pem \
        ./wazuh-certificates/${NODE_NAME}-key.pem \
        ./wazuh-certificates/root-ca.pem --strip-components=2
```bash
sudo chmod 500 /etc/wazuh-indexer/certs
sudo chmod 400 /etc/wazuh-indexer/certs/*
sudo chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs
```

   c. Sesuaikan JVM Heap Size di `/etc/wazuh-indexer/jvm.options`:
      Alokasikan 50% dari total kapasitas RAM instance (contoh: RAM 16GB -> 8GB):
      -Xms8g
      -Xmx8g

   d. Aktifkan dan jalankan service wazuh-indexer:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-indexer
```

   e. Inisialisasi Security Cluster Indexer:
```bash
sudo /usr/share/wazuh-indexer/bin/indexer-security-admin.sh
```

3. Instalasi & Konfigurasi Wazuh Server (Manager) di AL2023:
   a. Instal paket wazuh-manager:
```bash
sudo dnf install -y wazuh-manager
```

   b. Aktifkan dan jalankan service wazuh-manager:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-manager
sudo systemctl status wazuh-manager
```

4. Instalasi & Konfigurasi Filebeat di AL2023:
   a. Instal paket Filebeat dari repository Wazuh:
```bash
sudo dnf install -y filebeat
```

   b. Unduh file konfigurasi template resmi:
```bash
curl -so /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.9/tpl/wazuh/filebeat/filebeat.yml
curl -so /etc/filebeat/wazuh-template.json https://packages.wazuh.com/4.9/wazuh-template.json
sudo chmod go+r /etc/filebeat/wazuh-template.json
```

   c. Salin sertifikat SSL Filebeat:
```bash
sudo mkdir -p /etc/filebeat/certs
sudo tar -xf ./wazuh-certificates.tar -C /etc/filebeat/certs/ \
```

        ./wazuh-certificates/${NODE_NAME}.pem \
        ./wazuh-certificates/${NODE_NAME}-key.pem \
        ./wazuh-certificates/root-ca.pem --strip-components=2
```bash
sudo chmod 500 /etc/filebeat/certs
sudo chmod 400 /etc/filebeat/certs/*
sudo chown -R root:root /etc/filebeat/certs
```

   d. Aktifkan dan jalankan service Filebeat:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now filebeat
```

5. Instalasi & Konfigurasi Wazuh Dashboard di AL2023:
   a. Instal paket wazuh-dashboard:
```bash
sudo dnf install -y wazuh-dashboard
```

   b. Salin sertifikat SSL Dashboard:
```bash
sudo mkdir -p /etc/wazuh-dashboard/certs
sudo tar -xf ./wazuh-certificates.tar -C /etc/wazuh-dashboard/certs/ \
```

        ./wazuh-certificates/${NODE_NAME}.pem \
        ./wazuh-certificates/${NODE_NAME}-key.pem \
        ./wazuh-certificates/root-ca.pem --strip-components=2
```bash
sudo chmod 500 /etc/wazuh-dashboard/certs
sudo chmod 400 /etc/wazuh-dashboard/certs/*
sudo chown -R wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/certs
```

   c. Aktifkan dan jalankan service wazuh-dashboard:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-dashboard
```

```text
--- TAHAP 3: INSTALASI MANUAL PADA UBUNTU SERVER 22.04 LTS (APT / DEB) ---
```

1. Tambahkan Repository Resmi Wazuh (APT) & GPG Key:
```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && sudo chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee -a /etc/apt/sources.list.d/wazuh.list
sudo apt-get update
```

2. Instalasi & Konfigurasi Wazuh Indexer di Ubuntu:
```bash
sudo apt-get install -y wazuh-indexer
NODE_NAME="node-1"
sudo mkdir -p /etc/wazuh-indexer/certs
sudo tar -xf ./wazuh-certificates.tar -C /etc/wazuh-indexer/certs/ \
```

     ./wazuh-certificates/${NODE_NAME}.pem \
     ./wazuh-certificates/${NODE_NAME}-key.pem \
     ./wazuh-certificates/root-ca.pem --strip-components=2
```bash
sudo chmod 500 /etc/wazuh-indexer/certs
sudo chmod 400 /etc/wazuh-indexer/certs/*
sudo chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer/certs
# Sesuaikan JVM Heap Size di /etc/wazuh-indexer/jvm.options (-Xms8g, -Xmx8g)
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-indexer
sudo /usr/share/wazuh-indexer/bin/indexer-security-admin.sh
```

3. Instalasi & Konfigurasi Wazuh Server (Manager) & Filebeat di Ubuntu:
```bash
sudo apt-get install -y wazuh-manager
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-manager

sudo apt-get install -y filebeat
curl -so /etc/filebeat/filebeat.yml https://packages.wazuh.com/4.9/tpl/wazuh/filebeat/filebeat.yml
curl -so /etc/filebeat/wazuh-template.json https://packages.wazuh.com/4.9/wazuh-template.json
sudo chmod go+r /etc/filebeat/wazuh-template.json

sudo mkdir -p /etc/filebeat/certs
sudo tar -xf ./wazuh-certificates.tar -C /etc/filebeat/certs/ \
```

     ./wazuh-certificates/${NODE_NAME}.pem \
     ./wazuh-certificates/${NODE_NAME}-key.pem \
     ./wazuh-certificates/root-ca.pem --strip-components=2
```bash
sudo chmod 500 /etc/filebeat/certs
sudo chmod 400 /etc/filebeat/certs/*
sudo chown -R root:root /etc/filebeat/certs
sudo systemctl daemon-reload
sudo systemctl enable --now filebeat
```

4. Instalasi & Konfigurasi Wazuh Dashboard di Ubuntu:
```bash
sudo apt-get install -y wazuh-dashboard
sudo mkdir -p /etc/wazuh-dashboard/certs
sudo tar -xf ./wazuh-certificates.tar -C /etc/wazuh-dashboard/certs/ \
```

     ./wazuh-certificates/${NODE_NAME}.pem \
     ./wazuh-certificates/${NODE_NAME}-key.pem \
     ./wazuh-certificates/root-ca.pem --strip-components=2
```bash
sudo chmod 500 /etc/wazuh-dashboard/certs
sudo chmod 400 /etc/wazuh-dashboard/certs/*
sudo chown -R wazuh-dashboard:wazuh-dashboard /etc/wazuh-dashboard/certs
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-dashboard
```

## 10. METODE 3: ZERO-TOUCH DEPLOYMENT MENGGUNAKAN EC2 USER DATA (CLOUD-INIT)

Jika Anda ingin instance EC2 otomatis menginstal Wazuh secara penuh saat pertama kali 
booting (tanpa perlu SSH manual), tempelkan script berikut pada kolom "User Data" 
(Advanced Details) saat proses launch instance di AWS:

--- OPSI A: USER DATA SCRIPT UNTUK AMAZON LINUX 2023 (AL2023) ---
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "[1/4] Mengatur parameter kernel & swap di Amazon Linux 2023..."
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" > /etc/sysctl.d/99-wazuh.conf

dd if=/dev/zero of=/swapfile bs=128M count=32
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile swap swap defaults 0 0' >> /etc/fstab

echo "[2/4] Mengupdate paket dan mengunduh Wazuh installer..."
# Catatan: hindari mencantumkan 'curl' agar dnf tidak bentrok dengan curl-minimal bawaan AL2023
dnf update -y && dnf install -y tar gzip findutils jq libxcrypt-compat

cd /root
curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
curl -sO https://packages.wazuh.com/4.9/config.yml

echo "[3/4] Menjalankan instalasi All-in-One..."
bash ./wazuh-install.sh -a

echo "[4/4] Menyimpan password ke file terproteksi..."
tar -O -xf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt > /root/wazuh-credentials.txt
chmod 600 /root/wazuh-credentials.txt

# Salin juga ke home ec2-user agar langsung dapat diakses setelah login SSH
cp /root/wazuh-credentials.txt /home/ec2-user/wazuh-credentials.txt
chown ec2-user:ec2-user /home/ec2-user/wazuh-credentials.txt
chmod 600 /home/ec2-user/wazuh-credentials.txt

echo "Instalasi Wazuh All-in-One di Amazon Linux 2023 Selesai!"

--- OPSI B: USER DATA SCRIPT UNTUK UBUNTU SERVER 22.04 LTS ---
#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "[1/4] Mengatur parameter kernel & swap di Ubuntu..."
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

echo "[2/4] Mengupdate OS dan mengunduh Wazuh installer..."
apt-get update -y && apt-get install -y curl tar gzip jq

cd /root
curl -sO https://packages.wazuh.com/4.9/wazuh-install.sh
curl -sO https://packages.wazuh.com/4.9/config.yml

echo "[3/4] Menjalankan instalasi All-in-One..."
bash ./wazuh-install.sh -a

echo "[4/4] Menyimpan password ke file terproteksi..."
tar -O -xf wazuh-install-files.tar wazuh-install-files/wazuh-passwords.txt > /root/wazuh-credentials.txt
chmod 600 /root/wazuh-credentials.txt

# Salin juga ke home ubuntu
cp /root/wazuh-credentials.txt /home/ubuntu/wazuh-credentials.txt
chown ubuntu:ubuntu /home/ubuntu/wazuh-credentials.txt
chmod 600 /home/ubuntu/wazuh-credentials.txt

echo "Instalasi Wazuh All-in-One di Ubuntu 22.04 LTS Selesai!"

## 11. AKSES WAZUH DASHBOARD & MANAJEMEN KREDENSIAL

1. Buka browser dan arahkan ke alamat IP Publik EC2 atau Public DNS Anda:
```text
https://<EC2_PUBLIC_IP>
```

2. Peringatan SSL (Self-Signed):
   Browser akan menampilkan peringatan "Your connection is not private".
   Klik "Advanced" -> "Proceed to ... (unsafe)" untuk tahap awal.

3. Login menggunakan:
```text
Username: admin
Password: <Password_dari_wazuh-passwords.txt>
```

4. Mengganti Password Default User 'admin':
   Sangat direkomendasikan untuk mengganti password bawaan setelah instalasi:
   
#### A. Jalankan script pengganti hash password:

```bash
sudo /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p "PasswordBaruAnda123!@#"
```

   
#### B. Output akan menghasilkan string hash baru, contoh:

      $2y$12$e0M2FkX3...
   
#### C. Edit file internal_users.yml:

```bash
sudo nano /etc/wazuh-indexer/opensearch-security/internal_users.yml
```

      Temukan blok `admin:`, ganti nilai `hash` dengan hash baru tersebut.
   
#### D. Terapkan perubahan ke cluster Indexer:

```bash
sudo /usr/share/wazuh-indexer/bin/indexer-security-admin.sh
```

## 12. KONFIGURASI SSL/TLS, CUSTOM DOMAIN & REVERSE PROXY NGINX / AWS ALB

Untuk lingkungan production di AWS, hindari mengakses IP langsung dengan port 
self-signed certificate. Gunakan salah satu opsi berikut:

#### OPSI A: MENGGUNAKAN AWS APPLICATION LOAD BALANCER (ALB) + AWS ACM (SANGAT DIREKOMENDASIKAN)

1. Request sertifikat SSL publik gratis di AWS Certificate Manager (ACM) untuk domain Anda 
   (misal: `wazuh.perusahaan.com`).
2. Buat Target Group di AWS:
   - Target type: Instance (pilih instance EC2 Wazuh).
   - Protocol: HTTPS, Port: 443 (Dashboard).
   - Health check path: `/` (Port 443, matcher: 200, 302).
3. Buat ALB (Application Load Balancer):
   - Listener HTTPS: 443 -> Forward ke Target Group Wazuh.
   - Pasang sertifikat ACM pada ALB.
4. Update DNS di Route 53 mengarah ke DNS Name ALB.
5. Pada Security Group EC2, izinkan port 443 HANYA dari Security Group milik ALB.

#### OPSI B: MENGGUNAKAN REVERSE PROXY NGINX & LET'S ENCRYPT CERTBOT (AL2023 & UBUNTU)

Jika tidak menggunakan ALB, Anda dapat memasang Nginx langsung di instance EC2:

1. Ubah port binding Wazuh Dashboard di `/etc/wazuh-dashboard/opensearch_dashboards.yml`:
```bash
server.port: 5601
server.host: "127.0.0.1"
sudo systemctl restart wazuh-dashboard
```

2. Setup Nginx & Certbot sesuai OS:

```text
--- JIKA MENGGUNAKAN AMAZON LINUX 2023 (AL2023) ---
```

   a. Instal Nginx & Python PIP:
```bash
sudo dnf install -y nginx python3-pip
```

   b. Buat konfigurasi server block di `/etc/nginx/conf.d/wazuh.conf`:
```bash
sudo tee /etc/nginx/conf.d/wazuh.conf << 'EOF'
```

server {
```haproxy
listen 80;
```

    server_name wazuh.domainanda.com;

```nginx
location / {
```

        proxy_pass https://127.0.0.1:5601;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
```text
}
```

}
EOF

   c. Instal Certbot via Virtual Environment Python (Standar Resmi AL2023):
```bash
sudo python3 -m venv /opt/certbot/
sudo /opt/certbot/bin/pip install --upgrade pip
sudo /opt/certbot/bin/pip install certbot certbot-nginx
sudo ln -sf /opt/certbot/bin/certbot /usr/bin/certbot
```

   d. Aktifkan Nginx & Request SSL Certbot:
```bash
   sudo systemctl enable --now nginx
   sudo certbot --nginx -d wazuh.domainanda.com

--- JIKA MENGGUNAKAN UBUNTU SERVER 22.04 LTS ---
```

   a. Instal Nginx & Certbot via APT:
```bash
sudo apt-get install -y nginx certbot python3-certbot-nginx
```

   b. Konfigurasi Nginx Server Block (`/etc/nginx/sites-available/wazuh.conf`):
```bash
sudo tee /etc/nginx/sites-available/wazuh.conf << 'EOF'
```

server {
```haproxy
listen 80;
```

    server_name wazuh.domainanda.com;

```nginx
location / {
```

        proxy_pass https://127.0.0.1:5601;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_ssl_verify off;
```text
}
```

}
EOF

   c. Enable site & generate SSL gratis dari Let's Encrypt:
```bash
sudo ln -sf /etc/nginx/sites-available/wazuh.conf /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d wazuh.domainanda.com
```

## 13. PEMBUATAN CUSTOM GOLDEN AMI DARI INSTANCE WAZUH (SYSPREP & IMAGE CAPTURE)

Setelah server Wazuh berjalan normal dan selesai dikonfigurasi, Anda dapat 
membuat "Golden AMI" kustom. Golden AMI berguna untuk:
- Backup cepat seluruh sistem (Disaster Recovery).
- Menjalankan instance baru di Region/AZ lain secara instan tanpa perlu instalasi ulang.
- Digunakan pada AWS EC2 Auto Recovery atau Launch Template.

Langkah-langkah Pembuatan Golden AMI:

#### Langkah 1: Sysprep & Pembersihan Instance (Generalization)

Masuk via SSH ke server Wazuh dan jalankan pembersihan:
1. Hentikan service Wazuh sementara:
```bash
sudo systemctl stop wazuh-dashboard wazuh-manager filebeat wazuh-indexer
```

2. Bersihkan paket cache & log temporer:
   - Jika Amazon Linux 2023 (AL2023):
```bash
sudo dnf clean all
sudo rm -rf /tmp/* /var/tmp/* /var/log/dnf*
```

   - Jika Ubuntu 22.04 LTS:
```bash
sudo apt-get clean
sudo rm -rf /tmp/* /var/tmp/*
```

3. Bersihkan SSH Host Keys dan Authorized Keys (Agar key baru digenerate saat launch instance baru):
```bash
sudo rm -f /etc/ssh/ssh_host_*
```

   - Jika Amazon Linux 2023:
```bash
sudo shred -u /home/ec2-user/.ssh/authorized_keys
```

   - Jika Ubuntu 22.04 LTS:
```bash
sudo shred -u /home/ubuntu/.ssh/authorized_keys
```

4. Bersihkan Machine ID Linux (Agar instance baru mendapat machine-id unik dari DHCP AWS):
```bash
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
```

5. Bersihkan riwayat terminal:
   history -c && history -w

#### Langkah 2: Matikan Instance (Stop EC2)

- Di AWS Console, pilih instance `wazuh-siem-al2023` (atau `wazuh-siem-production`) -> Instance State -> "Stop instance".
- Atau via AWS CLI:
```bash
aws ec2 stop-instances --instance-ids <INSTANCE_ID>
aws ec2 wait instance-stopped --instance-ids <INSTANCE_ID>
```

#### Langkah 3: Capture AMI (Create Image)

- Via AWS Console:
  Klik kanan pada instance -> Image and templates -> "Create image".
  * Image name: `wazuh-all-in-one-golden-v4.9`
  * Image description: `Custom Wazuh All-in-One (AL2023 / Ubuntu) with pre-tuned OS parameters`
  * No reboot: Biarkan default (Unchecked)
  * Klik "Create image".
- Via AWS CLI:
```bash
IMAGE_ID=$(aws ec2 create-image \
  --instance-id <INSTANCE_ID> \
  --name "wazuh-all-in-one-golden-v4.9" \
  --description "Custom Golden Image Wazuh v4.9" \
  --query 'ImageId' --output text)
echo "Golden AMI dibuat: $IMAGE_ID"
```

#### Langkah 4: Menjalankan Instance Baru dari Golden AMI

Kapan pun Anda membutuhkan replika atau recovery:
- Masuk ke menu EC2 -> AMIs -> Pilih `wazuh-all-in-one-golden-v4.9` -> Klik "Launch instance from AMI".
- Pilih tipe `t3.xlarge` / `m6i.xlarge` dan pasang Security Group yang sama.
- Instance langsung menyala dengan seluruh komponen Wazuh yang sudah terkonfigurasi!

## 14. INSTALASI & REGISTRASI WAZUH AGENT MULTI-PLATFORM (FULL DETAIL)

Wazuh Agent dapat didaftarkan langsung via Web UI (Wazuh Dashboard -> Endpoints 
Summary -> Deploy new agent) atau menggunakan baris perintah otomatis di bawah ini.

(Catatan: Untuk panduan khusus modul FIM, SCA, Active Response, macOS & Docker Host, 
lihat dokumen pendamping lengkap: `wazuh_agent_install_guide.txt`).

--- A. PRASYARAT KONEKTIVITAS JARINGAN ---
Sebelum instalasi, pastikan server agent dapat menjangkau Wazuh Manager:
- Port TCP 1515: Layanan registrasi awal (Authd).
- Port TCP 1514: Layanan pengiriman log & event terenkripsi.
Uji dari server target: `nc -zvw3 <IP_WAZUH_MANAGER> 1514`

--- B. PADA TARGET INSTANCE LINUX (UBUNTU / DEBIAN) ---
1. Import GPG Key resmi:
```bash
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
sudo chmod 644 /usr/share/keyrings/wazuh.gpg
```

2. Tambahkan repository APT:
```bash
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt-get update
```

3. Instal Agent dengan parameter Manager:
```bash
sudo WAZUH_MANAGER='<IP_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='default' \
     WAZUH_AGENT_NAME='web-ubuntu-prod-01' \
```

        apt-get install -y wazuh-agent

4. Enable & jalankan service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
sudo systemctl status wazuh-agent
```

--- C. PADA TARGET INSTANCE LINUX (AMAZON LINUX 2023 / RHEL / ROCKY / ALMALINUX) ---
1. Import GPG Key dan buat repository YUM/DNF:
```bash
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
sudo tee /etc/yum.repos.d/wazuh.repo << 'EOF'
```

[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

2. Instal Agent via DNF (Amazon Linux 2023) atau YUM:
```bash
sudo WAZUH_MANAGER='<IP_WAZUH_MANAGER>' \
     WAZUH_AGENT_GROUP='default' \
     WAZUH_AGENT_NAME='ec2-al2023-prod-01' \
     dnf install -y wazuh-agent
```

3. Enable & jalankan service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent
sudo systemctl status wazuh-agent
```

--- D. PADA TARGET INSTANCE MICROSOFT WINDOWS SERVER (POWERSHELL) ---
1. Buka PowerShell sebagai Administrator.
2. Jalankan script instalasi silent:
   $WazuhManager = "<IP_WAZUH_MANAGER>"
   $AgentName    = "win-server-prod-01"
   $InstallerUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.9.0-1.msi"
   $Destination  = "$env:TEMP\wazuh-agent.msi"

   [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
   Invoke-WebRequest -Uri $InstallerUrl -OutFile $Destination

   $Args = "/i `"$Destination`" /qn WAZUH_MANAGER=`"$WazuhManager`" WAZUH_REGISTRATION_SERVER=`"$WazuhManager`" WAZUH_AGENT_NAME=`"$AgentName`""
   Start-Process msiexec.exe -ArgumentList $Args -Wait

   Start-Service -Name "WazuhSvc"
   Set-Service -Name "WazuhSvc" -StartupType Automatic

--- E. VERIFIKASI DARI SISI WAZUH MANAGER ---
1. Periksa daftar seluruh agent yang terhubung:
```bash
sudo /var/ossec/bin/agent_control -l
```

2. Periksa rincian data 1 agent:
```bash
sudo /var/ossec/bin/agent_control -i 001
```

## 15. INTEGRASI WAZUH DENGAN LAYANAN AWS (CLOUDTRAIL & GUARDDUTY)

Wazuh dapat menarik log langsung dari AWS S3 Bucket yang berisi rekaman AWS 
CloudTrail, VPC Flow Logs, atau AWS GuardDuty.

Langkah-langkah Setup:

1. Buat IAM Role untuk EC2 Wazuh:
   - Buat IAM Role dengan tipe AWS Service: EC2.
   - Berikan policy permissions read-only ke S3 bucket CloudTrail Anda:
     {
       "Version": "2012-10-17",
       "Statement": [
         {
           "Effect": "Allow",
           "Action": [
             "s3:GetObject",
             "s3:ListBucket"
           ],
           "Resource": [
             "arn:aws:s3:::nama-bucket-cloudtrail-anda",
             "arn:aws:s3:::nama-bucket-cloudtrail-anda/*"
           ]
```text
    }
  ]
}
```

   - Attach IAM Role ini ke instance EC2 Wazuh Manager (EC2 -> Actions -> Security -> Modify IAM Role).

2. Instal dependencies AWS pada Wazuh Server:
```bash
sudo /var/ossec/framework/python/bin/pip3 install boto3
```

3. Konfigurasi Module AWS di Wazuh Manager (`/var/ossec/etc/ossec.conf`):
   Buka file konfigurasi:
```bash
sudo nano /var/ossec/etc/ossec.conf
```

   Tambahkan blok konfigurasi berikut di dalam tag `<ossec_config>`:
   <wodle name="aws-s3">
     <disabled>no</disabled>
     <interval>10m</interval>
     <run_on_start>yes</run_on_start>
     <skip_on_error>yes</skip_on_error>
     
     <!-- Integrasi CloudTrail -->
     <service type="cloudtrail">
       <bucket name="nama-bucket-cloudtrail-anda"></bucket>
     </service>
   </wodle>

4. Restart Wazuh Manager:
```bash
sudo systemctl restart wazuh-manager
```

5. Cek log pengolahan AWS di ossec.log:
```bash
sudo grep "aws-s3" /var/ossec/logs/ossec.log
```

## 16. MAINTENANCE, BACKUP DATA & LOG ROTATION

1. Manajemen Retensi Index (Mencegah Disk EBS Penuh):
   Secara default, log yang diindeks oleh Indexer akan terus bertambah. 
   Konfigurasikan Index State Management (ISM) pada Wazuh Dashboard:
   - Masuk ke Dashboard -> Index Management -> State Management Policies.
   - Atur rollover policy (contoh: hapus index setelah 60 hari atau pindahkan 
     ke cold storage).

2. Backup Konfigurasi Wazuh Manager:
   Buat script cron otomatis untuk membackup file konfigurasi utama:
```bash
sudo tar -czf /backup/wazuh_config_$(date +%F).tar.gz \
  /var/ossec/etc/ossec.conf \
  /var/ossec/etc/client.keys \
  /var/ossec/etc/rules/local_rules.xml \
  /var/ossec/etc/decoders/local_decoder.xml
```

3. Snapshot EBS Otomatis di AWS:
   Gunakan layanan AWS Data Lifecycle Manager (DLM) untuk membuat Snapshot 
   harian dari EBS volume EC2 Wazuh secara otomatis untuk disaster recovery.

## 17. TROUBLESHOOTING MASALAH UMUM

#### A. Service Wazuh Indexer Gagal Start (Failed / Crash Loop)

   - Penyebab: Memori RAM tidak mencukupi atau nilai `vm.max_map_count` belum diset.
   - Diagnosa:
```bash
sudo systemctl status wazuh-indexer
sudo journalctl -u wazuh-indexer -e --no-pager
sudo cat /var/log/wazuh-indexer/wazuh-cluster.log | tail -n 50
```

   - Solusi:
     * Cek `sysctl vm.max_map_count`. Pastikan bernilai 262144.
     * Cek `/etc/wazuh-indexer/jvm.options`, kurangi ukuran heap jika RAM fisik kecil 
       (misal: ubah dari 8g ke 4g atau 2g).

#### B. Wazuh Dashboard Status "Wazuh server is down" / API Connection Error

   - Penyebab: Wazuh Manager atau Filebeat belum berjalan, atau credentials API 
     pada dashboard tidak cocok.
   - Solusi:
     * Cek apakah API merespons:
```bash
curl -k -u admin:<password> https://127.0.0.1:55000/
```

     * Periksa status manager:
```bash
sudo /var/ossec/bin/wazuh-control status
```

#### C. Agent Berstatus "Never Connected" atau "Disconnected"

   - Penyebab: Security Group AWS memblokir port 1514/1515, atau konfigurasi IP 
     Manager salah di sisi Agent.
   - Diagnosa di sisi Agent:
```bash
sudo cat /var/ossec/logs/ossec.log | tail -n 30
```

   - Tes konektivitas dari server Agent ke Manager:
```text
nc -zvw3 <IP_WAZUH_MANAGER> 1514
nc -zvw3 <IP_WAZUH_MANAGER> 1515
```

   - Solusi:
     * Pastikan Inbound Rule Security Group EC2 mengizinkan port 1514 dan 1515.
     * Pastikan file `/var/ossec/etc/ossec.conf` pada agent mencantumkan IP manager yang benar 
       di dalam tag `<address>...</address>`.

#### D. Disk EBS Menjadi Penuh (100% Usage)

   - Cek penggunaan partisi:
```text
df -h
```

   - Hapus arsip log lama yang belum terkompresi jika darurat:
```bash
sudo rm -rf /var/ossec/logs/archives/archives.log
sudo find /var/ossec/logs/alerts/ -type f -name "*.log" -mtime +30 -delete
```

E. Error Konflik Paket 'curl-minimal' vs 'curl' Saat dnf install di Amazon Linux 2023
   - Gejala / Pesan Error:
```text
Problem: problem with installed package curl-minimal-...
```

     - package curl-minimal-... from @System conflicts with curl provided by curl-...
     (try to add '--allowerasing' to command line to replace conflicting packages)
   - Penyebab:
     Amazon Linux 2023 secara default menyertakan paket `curl-minimal` untuk efisiensi ukuran OS.
     Paket `curl` standar dan `curl-minimal` saling berkonflik di repository RPM AL2023. 
     Jika Anda meminta dnf menginstal `curl` tanpa izin menghapus `curl-minimal`, DNF akan menolak transaksi.
   - Solusi:
     * Opsi 1 (Sangat Direkomendasikan): Hapus kata 'curl' dari perintah install karena perintah curl sudah siap pakai:
```bash
sudo dnf install -y libxcrypt-compat
atau:
sudo dnf install -y tar gzip unzip jq coreutils findutils libxcrypt-compat
```

     * Opsi 2: Jika memang ingin mengganti curl-minimal menjadi paket curl versi lengkap, sertakan flag '--allowerasing':
```bash
sudo dnf install -y --allowerasing curl tar gzip unzip jq coreutils findutils libxcrypt-compat
```

#### F. Gagal Akses Port 443 Wazuh Dashboard via SSH Tunnel / Bastion Host

   - Gejala:
     Connection refused, Permission denied saat tunnel dibuka, ERR_EMPTY_RESPONSE di browser,
     atau channel administratively prohibited.
   - Solusi Cepat:
     1. Gunakan port lokal > 1024 (misal: `-L 8443:<IP_PRIVATE_WAZUH>:443`) karena port 443 
        lokal butuh hak akses root/sudo di Linux/macOS.
     2. Di browser, wajib gunakan skema `https://localhost:8443` (bukan `http://`).
     3. Pastikan Security Group Wazuh mengizinkan Inbound TCP 443 dari SG/IP Bastion.
     4. Pastikan `AllowTcpForwarding yes` di `/etc/ssh/sshd_config` server Bastion.
     (Panduan lengkap & alternatif AWS SSM port forwarding tanpa bastion: 
      lihat 'wazuh_keterangan_tambahan.txt' Bab 12).

## 18. CHEAT SHEET PERINTAH CLI & LOKASI LOG PENTING

--- PERINTAH KONTROL SERVICE ---
Periksa status seluruh service:
```bash
sudo systemctl status wazuh-indexer
sudo systemctl status wazuh-manager
sudo systemctl status filebeat
sudo systemctl status wazuh-dashboard
```

Restart seluruh stack Wazuh:
```bash
sudo systemctl restart wazuh-indexer
sudo systemctl restart wazuh-manager
sudo systemctl restart filebeat
sudo systemctl restart wazuh-dashboard
```

Kontrol internal Wazuh Manager via CLI:
```bash
sudo /var/ossec/bin/wazuh-control status
sudo /var/ossec/bin/wazuh-control restart
```

Melihat daftar agent terdaftar via CLI:
```bash
sudo /var/ossec/bin/agent_control -l
```

--- LOKASI FILE KONFIGURASI PENTING ---
Wazuh Manager Konfigurasi : /var/ossec/etc/ossec.conf
Wazuh Agent List & Keys   : /var/ossec/etc/client.keys
Custom Detection Rules    : /var/ossec/etc/rules/local_rules.xml
Custom Decoders           : /var/ossec/etc/decoders/local_decoder.xml
Wazuh Indexer Konfigurasi : /etc/wazuh-indexer/opensearch.yml
Wazuh Dashboard Konfig    : /etc/wazuh-dashboard/opensearch_dashboards.yml
Filebeat Konfigurasi      : /etc/filebeat/filebeat.yml

--- LOKASI LOG UNTUK AUDIT & TROUBLESHOOTING ---
Manager Master Log        : /var/ossec/logs/ossec.log
Security Alerts Log       : /var/ossec/logs/alerts/alerts.json
Wazuh API Log             : /var/ossec/logs/api.log
Wazuh Indexer Cluster Log : /var/log/wazuh-indexer/wazuh-cluster.log
Wazuh Dashboard System Log: journalctl -u wazuh-dashboard -f
Wazuh Agent Log           : /var/ossec/logs/ossec.log

## AKHIR DARI PANDUAN
