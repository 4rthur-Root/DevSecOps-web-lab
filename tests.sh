#!/bin/bash

# Interrompt le script en cas d'erreur
set -e

echo "============================================="
echo "==  Détection et Configuration du Système  =="
echo "============================================="

# Détection du gestionnaire de paquets
if command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
elif command -v microdnf &> /dev/null; then
    PKG_MANAGER="microdnf"
elif command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
elif command -v pacman &> /dev/null; then
    PKG_MANAGER="pacman"
else
    echo "❌ Erreur : Gestionnaire de paquets non supporté."
    exit 1
fi

echo "-> Gestionnaire détecté : $PKG_MANAGER"

echo "============================================="
echo "==   Ajout des Dépôts Optionnels (Terraform) =="
echo "============================================="

case $PKG_MANAGER in
    "dnf"|"microdnf")
        # Ajout dépôt HashiCorp (Terraform)
        if [ ! -f /etc/yum.repos.d/hashicorp.repo ]; then
            echo "Ajout du dépôt HashiCorp..."
            sudo $PKG_MANAGER install -y dnf-plugins-core
            sudo dnf config-manager --add-repo https://hashicorp.com
        fi
        # Installation des paquets système
        sudo $PKG_MANAGER install -y ansible terraform podman nmap python3 python3-pip python3-pipx
        ;;
        
    "apt")
        # Mise à jour des index
        sudo apt-get update
        sudo apt-get install -y gpg coreutils curl python3 python3-pip pipx podman nmap dbus-user-session
        
        # Ajout dépôt HashiCorp de manière propre
        if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
            echo "Ajout du dépôt HashiCorp..."
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

echo "============================================="
echo "==          Installation de SQLMap          =="
echo "============================================="
# Utilisation de pipx pour respecter les normes Python modernes (PEP 668)
if ! command -v sqlmap &> /dev/null; then
    echo "Installation de SQLMap via pipx..."
    pipx install sqlmap
    export PATH="$HOME/.local/bin:$PATH"
else
    echo "SQLMap est déjà installé."
fi

echo "============================================="
echo "==       Configuration Socket Podman       =="
echo "============================================="
# S'assurer que les variables XDG_RUNTIME_DIR sont prêtes (obligatoire pour le mode rootless hors Fedora)
if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

echo "Activation et démarrage du service de socket Podman en mode utilisateur..."
systemctl --user daemon-reload
systemctl --user enable --now podman.socket

echo "============================================="
echo "==          Test des Installations         =="
echo "============================================="
ansible --version | head -n 1
terraform --version | head -n 1
podman --version
nmap --version | head -n 1
sqlmap --version | head -n 2

echo "============================================="
echo "==           Test Socket Podman            =="
echo "============================================="
echo "Dossier runtime : $XDG_RUNTIME_DIR"
if [ -S "$XDG_RUNTIME_DIR/podman/podman.sock" ]; then
    echo "✅ Le socket Podman est actif et accessible : $XDG_RUNTIME_DIR/podman/podman.sock"
else
    echo "⚠️ Le socket n'est pas encore visible, vérification de l'état du service :"
    systemctl --user status podman.socket --no-pager
fi

echo "============================================="
echo "==     Test Podman + image Juice Shop      =="
echo "============================================="
# Lancement du conteneur en arrière-plan
podman run -d --name test-juiceshop -p 3000:3000 bkimminich/juice-shop:latest

echo "Attente du démarrage de l'application (15 secondes)..."
sleep 15

# Requête de vérification
if curl -s http://localhost:3000 | grep -q "OWASP Juice Shop"; then
    echo "✅ Succès ! L'application Juice Shop répond correctement."
else
    echo "❌ Échec ! Impossible d'atteindre l'application Juice Shop."
fi

echo "Nettoyage du conteneur de test..."
podman rm -f test-juiceshop
echo "============================================="
echo "==         Script exécuté avec succès       =="
echo "============================================="
