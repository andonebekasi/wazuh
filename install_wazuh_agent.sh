#!/usr/bin/env bash
# ==============================================================================
# Script Name   : install_wazuh_agent.sh
# Description   : Universal Automated Installer & Enrollment Script for Wazuh Agent v4.14
# Target Version: Wazuh Agent v4.14.x
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

prompt_read() {
    local prompt_msg="$1"
    local var_name="$2"
    if [ -t 0 ]; then
        read -rp "$prompt_msg" "$var_name"
    elif [ -r /dev/tty ]; then
        read -rp "$prompt_msg" "$var_name" < /dev/tty
    else
        read -rp "$prompt_msg" "$var_name" || true
    fi
}

# ------------------------------------------------------------------------------
# Default Settings
# ------------------------------------------------------------------------------
WAZUH_MANAGER=""
AGENT_NAME="$(hostname -s 2>/dev/null || hostname)"
AGENT_GROUP="default"
AUTH_PASSWORD=""
PROTOCOL="tcp"
WAZUH_VERSION="4.14"
FORCE_CONNECTIVITY=false
NON_INTERACTIVE=false

# ------------------------------------------------------------------------------
# Help & Usage
# ------------------------------------------------------------------------------
show_help() {
    cat << EOF
Usage: $(basename "$0") -m <MANAGER_IP_OR_FQDN> [OPTIONS]

Universal Automated Installer and Enrollment Script for Wazuh Agent v4.14.

REQUIRED OPTIONS:
  -m, --manager <IP|FQDN>     IP address or Domain / FQDN of the Wazuh Manager / Server.

OPTIONAL PARAMETERS:
  -n, --agent-name <NAME>     Custom name for this agent (Default: '$(hostname -s 2>/dev/null || hostname)').
  -g, --agent-group <GROUP>   Agent group(s) in Wazuh Manager (Default: 'default').
                              Multiple groups can be comma-separated, e.g. 'production,web'.
  -p, --auth-pass <PASSWORD>  Registration password for Authd enrollment (Optional,
                              required only if authd.pass is configured on the Manager).
  -P, --protocol <tcp|udp>    Communication protocol (Default: 'tcp').
  -v, --version <VERSION>     Wazuh agent major version (Default: '4.14').
  -f, --force                 Skip pre-flight TCP port connectivity check to Manager.
  -y, --yes                   Non-interactive mode (proceed without confirmation).
  -h, --help                  Display this help message and exit.

SUPPORTED OPERATING SYSTEMS:
  * Ubuntu 18.04, 20.04, 22.04, 24.04 (Latest)
  * Debian 10, 11, 12
  * RHEL 7, 8, 9, 10 / CentOS 7, 8, 9 Stream
  * Oracle Linux 7, 8, 9
  * AlmaLinux 8, 9, 10 / Rocky Linux 8, 9
  * Amazon Linux 2 & Amazon Linux 2023

EXAMPLES:
  # One-liner via curl:
  curl -sSL https://raw.githubusercontent.com/andonebekasi/wazuh/main/install_wazuh_agent.sh | sudo bash -s -- -m 192.168.1.100

  # Quick install pointing to Wazuh Manager IP:
  sudo bash $(basename "$0") -m 192.168.1.100

  # Install with custom agent name, group, and authd password:
  sudo bash $(basename "$0") -m 10.0.1.50 -n "web-prod-01" -g "production,web" -p "SecretPass123"

  # Silent deployment for Cloud-Init / AWS SSM / Ansible:
  sudo bash $(basename "$0") -m 172.31.20.10 -n "backend-srv" -g "production" -y
EOF
}

# ------------------------------------------------------------------------------
# CLI Argument Parsing
# ------------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--manager)
            WAZUH_MANAGER="$2"
            shift 2
            ;;
        -n|--agent-name)
            AGENT_NAME="$2"
            shift 2
            ;;
        -g|--agent-group)
            AGENT_GROUP="$2"
            shift 2
            ;;
        -p|--auth-pass)
            AUTH_PASSWORD="$2"
            shift 2
            ;;
        -P|--protocol)
            PROTOCOL="$2"
            shift 2
            ;;
        -v|--version)
            WAZUH_VERSION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE_CONNECTIVITY=true
            shift
            ;;
        -y|--yes)
            NON_INTERACTIVE=true
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
        echo "Example: sudo bash $0 -m <MANAGER_IP>"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# Manager Parameter Validation
