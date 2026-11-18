#!/usr/bin/env bash
# ==============================================================================
# Script Name   : install_wazuh_server.sh
# Description   : Universal Automated Installer for Wazuh Server v4.14 (All-in-One:
#                 Wazuh Indexer, Wazuh Manager, Filebeat, and Wazuh Dashboard)
# Target Version: Wazuh v4.14.x (Latest: 4.14.10)
# Supported OS  : - Ubuntu 18.04 LTS, 20.04 LTS, 22.04 LTS, 24.04 LTS (Latest)
#                 - Debian 10 (Buster), 11 (Bullseye), 12 (Bookworm)
#                 - Red Hat Enterprise Linux (RHEL) 7, 8, 9, 10
#                 - Oracle Linux 7, 8, 9
#                 - AlmaLinux 8, 9, 10 / Rocky Linux 8, 9 / CentOS 7, 8, 9 Stream
#                 - Amazon Linux 2 (AL2) & Amazon Linux 2023 (AL2023)
# Architecture  : x86_64 (amd64) / aarch64 (arm64)
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Formatting & Colors
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_header() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
}

# ------------------------------------------------------------------------------
# Default Settings & Flags
# ------------------------------------------------------------------------------
WAZUH_VERSION="4.14"
FORCE_INSTALL=false
AUTO_FIREWALL=false
CHECK_ONLY=false
INSTALL_DIR="/tmp/wazuh_server_install_$$"

# ------------------------------------------------------------------------------
# Help & Usage
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Universal Automated Installer Script for Wazuh Server v4.14 (All-in-One).

OPTIONS:
  -f, --force            Bypass hardware resource checks (RAM, CPU cores, Disk).
  -o, --open-firewall    Automatically configure local firewall (firewalld / ufw)
                         for ports 1514, 1515, 443, and 55000.
  -c, --check-only       Perform pre-flight checks and exit without installing.
  -h, --help             Display this help message and exit.

SUPPORTED OPERATING SYSTEMS:
  * Ubuntu 18.04, 20.04, 22.04, 24.04 (Latest)
  * Debian 10, 11, 12
  * RHEL 7, 8, 9, 10 / CentOS 7, 8, 9 Stream
  * Oracle Linux 7, 8, 9
  * AlmaLinux 8, 9, 10 / Rocky Linux 8, 9
  * Amazon Linux 2 & Amazon Linux 2023

EXAMPLES:
  # Standar All-in-One installation:
  sudo bash $(basename "$0")

  # Install with automatic firewall port opening:
  sudo bash $(basename "$0") --open-firewall

  # Force installation on low-resource VM (e.g. testing lab < 4GB RAM):
  sudo bash $(basename "$0") --force --open-firewall
EOF
}

# ------------------------------------------------------------------------------
# CLI Argument Parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE_INSTALL=true
            shift
            ;;
        -o|--open-firewall)
            AUTO_FIREWALL=true
            shift
            ;;
        -c|--check-only)
            CHECK_ONLY=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Pre-flight Check: Root Permissions
# ------------------------------------------------------------------------------
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be executed as root or with sudo privileges."
        echo "Example: sudo bash $0"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# OS & Distribution Detection
