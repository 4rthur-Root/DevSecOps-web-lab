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

echo "============================================="
echo "===  Detection and Configuration of the system...  ==="
echo "============================================="

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
    echo "❌ Error: Unsupported package manager."
    exit 1
fi

echo "-> Detected package manager: $PKG_MANAGER"

echo "===   Adding Optional Terraform Repositories ==="

case $PKG_MANAGER in
    "dnf"|"microdnf")
        # Adding HashiCorp repository (Terraform)
        if [ ! -f /etc/yum.repos.d/hashicorp.repo ]; then
            echo "Adding HashiCorp repository..."
            sudo $PKG_MANAGER install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://hashicorp.com
        fi
        # Installation of system packages
        sudo $PKG_MANAGER install -y ansible terraform podman nmap python3 python3-pip python3-pipx
        ;;
        
    "apt")
        # Index updates and install required packages
        sudo apt-get update
        sudo apt-get install -y gpg coreutils curl python3 python3-pip pipx podman nmap dbus-user-session
        
        # Adding HashiCorp repository in a proper way
        if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
            echo "Adding HashiCorp repository..."
            curl -fsSL https://hashicorp.com | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
            sudo apt-get update
        fi
        sudo apt-get install -y ansible terraform
        ;;
        
    "pacman")
        sudo pacman -Sy --noconfirm ansible terraform podman nmap python-pip pipx
        ;;
esac



line
echo "===        Socket Podman  Configuration     ==="

# Ensuring that the XDG_RUNTIME_DIR variables are set (required for rootless mode outside Fedora)
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

echo "Activation and starting of the Podman socket service in user mode..."
systemctl --user daemon-reload
systemctl --user enable --now podman.socket

line
echo "===          Testing installations         ==="

ansible --version | head -n 1
terraform --version | head -n 1
podman --version

line
echo "===           Test Socket Podman            ==="

echo "Runtime folder : $XDG_RUNTIME_DIR"
if [ -S "$XDG_RUNTIME_DIR/podman/podman.sock" ]; then
    echo "✅ The Podman socket is active and accessible : $XDG_RUNTIME_DIR/podman/podman.sock"
else
    echo "⚠️ The socket is not yet visible, checking the service status :"
    systemctl --user status podman.socket --no-pager
fi

line
echo "===     Test Podman + image Juice Shop      ==="

# Launch a test container with the Juice Shop application
podman run -d --name test-juiceshop -p 3000:3000 bkimminich/juice-shop:latest

echo "Waiting for the application to start (15 seconds)..."
sleep 15

# Verification request
if curl -s http://localhost:3000 | grep -q "OWASP Juice Shop"; then
    echo "✅ Success! The Juice Shop application is responding correctly."
else
    echo "❌ Failure! Unable to reach the Juice Shop application."
fi

echo "Cleaning up the test container..."
podman rm -f test-juiceshop
echo "============================================="
echo "===         Script executed with success, the machine is ready!         ==="
echo "============================================="