# ------------------------------------------------------------------------------
validate_parameters() {
    if [[ -z "$WAZUH_MANAGER" ]]; then
        if [[ "$NON_INTERACTIVE" == true ]]; then
            log_error "Wazuh Manager IP or Domain is required. Specify with -m <IP|DOMAIN>."
            exit 1
        fi
        echo -e "${YELLOW}${BOLD}Wazuh Manager IP or FQDN is required.${NC}"
        prompt_read "Enter Wazuh Manager IP or Domain: " WAZUH_MANAGER
        if [[ -z "$WAZUH_MANAGER" ]]; then
            log_error "Manager IP cannot be empty. Aborting."
            exit 1
        fi
    fi

    log_info "Wazuh Manager IP/Host : ${BOLD}${WAZUH_MANAGER}${NC}"
    log_info "Agent Name            : ${BOLD}${AGENT_NAME}${NC}"
    log_info "Agent Group(s)        : ${BOLD}${AGENT_GROUP}${NC}"
    log_info "Protocol              : ${BOLD}${PROTOCOL}${NC}"
    log_info "Target Version        : ${BOLD}${WAZUH_VERSION}${NC}"
    if [[ -n "$AUTH_PASSWORD" ]]; then
        log_info "Authd Registration Password: [Configured]"
    else
        log_info "Authd Registration Password: [None / Default]"
    fi
}

