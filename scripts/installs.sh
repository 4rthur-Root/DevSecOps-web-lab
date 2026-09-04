#!/bin/bash
# This script installs the necessary tools for the DevSecOps Lab environment.
# Tools: Ansible, Terraform, Podman.

# To stop the script on any error.
set -e

# Function to print a line separator
line() {
    echo "--------------------------------"
    printf '\n'
}

echo "=================================================="
echo " Detection and Configuration of the system..."
echo "=================================================="

# Detection of the package manager
if command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
elif command -v microdnf &> /dev/null; then
    PKG_MANAGER="microdnf"
elif command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
elif command -v pacman &> /dev/null; then
    PKG_MANAGER="pacman"
else
    echo "❌ Error: Unsupported package manager. Please install dependencies manually."
    exit 1
fi

echo "-> Detected package manager: $PKG_MANAGER"

echo "---   Adding Optional Terraform Repositories ---"

case $PKG_MANAGER in
    "dnf"|"microdnf")
        # Adding HashiCorp repository (Terraform)
        # Note: We download the .repo file directly into /etc/yum.repos.d/ to ensure 
        # compatibility across both DNF4 (which uses --add-repo) and DNF5 (which uses addrepo --from-repofile).
        if [ ! -f /etc/yum.repos.d/hashicorp.repo ]; then
            echo "Adding HashiCorp repository..."
            sudo curl -fsSL https://rpm.releases.hashicorp.com/fedora/hashicorp.repo -o /etc/yum.repos.d/hashicorp.repo
        fi
        # Package names on Fedora/RHEL: 'pipx' (not 'python3-pipx').
        echo "Installing packages with $PKG_MANAGER..."
        sudo $PKG_MANAGER install -y ansible terraform podman python3 python3-pip pipx
        ;;
        
    "apt")
        # Update indexes and install base prerequisites
        sudo apt-get update
        sudo apt-get install -y gpg coreutils curl wget python3 python3-pip pipx podman dbus-user-session
        
        # Adding HashiCorp official repository with armored GPG key
        if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
            echo "Adding HashiCorp repository..."
            wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
            sudo apt-get update
        fi
        sudo apt-get install -y ansible terraform
        ;;
        
    "pacman")
        # Arch Linux / Manjaro packages
        sudo pacman -Sy --noconfirm ansible terraform podman python-pip python-pipx
        ;;
esac

line
echo "---       Socket Podman Configuration     ---"

# Ensuring that the XDG_RUNTIME_DIR variable is set (required for rootless mode outside Fedora default)
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

echo "Activating and starting Podman socket service in user mode..."
systemctl --user daemon-reload
systemctl --user enable --now podman.socket

line
echo "---          Testing installations         ---"

ansible --version | head -n 1
terraform --version | head -n 1
podman --version 

line
echo "---           Test Socket Podman            ---"

echo "Runtime folder : $XDG_RUNTIME_DIR"
if [ -S "$XDG_RUNTIME_DIR/podman/podman.sock" ]; then
    echo "✅ The Podman socket is active and accessible: $XDG_RUNTIME_DIR/podman/podman.sock"
else
    echo "⚠️ The socket is not yet visible, checking service status:"
    systemctl --user status podman.socket --no-pager
fi

line
echo "---     Test Podman + image Juice Shop      ---"

# Clean up any leftover test container first
podman rm -f test-juiceshop &> /dev/null || true

# Launch a test container with the Juice Shop application
echo "Starting test container 'test-juiceshop' on port 3000..."
podman run -d --name test-juiceshop -p 3000:3000 bkimminich/juice-shop:latest

echo "Waiting for the application to start (15 seconds)..."
sleep 15

# Verification request
if curl -s http://localhost:3000 | grep -q "OWASP Juice Shop"; then
    echo "✅ Success! The Juice Shop application is responding correctly."
else
    echo "⚠️ Note: Application took longer than expected to respond or port 3000 is busy."
fi

echo "Cleaning up the test container..."
podman rm -f test-juiceshop &> /dev/null || true

echo "=================================================================="
echo "        Script executed with success, the machine is ready!       "
echo "=================================================================="
