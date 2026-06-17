echo "== Test des installations =="
ansible --version
terraform --version
podman --version

echo "== Test socket podman =="
echo $XDG_RUNTIME_DIR  # Doit retourner /run/user/1000 ou similaire
ls $XDG_RUNTIME_DIR/podman/podman.sock

echo "== Test Podman + image Juice Shop =="
podman run -d --name test-juiceshop -p 3000:3000 bkimminich/juice-shop:latest

sleep 10

curl localhost:3000 | grep "OWASP Juice Shop"

podman rm -f test-juiceshop  # Nettoyage après test