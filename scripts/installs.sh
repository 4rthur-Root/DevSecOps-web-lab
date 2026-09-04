#!usr/bin/env bash
# This script installs the necessary tools for the DevSecOps Lab environment.
# Tools: Ansible, Terraform, Podman.


set -euo pipefail

# --- Color Setup (auto-detect TTY, respect NO_COLOR) ---
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

# --- Logging Helpers ---
log_info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- Error Trap: report line number and exit ---
trap 'log_error "Script failed at line ${LINENO}. Check the output above for details."; exit 1' ERR

# --- Separator ---
separator() {
    echo -e "${RED}--------------------------------${NC}"
    printf '\n'
}

# --- Pre-flight Checks ---
if [[ $EUID -ne 0 ]] && ! command -v sudo &>/dev/null; then
    log_error "This script requires root privileges or 'sudo' to be available."
    exit 1
fi

SUDO=""
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
fi

# --- Detect Package Manager ---
detect_pkg_manager() {
    if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v microdnf &>/dev/null; then
        PKG_MANAGER="microdnf"
    elif command -v apt-get &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
    else
        log_error "Unsupported package manager. Please install dependencies manually."
        exit 1
    fi
    log_info "Detected package manager: ${PKG_MANAGER}"
}

# --- Get OS codename (portable, no lsb_release dependency) ---
get_codename() {
    if command -v lsb_release &>/dev/null; then
        lsb_release -cs
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${VERSION_CODENAME:-}"
    else
        log_error "Cannot determine OS codename."
        exit 1
    fi
}

# --- Install Packages ---
install_packages() {
    echo -e "${CYAN}---   Adding Optional Terraform Repositories ---${NC}"

    case "${PKG_MANAGER}" in
        "dnf"|"microdnf")
            local repo_file="/etc/yum.repos.d/hashicorp.repo"
            if [[ ! -f "${repo_file}" ]]; then
                log_info "Adding HashiCorp repository..."
                ${SUDO} curl -fsSL https://rpm.releases.hashicorp.com/fedora/hashicorp.repo \
                    -o "${repo_file}"
            else
                log_info "HashiCorp repository already present."
            fi

            log_info "Installing packages with ${PKG_MANAGER}..."
            ${SUDO} ${PKG_MANAGER} install -y ansible terraform podman python3 python3-pip pipx
            ;;

        "apt")
            local codename
            codename="$(get_codename)"
            if [[ -z "${codename}" ]]; then
                log_error "Failed to determine Ubuntu/Debian codename."
                exit 1
            fi

            log_info "Updating package indexes..."
            ${SUDO} apt-get update -y

            log_info "Installing base prerequisites..."
            ${SUDO} apt-get install -y gpg coreutils curl wget python3 python3-pip pipx podman dbus-user-session

            # HashiCorp repo
            local gpg_file="/usr/share/keyrings/hashicorp-archive-keyring.gpg"
            local list_file="/etc/apt/sources.list.d/hashicorp.list"
            if [[ ! -f "${gpg_file}" ]]; then
                log_info "Adding HashiCorp repository (GPG key)..."
                ${SUDO} install -d /usr/share/keyrings
                curl -fsSL https://apt.releases.hashicorp.com/gpg \
                    | ${SUDO} gpg --dearmor -o "${gpg_file}"
            fi

            if [[ ! -f "${list_file}" ]]; then
                log_info "Adding HashiCorp apt source..."
                echo "deb [signed-by=${gpg_file}] https://apt.releases.hashicorp.com ${codename} main" \
                    | ${SUDO} tee "${list_file}" > /dev/null
                ${SUDO} apt-get update -y
            fi

            log_info "Installing Ansible and Terraform..."
            ${SUDO} apt-get install -y ansible terraform
            ;;

        "pacman")
            log_info "Installing packages with pacman..."
            ${SUDO} pacman -Sy --noconfirm ansible terraform podman python-pip python-pipx
            ;;
    esac

    log_success "All packages installed successfully."
}

# --- Configure Podman Socket ---
configure_podman_socket() {
    separator
    echo -e "${CYAN}---       Socket Podman Configuration     ---${NC}"

    if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
    fi

    # Check if systemd user session is available
    if ! command -v systemctl &>/dev/null; then
        log_warn "systemd not available. Skipping Podman socket configuration."
        return 0
    fi

    # Check if user session is running (e.g., not in a plain container)
    if ! systemctl --user status &>/dev/null 2>&1; then
        log_warn "No systemd user session detected. Skipping socket activation."
        log_warn "You may need to run: loginctl enable-linger $(whoami)"
        return 0
    fi

    log_info "Activating and starting Podman socket service in user mode..."
    systemctl --user daemon-reload
    systemctl --user enable --now podman.socket
    log_success "Podman socket service enabled and started."
}

# --- Verify Installations ---
verify_installations() {
    separator
    echo -e "${GREEN}---          Testing installations         ---${NC}"

    local all_ok=true

    if command -v ansible &>/dev/null; then
        log_success "$(ansible --version | head -n 1)"
    else
        log_error "Ansible is NOT installed or not in PATH."
        all_ok=false
    fi

    if command -v terraform &>/dev/null; then
        log_success "$(terraform --version | head -n 1)"
    else
        log_error "Terraform is NOT installed or not in PATH."
        all_ok=false
    fi

    if command -v podman &>/dev/null; then
        log_success "$(podman --version)"
    else
        log_error "Podman is NOT installed or not in PATH."
        all_ok=false
    fi

    if [[ "${all_ok}" != true ]]; then
        log_error "One or more tools failed verification."
        exit 1
    fi
}

# --- Test Podman Socket ---
test_podman_socket() {
    separator
    echo -e "${CYAN}---           Test Socket Podman            ---${NC}"

    log_info "Runtime folder: ${XDG_RUNTIME_DIR}"

    local sock="${XDG_RUNTIME_DIR}/podman/podman.sock"
    if [[ -S "${sock}" ]]; then
        log_success "Podman socket is active and accessible: ${sock}"
    else
        log_warn "Socket not found at: ${sock}"
        log_warn "Checking service status:"
        systemctl --user status podman.socket --no-pager 2>&1 || true
    fi
}

# --- Test Podman with hello-world ---
test_podman_run() {
    separator
    echo -e "${CYAN}---     Test Podman + hello world      ---${NC}"

    local image="docker.io/library/hello-world"

    log_info "Pulling image: ${image}"
    if ! podman pull "${image}"; then
        log_error "Failed to pull image ${image}."
        exit 1
    fi
    log_success "Image pulled successfully."

    log_info "Running container..."
    if ! podman run --rm "${image}"; then
        log_error "Container run failed. Cleaning up image."
        podman rmi "${image}" &>/dev/null || true
        exit 1
    fi
    log_success "Container ran successfully."

    # Cleanup
    podman rmi "${image}" &>/dev/null || true
}

# MAIN

echo "=================================================="
echo " Detection and Configuration of the system..."
echo "=================================================="

detect_pkg_manager
install_packages
configure_podman_socket
verify_installations
test_podman_socket
test_podman_run

separator
echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN}     Script executed successfully. Machine is ready!${NC}"
echo -e "${GREEN}====================================================${NC}"   