# ------------------------------------------------------------------------------
detect_os() {
    log_header "Detecting Operating System & Hardware Platform"
    
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
        log_error "Unsupported system architecture: $ARCH. Wazuh Server requires x86_64 or aarch64."
        exit 1
    fi
    log_info "System Architecture: ${BOLD}${ARCH}${NC}"

    OS_ID=""
    OS_VERSION=""
    OS_PRETTY_NAME=""
    PKG_MGR=""

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-0}"
        OS_PRETTY_NAME="${PRETTY_NAME:-$OS_ID}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_PRETTY_NAME=$(cat /etc/redhat-release)
        if grep -qi "centos" /etc/redhat-release; then
            OS_ID="centos"
        elif grep -qi "oracle" /etc/redhat-release; then
            OS_ID="ol"
        elif grep -qi "almalinux" /etc/redhat-release; then
            OS_ID="almalinux"
        elif grep -qi "rocky" /etc/redhat-release; then
            OS_ID="rocky"
        else
            OS_ID="rhel"
        fi
        OS_VERSION=$(sed -rn 's/.* ([0-9]+)\..*/\1/p' /etc/redhat-release)
    elif [[ -f /etc/debian_version ]]; then
        OS_ID="debian"
        OS_VERSION=$(cat /etc/debian_version)
        OS_PRETTY_NAME="Debian $OS_VERSION"
    else
        log_error "Unable to detect Linux distribution from standard release files."
        exit 1
    fi

    # Determine Package Manager and Normalization
    case "$OS_ID" in
        ubuntu|debian)
            PKG_MGR="apt"
            ;;
        rhel|centos|rocky|almalinux|ol)
            if command -v dnf >/dev/null 2>&1; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            ;;
        amzn)
            if [[ "$OS_VERSION" == "2023" ]] || command -v dnf >/dev/null 2>&1; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            ;;
        *)
            # Check by package manager availability
            if command -v apt-get >/dev/null 2>&1; then
                PKG_MGR="apt"
            elif command -v dnf >/dev/null 2>&1; then
                PKG_MGR="dnf"
            elif command -v yum >/dev/null 2>&1; then
                PKG_MGR="yum"
            else
                log_error "Unsupported Linux distribution ($OS_ID). Neither apt, dnf, nor yum was found."
                exit 1
            fi
            ;;
    esac

    log_success "Operating System : ${BOLD}${OS_PRETTY_NAME}${NC}"
    log_info    "Distribution ID : ${OS_ID}"
    log_info    "Version ID      : ${OS_VERSION}"
    log_info    "Package Manager : ${PKG_MGR}"
}

# ------------------------------------------------------------------------------
# Hardware & Resource Specifications Check
# ------------------------------------------------------------------------------
check_system_resources() {
    log_header "Validating System Hardware Resources"
    
    # 1. CPU Cores Check
    CPU_CORES=$(grep -c ^processor /proc/cpuinfo || nproc || echo 1)
    log_info "Detected CPU Cores : ${CPU_CORES}"
    if [[ $CPU_CORES -lt 2 ]]; then
        log_warn "Wazuh Server requires at least 2 CPU cores (4 cores recommended for production)."
        if [[ "$FORCE_INSTALL" != true && "$CHECK_ONLY" != true ]]; then
            read -rp "Do you wish to proceed anyway? (y/N): " proceed_cpu
            if [[ ! "$proceed_cpu" =~ ^[Yy]$ ]]; then
                log_error "Installation aborted by user due to insufficient CPU resources."
                exit 1
            fi
        fi
    else
        log_success "CPU Cores check passed (>= 2 cores)."
    fi

    # 2. RAM Check (in MB)
    TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
    log_info "Detected RAM Memory: ${TOTAL_RAM_MB} MB (~$((TOTAL_RAM_MB / 1024)) GB)"
    
    # Wazuh Indexer (OpenSearch JVM) requires at least 4 GB RAM. Recommended 8 GB+
    if [[ $TOTAL_RAM_MB -lt 3800 ]]; then
        log_warn "Total RAM is below 4 GB (${TOTAL_RAM_MB} MB). Wazuh Indexer may fail or encounter OOM crashes!"
        log_warn "Recommended minimal RAM is 4 GB (8 GB+ for production)."
        if [[ "$FORCE_INSTALL" != true && "$CHECK_ONLY" != true ]]; then
            read -rp "Do you wish to bypass this warning and force installation? (y/N): " proceed_ram
            if [[ ! "$proceed_ram" =~ ^[Yy]$ ]]; then
                log_error "Installation aborted due to insufficient RAM. Allocate at least 4 GB RAM or run with --force."
                exit 1
            fi
        fi
    else
        log_success "RAM Memory check passed (>= 4 GB)."
    fi

    # 3. Free Disk Space Check (in GB)
    FREE_DISK_GB=$(df -BG /var 2>/dev/null | awk 'NR==2 {gsub("G","",$4); print $4}' || df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    log_info "Free Disk Space on /var: ~${FREE_DISK_GB} GB"
    if [[ -n "$FREE_DISK_GB" && "$FREE_DISK_GB" -lt 10 ]]; then
        log_warn "Free disk space is less than 10 GB (~${FREE_DISK_GB} GB). OpenSearch and Wazuh logs require sufficient disk capacity."
        if [[ "$FORCE_INSTALL" != true && "$CHECK_ONLY" != true ]]; then
            read -rp "Do you wish to proceed anyway? (y/N): " proceed_disk
            if [[ ! "$proceed_disk" =~ ^[Yy]$ ]]; then
                log_error "Installation aborted due to low disk space."
                exit 1
            fi
        fi
    else
        log_success "Disk space check passed (>= 10 GB free)."
    fi
}

# ------------------------------------------------------------------------------
# Kernel & System Tuning (Sysctl & Limits)
# ------------------------------------------------------------------------------
apply_system_tuning() {
    log_header "Applying Kernel & System Parameter Tuning"

    # Wazuh Indexer (OpenSearch) strictly mandates vm.max_map_count >= 262144
    log_info "Configuring sysctl: vm.max_map_count=262144 and vm.swappiness=1..."
    cat << 'EOF' > /etc/sysctl.d/99-wazuh-indexer.conf
# Wazuh Server & Indexer (OpenSearch) Optimization
vm.max_map_count=262144
vm.swappiness=1
net.core.somaxconn=1024
fs.file-max=655360
EOF

    # Apply immediately
    sysctl -w vm.max_map_count=262144 >/dev/null 2>&1 || true
    sysctl -w vm.swappiness=1 >/dev/null 2>&1 || true
    sysctl --system >/dev/null 2>&1 || sysctl -p /etc/sysctl.d/99-wazuh-indexer.conf >/dev/null 2>&1 || true

    CURRENT_MAX_MAP=$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)
    log_success "vm.max_map_count is now set to: ${CURRENT_MAX_MAP}"

    # Resource Limits for Wazuh & OpenSearch
    log_info "Configuring security limits: /etc/security/limits.d/99-wazuh.conf..."
    cat << 'EOF' > /etc/security/limits.d/99-wazuh.conf
# Wazuh Indexer & Manager file limits
wazuh-indexer soft nofile 65536
wazuh-indexer hard nofile 65536
wazuh-indexer soft nproc 4096
wazuh-indexer hard nproc 4096
wazuh-indexer soft memlock unlimited
wazuh-indexer hard memlock unlimited
wazuh soft nofile 65536
wazuh hard nofile 65536
EOF
    log_success "Security limits configured successfully."
}