# ------------------------------------------------------------------------------
# OS & Distribution Detection
# ------------------------------------------------------------------------------
detect_os() {
    log_header "Detecting Operating System & Hardware Platform"

    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
        log_error "Unsupported system architecture: $ARCH. Wazuh Agent requires x86_64 or aarch64."
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
            if command -v apt-get >/dev/null 2>&1; then
                PKG_MGR="apt"
            elif command -v dnf >/dev/null 2>&1; then
                PKG_MGR="dnf"
            elif command -v yum >/dev/null 2>&1; then
                PKG_MGR="yum"
            else
                log_error "Unsupported Linux distribution ($OS_ID)."
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
# Pre-flight Connectivity Check to Wazuh Manager
# ------------------------------------------------------------------------------
check_connectivity() {
    log_header "Testing Network Connectivity to Wazuh Manager (${WAZUH_MANAGER})"

    if [[ "$FORCE_CONNECTIVITY" == true ]]; then
        log_warn "Bypassing network connectivity check (--force active)."
        return 0
    fi

    # Function to test TCP connection via bash built-in /dev/tcp
    test_tcp_port() {
        local host="$1"
        local port="$2"
        timeout 4 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null
    }

    PORT_1515_OK=false
    PORT_1514_OK=false

    log_info "Testing Port 1515 TCP (Authd Enrollment Service)..."
    if test_tcp_port "$WAZUH_MANAGER" 1515; then
        log_success "Port 1515 TCP is OPEN and reachable."
        PORT_1515_OK=true
    else
        log_warn "Port 1515 TCP is UNREACHABLE or closed."
    fi

    log_info "Testing Port 1514 TCP (Agent Event Data Service)..."
    if test_tcp_port "$WAZUH_MANAGER" 1514; then
        log_success "Port 1514 TCP is OPEN and reachable."
        PORT_1514_OK=true
    else
        log_warn "Port 1514 TCP is UNREACHABLE or closed."
    fi

    if [[ "$PORT_1515_OK" != true || "$PORT_1514_OK" != true ]]; then
        echo ""
        log_warn "One or more required ports on Wazuh Manager (${WAZUH_MANAGER}) could not be reached!"
        log_warn "Common Causes:"
        echo -e "   1. Cloud Security Group (AWS/OCI/GCP/Azure) is missing Inbound rules for 1514/TCP & 1515/TCP."
        echo -e "   2. Local firewall (firewalld/ufw/iptables) on Wazuh Manager is blocking the connection."
        echo -e "   3. Wazuh Manager service is not yet running."
        echo -e "   4. IP address / FQDN '${WAZUH_MANAGER}' is incorrect or unreachable across subnets/VPC."
        echo ""

        if [[ "$NON_INTERACTIVE" != true ]]; then
            prompt_read "Do you want to continue the installation anyway? (y/N): " proceed_conn
            if [[ ! "$proceed_conn" =~ ^[Yy]$ ]]; then
                log_error "Installation aborted by user."
                exit 1
            fi
        else
            log_warn "Continuing installation in non-interactive mode. Please verify firewall rules later."
        fi
    else
        log_success "Network connectivity verification passed!"
    fi
}

# ------------------------------------------------------------------------------
# Repository Configuration & Package Installation
# ------------------------------------------------------------------------------
install_agent() {
    log_header "Configuring Repository & Installing Wazuh Agent v${WAZUH_VERSION}"

    # Setup environment variables for Wazuh automated enrollment during package install
    export WAZUH_MANAGER="$WAZUH_MANAGER"
    export WAZUH_AGENT_NAME="$AGENT_NAME"
    export WAZUH_AGENT_GROUP="$AGENT_GROUP"
    export WAZUH_PROTOCOL="$PROTOCOL"
    if [[ -n "$AUTH_PASSWORD" ]]; then
        export WAZUH_REGISTRATION_PASSWORD="$AUTH_PASSWORD"
    fi

    case "$PKG_MGR" in
        apt)
            log_info "Preparing APT repositories and GPG keys..."
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y curl gnupg apt-transport-https

            # Modern keyring setup with fallback for Ubuntu 18.04
            mkdir -p /usr/share/keyrings
            if curl -sSL https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import 2>/dev/null; then
                chmod 644 /usr/share/keyrings/wazuh.gpg
                echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
            else
                log_warn "Keyring creation fallback using legacy apt-key (compatible with older Ubuntu/Debian)..."
                curl -sSL https://packages.wazuh.com/key/GPG-KEY-WAZUH | apt-key add -
                echo "deb https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list
            fi

            apt-get update -y

            # Look for exact 4.14 package version in repository cache
            log_info "Resolving Wazuh Agent v${WAZUH_VERSION} package version..."
            EXACT_PKG_VER=$(apt-cache madison wazuh-agent 2>/dev/null | awk '{print $3}' | grep -E "^${WAZUH_VERSION}\." | head -n 1 || true)

            if [[ -n "$EXACT_PKG_VER" ]]; then
                log_info "Installing specific package: wazuh-agent=${EXACT_PKG_VER}..."
                apt-get install -y "wazuh-agent=${EXACT_PKG_VER}"
            else
                log_info "Installing wazuh-agent from stable channel..."
                apt-get install -y wazuh-agent
            fi
            ;;

        dnf)
            log_info "Configuring RPM repository for DNF..."
            rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

            cat << 'EOF' > /etc/yum.repos.d/wazuh.repo
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

            log_info "Installing Wazuh Agent via DNF..."
            if dnf install -y "wazuh-agent-${WAZUH_VERSION}*" 2>/dev/null; then
                log_success "Installed wazuh-agent-${WAZUH_VERSION}* successfully."
            else
                log_info "Falling back to default wazuh-agent package..."
                dnf install -y wazuh-agent
            fi
            ;;

        yum)
            log_info "Configuring RPM repository for YUM..."
            rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH

            cat << 'EOF' > /etc/yum.repos.d/wazuh.repo
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-$releasever - Wazuh
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

            log_info "Installing Wazuh Agent via YUM..."
            if yum install -y "wazuh-agent-${WAZUH_VERSION}*" 2>/dev/null; then
                log_success "Installed wazuh-agent-${WAZUH_VERSION}* successfully."
            else
                log_info "Falling back to default wazuh-agent package..."
                yum install -y wazuh-agent
            fi
            ;;
    esac

    log_success "Wazuh Agent package installation finished."
}

