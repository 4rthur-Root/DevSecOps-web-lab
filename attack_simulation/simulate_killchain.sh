#!/bin/bash

# simulate_killchain.sh - Simulation d'attaque DevSecOps Lab
# Cible : WAF (http://localhost:8080) → Juice Shop
# Phases : Reconnaissance → SQLi → XSS → Path Traversal


TARGET="http://localhost:8080"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  DEVSECOPS LAB - KILL CHAIN SIMULATION     ${NC}"
echo -e "${BLUE}==========================================${NC}"
sleep 1

# PHASE 1 : Reconnaissance
echo -e "\n${YELLOW}[PHASE 1] Reconnaissance${NC}"

echo "[*] Scan de chemins sensibles..."
for path in /admin /server-status /phpinfo.php /.git/config /backup /api/users; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET$path")
    echo "  $path → HTTP $STATUS"
    sleep 0.3
done

# PHASE 2 : SQL Injection
echo -e "\n${YELLOW}[PHASE 2] SQL Injection${NC}"

echo "[*] Test SQLi basique..."
curl -s -o /dev/null "$TARGET/rest/products/search?q=test' OR '1'='1"
echo "  Payload : OR 1=1 envoyé"

echo "[*] Test UNION SELECT..."
curl -s -o /dev/null "$TARGET/rest/products/search?q=test' UNION SELECT null,null,null--"
echo "  Payload : UNION SELECT envoyé"

echo "[*] Test SQL avec commentaire..."
curl -s -o /dev/null "$TARGET/rest/products/search?q=1'; DROP TABLE users;--"
echo "  Payload : DROP TABLE envoyé"

# PHASE 3 : XSS
echo -e "\n${YELLOW}[PHASE 3] Cross-Site Scripting (XSS)${NC}"

echo "[*] Test XSS basique..."
curl -s -o /dev/null "$TARGET/rest/products/search?q=<script>alert('XSS')</script>"
echo "  Payload : script alert envoyé"

echo "[*] Test XSS encodé..."
curl -s -o /dev/null "$TARGET/rest/products/search?q=%3Cscript%3Ealert%281%29%3C%2Fscript%3E"
echo "  Payload : XSS encodé envoyé"

# PHASE 4 : Path Traversal
echo -e "\n${YELLOW}[PHASE 4] Path Traversal${NC}"

echo "[*] Test traversée de répertoire..."
curl -s -o /dev/null "$TARGET/../../../../etc/passwd"
curl -s -o /dev/null "$TARGET/assets/../../../etc/shadow"
echo "  Payloads : path traversal envoyés"

# PHASE 5 : Faux positif intentionnel
echo -e "\n${YELLOW}[PHASE 5] Génération d'un faux positif${NC}"

echo "[*] Requête légitime avec apostrophe (ex: recherche \"O'Reilly\")..."
curl -s -o /dev/null "$TARGET/rest/products/search?q=O'Reilly"
echo "  Requête légitime envoyée (potentiel faux positif WAF)"

# Résumé 
echo -e "\n${GREEN}===================================${NC}"
echo -e "${GREEN}  SIMULATION TERMINÉE${NC}"
echo -e "${GREEN}====================================${NC}"
echo -e "Vérifie maintenant Grafana → Explore → Loki"
echo -e "LogQL : ${BLUE}{job=\"waf\"}${NC}"
echo -e "Filtre blocages : ${BLUE}{job=\"waf\"} |= \"403\"${NC}"