# ------------------------------------------------------------------------------
# Install Prerequisites & Dependencies
# ------------------------------------------------------------------------------
install_dependencies() {
    log_header "Installing Required System Dependencies"

    case "$PKG_MGR" in
        apt)
            log_info "Updating APT package index..."
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            log_info "Installing core packages via APT..."
            apt-get install -y curl tar unzip gzip coreutils procps sed grep jq gnupg libcap2-bin iptables net-tools
            ;;
        dnf)
            log_info "Installing core packages via DNF..."
            if [[ "$OS_ID" == "amzn" && "$OS_VERSION" == "2023" ]]; then
                # Amazon Linux 2023 minimal package handling
                dnf install -y curl-minimal tar unzip gzip coreutils procps-ng sed grep jq libcap iptables || \
                dnf install -y curl tar unzip gzip coreutils procps-ng sed grep jq libcap iptables
            else
                dnf install -y curl tar unzip gzip coreutils procps-ng sed grep jq libcap iptables
            fi
            ;;
        yum)
            log_info "Installing core packages via YUM..."
            yum install -y curl tar unzip gzip coreutils procps-ng sed grep jq libcap iptables
            ;;
    esac

    log_success "All prerequisites installed successfully."
}

# ------------------------------------------------------------------------------
# Firewall Configuration
# ------------------------------------------------------------------------------
configure_firewall() {
    log_header "Configuring Firewall Ports for Wazuh Server"

    # Ports required:
    # 1514/tcp  : Agent communication & log events
    # 1515/tcp  : Agent enrollment / authd service
    # 443/tcp   : Wazuh Dashboard HTTPS Web UI
    # 55000/tcp : Wazuh RESTful API

    FIREWALL_CONFIGURED=false

    # Check for firewalld
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
        log_info "firewalld is active. Adding Wazuh ports (1514, 1515, 443, 55000/tcp)..."
        firewall-cmd --permanent --add-port=1514/tcp
        firewall-cmd --permanent --add-port=1515/tcp
        firewall-cmd --permanent --add-port=443/tcp
        firewall-cmd --permanent --add-port=55000/tcp
        firewall-cmd --reload
        log_success "firewalld rules successfully updated."
        FIREWALL_CONFIGURED=true
    # Check for ufw
    elif command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        log_info "ufw is active. Allowing Wazuh ports (1514, 1515, 443, 55000/tcp)..."
        ufw allow 1514/tcp comment 'Wazuh Agent Events'
        ufw allow 1515/tcp comment 'Wazuh Authd Enrollment'
        ufw allow 443/tcp  comment 'Wazuh Dashboard HTTPS'
        ufw allow 55000/tcp comment 'Wazuh API'
        ufw reload
        log_success "ufw rules successfully updated."
        FIREWALL_CONFIGURED=true
    fi

    if [[ "$FIREWALL_CONFIGURED" != true ]]; then
        log_info "No local firewall daemon (firewalld/ufw) is actively blocking ports."
        log_warn "If this server is hosted in a Cloud environment (AWS EC2, OCI, GCP, Azure),"
        log_warn "ensure your Security Group / Network Security Group (NSG) Inbound Rules allow:"
        echo -e "   - ${BOLD}Port 1514/TCP${NC}  : From all Agent IPs (Event communication)"
        echo -e "   - ${BOLD}Port 1515/TCP${NC}  : From all Agent IPs (Authd Agent registration)"
        echo -e "   - ${BOLD}Port 443/TCP${NC}   : From Administrator / SOC IPs (Dashboard Web UI)"
        echo -e "   - ${BOLD}Port 55000/TCP${NC} : From API clients / Dashboard (RESTful API)"
    fi
}