# ------------------------------------------------------------------------------
# Configuration Sanity & ossec.conf Verification
# ------------------------------------------------------------------------------
configure_ossec() {
    log_header "Verifying & Finalizing Agent Configuration"

    CONF_FILE="/var/ossec/etc/ossec.conf"

    if [[ ! -f "$CONF_FILE" ]]; then
        log_error "Config file ${CONF_FILE} not found! Installation may have failed."
        exit 1
    fi

    # Ensure Manager address is properly populated
    if grep -q "<address>0.0.0.0</address>" "$CONF_FILE"; then
        log_info "Replacing default placeholder 0.0.0.0 with ${WAZUH_MANAGER} in ${CONF_FILE}..."
        sed -i "s|<address>0.0.0.0</address>|<address>${WAZUH_MANAGER}</address>|g" "$CONF_FILE"
    fi

    # Ensure Protocol is properly configured
    if grep -q "<protocol>" "$CONF_FILE"; then
        sed -i "s|<protocol>.*</protocol>|<protocol>${PROTOCOL}</protocol>|g" "$CONF_FILE"
    fi

    # If registration password is provided, configure auth section if missing
    if [[ -n "$AUTH_PASSWORD" ]]; then
        if ! grep -q "<auth>" "$CONF_FILE"; then
            log_info "Adding enrollment password block to ${CONF_FILE}..."
            sed -i "/<\/client>/i \  <auth>\n    <password>${AUTH_PASSWORD}</password>\n  </auth>" "$CONF_FILE"
        fi
    fi

    log_success "Configuration in ${CONF_FILE} verified."
}

# ------------------------------------------------------------------------------
# Service Management & Verification
# ------------------------------------------------------------------------------
start_and_verify_service() {
    log_header "Enabling & Starting Wazuh Agent Service"

    systemctl daemon-reload
    systemctl enable wazuh-agent
    systemctl restart wazuh-agent

    log_info "Waiting 6 seconds for agent registration handshake..."
    sleep 6

    if systemctl is-active --quiet wazuh-agent; then
        log_success "wazuh-agent service is ACTIVE (Running)!"
    else
        log_error "wazuh-agent service failed to start."
        systemctl status wazuh-agent --no-pager
        exit 1
    fi

    # Inspect registration key & ID
    AGENT_ID="[Pending Enrollment]"
    if [[ -s /var/ossec/etc/client.keys ]]; then
        AGENT_ID=$(awk '{print $1}' /var/ossec/etc/client.keys | head -n 1)
        AGENT_KEY_NAME=$(awk '{print $2}' /var/ossec/etc/client.keys | head -n 1)
        log_success "Agent successfully registered with ID: ${BOLD}${AGENT_ID}${NC} (Name: ${AGENT_KEY_NAME})"
    else
        log_warn "client.keys is currently empty. Agent is waiting for registration response from Manager."
    fi

    # Check recent log entries
    log_info "Recent log entries from /var/ossec/logs/ossec.log:"
    echo -e "${CYAN}------------------------------------------------------------------------${NC}"
    tail -n 8 /var/ossec/logs/ossec.log 2>/dev/null || true
    echo -e "${CYAN}------------------------------------------------------------------------${NC}"

    # Final summary banner
    cat << EOF

${GREEN}${BOLD}========================================================================${NC}
${GREEN}${BOLD}          WAZUH AGENT v${WAZUH_VERSION} DEPLOYMENT COMPLETED!            ${NC}
${GREEN}${BOLD}========================================================================${NC}

${BOLD}AGENT DETAILS:${NC}
  - Agent Name   : ${CYAN}${AGENT_NAME}${NC}
  - Agent ID     : ${BOLD}${AGENT_ID}${NC}
  - Agent Group  : ${BOLD}${AGENT_GROUP}${NC}
  - Target Server: ${BOLD}${WAZUH_MANAGER}${NC} (Ports: 1514/1515 TCP)
  - Service      : ${GREEN}Active & Enabled (systemd)${NC}

${BOLD}USEFUL TROUBLESHOOTING COMMANDS:${NC}
  - View real-time logs : ${BOLD}sudo tail -f /var/ossec/logs/ossec.log${NC}
  - Check service status: ${BOLD}sudo systemctl status wazuh-agent${NC}
  - Inspect client key  : ${BOLD}sudo cat /var/ossec/etc/client.keys${NC}
  - Restart agent       : ${BOLD}sudo systemctl restart wazuh-agent${NC}

${GREEN}${BOLD}========================================================================${NC}
EOF
}

# ------------------------------------------------------------------------------
# Main Flow
# ------------------------------------------------------------------------------
main() {
    check_root
    validate_parameters
    detect_os
    check_connectivity
    install_agent
    configure_ossec
    start_and_verify_service
}

main "$@"