# ------------------------------------------------------------------------------
# Wazuh Server v4.14 Installation
# ------------------------------------------------------------------------------
install_wazuh_server() {
    log_header "Starting Wazuh Server v${WAZUH_VERSION} All-in-One Installation"

    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    INSTALLER_URL="https://packages.wazuh.com/${WAZUH_VERSION}/wazuh-install.sh"
    log_info "Downloading official Wazuh Installation Assistant from:"
    log_info "${INSTALLER_URL}"

    rm -f wazuh-install.sh
    if ! curl -sSL -O "${INSTALLER_URL}"; then
        log_error "Failed to download wazuh-install.sh from ${INSTALLER_URL}"
        exit 1
    fi

    # Verify script content integrity (make sure it's not an XML AccessDenied document)
    if ! head -n 1 wazuh-install.sh | grep -q "^#\!/bin/bash"; then
        log_error "Downloaded file is not a valid bash script. Content preview:"
        head -n 5 wazuh-install.sh
        exit 1
    fi

    chmod +x wazuh-install.sh
    log_success "Wazuh installation script verified successfully."

    log_info "Executing Wazuh All-in-One (-a) Installation Assistant..."
    log_info "This process installs Wazuh Indexer, Manager, Filebeat, and Dashboard."
    log_info "Installation may take 5 - 15 minutes depending on network and hardware speed...\n"

    # Execute Wazuh installer
    bash ./wazuh-install.sh -a

    log_success "Wazuh Installation Assistant completed execution."
}

# ------------------------------------------------------------------------------
# Post-Installation Verification & Password Extraction
# ------------------------------------------------------------------------------
verify_installation() {
    log_header "Post-Installation Health Verification"

    SERVICES=("wazuh-indexer" "wazuh-manager" "filebeat" "wazuh-dashboard")
    ALL_RUNNING=true

    for srv in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$srv"; then
            echo -e "  [+] Service ${BOLD}${srv}${NC} : ${GREEN}RUNNING (Active)${NC}"
        else
            echo -e "  [-] Service ${BOLD}${srv}${NC} : ${RED}STOPPED / FAILED${NC}"
            ALL_RUNNING=false
        fi
    done

    echo ""
    if [[ "$ALL_RUNNING" == true ]]; then
        log_success "All Wazuh Server services are active and running normally!"
    else
        log_warn "Some services are not active yet. They might still be initializing or need review."
        log_warn "Run: journalctl -u <service_name> -n 50 --no-pager"
    fi

    # Locate and extract credentials
    PASSWORDS_FILE=""
    if [[ -f "${INSTALL_DIR}/wazuh-passwords.txt" ]]; then
        PASSWORDS_FILE="${INSTALL_DIR}/wazuh-passwords.txt"
    elif [[ -f "${INSTALL_DIR}/wazuh-install-files.tar" ]]; then
        tar -xf "${INSTALL_DIR}/wazuh-install-files.tar" -C "$INSTALL_DIR" wazuh-passwords.txt 2>/dev/null || true
        if [[ -f "${INSTALL_DIR}/wazuh-passwords.txt" ]]; then
            PASSWORDS_FILE="${INSTALL_DIR}/wazuh-passwords.txt"
        fi
    fi

    # Also backup passwords file to /root/wazuh-passwords.txt for persistence
    if [[ -n "$PASSWORDS_FILE" && -f "$PASSWORDS_FILE" ]]; then
        cp -f "$PASSWORDS_FILE" /root/wazuh-passwords.txt
        chmod 600 /root/wazuh-passwords.txt
        log_success "Credentials file securely saved to: ${BOLD}/root/wazuh-passwords.txt${NC}"
    fi

    # Determine Server IP
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' || echo "YOUR_SERVER_IP")

    ADMIN_PASS="[Check /root/wazuh-passwords.txt]"
    if [[ -f /root/wazuh-passwords.txt ]]; then
        EXTRACTED_PASS=$(grep -E "^User:\s*admin\b" -A 1 /root/wazuh-passwords.txt | grep -E "Password:" | awk '{print $2}' || true)
        if [[ -n "$EXTRACTED_PASS" ]]; then
            ADMIN_PASS="$EXTRACTED_PASS"
        fi
    fi

    # Display Final Access Banner
    cat << EOF

${GREEN}${BOLD}========================================================================${NC}
${GREEN}${BOLD}         WAZUH SERVER v${WAZUH_VERSION} INSTALLED SUCCESSFULLY!          ${NC}
${GREEN}${BOLD}========================================================================${NC}

${BOLD}1. WAZUH WEB DASHBOARD ACCESS:${NC}
   - URL      : ${CYAN}https://${SERVER_IP}${NC}
   - Username : ${BOLD}admin${NC}
   - Password : ${YELLOW}${ADMIN_PASS}${NC}

${BOLD}2. CREDENTIALS & CERTIFICATES BACKUP:${NC}
   - Master Password File : ${BOLD}/root/wazuh-passwords.txt${NC}
   - Installation Tarball : ${BOLD}${INSTALL_DIR}/wazuh-install-files.tar${NC}

${BOLD}3. FIREWALL PORTS MATRIX (VERIFY CLOUD SECURITY GROUP):${NC}
   - Port 443   (TCP) : Web UI Dashboard (Admin / SOC browser)
   - Port 1514  (TCP) : Wazuh Agent Event & Log Communication
   - Port 1515  (TCP) : Wazuh Agent Enrollment (authd service)
   - Port 55000 (TCP) : Wazuh RESTful API

${BOLD}4. AGENT ENROLLMENT QUICK COMMAND:${NC}
   To install an agent on client servers, run the agent script:
   ${CYAN}sudo bash install_wazuh_agent.sh -m ${SERVER_IP}${NC}

   (Optional) If you want to protect agent enrollment with a registration password:
   ${BOLD}echo "YourSecretPassword123" | sudo tee /var/ossec/etc/authd.pass${NC}
   ${BOLD}sudo chmod 640 /var/ossec/etc/authd.pass && sudo chown root:wazuh /var/ossec/etc/authd.pass${NC}
   ${BOLD}sudo systemctl restart wazuh-manager${NC}
   Then on the agent:
   ${CYAN}sudo bash install_wazuh_agent.sh -m ${SERVER_IP} -p "YourSecretPassword123"${NC}

${GREEN}${BOLD}========================================================================${NC}
EOF
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    check_root
    detect_os
    check_system_resources

    if [[ "$CHECK_ONLY" == true ]]; then
        log_success "Pre-flight checks completed. System is ready for Wazuh Server v${WAZUH_VERSION}."
        exit 0
    fi

    apply_system_tuning
    install_dependencies

    if [[ "$AUTO_FIREWALL" == true ]]; then
        configure_firewall
    fi

    install_wazuh_server
    verify_installation
}

main "$@"
