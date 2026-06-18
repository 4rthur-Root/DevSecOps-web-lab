#!/bin/bash

# simulate_killchain.sh - Simulation d'attaque DevSecOps Lab
# Cible : WAF (http://localhost:8080) → Juice Shop
# Phases : Reconnaissance (A02) → SQLi (A05) → XSS (A05) → Path Traversal (A01)
# Mapping OWASP Top 10 2025


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
# OWASP Top 10 2025 — A02:2025 Security Misconfiguration
# Chemins sensibles exposés, pages par défaut, information disclosure
echo -e "\n${YELLOW}[PHASE 1] Reconnaissance ${RED}(A02 Security Misconfiguration)${NC}"

echo "[*] Scan de chemins sensibles..."
for path in /admin /server-status /phpinfo.php /.git/config /backup /api/users; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET$path")
    echo "  $path → HTTP $STATUS"
    sleep 0.3
done

# PHASE 2 : SQL Injection
# OWASP Top 10 2025 — A05:2025 Injection
# Manipulation de requêtes SQL via des entrées non filtrées
echo -e "\n${YELLOW}[PHASE 2] SQL Injection ${RED}(A05 Injection)${NC}"

HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/rest/products/search?q=test%27%20OR%20%271%27=%271")
echo "  Payload : OR 1=1 → HTTP $HTTP"

HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/rest/products/search?q=test%27%20UNION%20SELECT%20null,null,null--")
echo "  Payload : UNION SELECT → HTTP $HTTP"

HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/rest/products/search?q=1%27;%20DROP%20TABLE%20users;--")
echo "  Payload : DROP TABLE → HTTP $HTTP"

# PHASE 3 : XSS
# OWASP Top 10 2025 — A05:2025 Injection (XSS)
# Injection de scripts malveillants dans des pages web consultées par d'autres utilisateurs
echo -e "\n${YELLOW}[PHASE 3] Cross-Site Scripting (XSS) ${RED}(A05 Injection)${NC}"

HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/rest/products/search?q=%3Cscript%3Ealert(%27XSS%27)%3C/script%3E")
echo "  Payload : script alert → HTTP $HTTP"

HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/rest/products/search?q=%3Cscript%3Ealert%281%29%3C%2Fscript%3E")
echo "  Payload : XSS encodé → HTTP $HTTP"

# PHASE 4 : Path Traversal
# OWASP Top 10 2025 — A01:2025 Broken Access Control
# Contournement des restrictions d'accès pour lire des fichiers hors de la racine web
echo -e "\n${YELLOW}[PHASE 4] Path Traversal ${RED}(A01 Broken Access Control)${NC}"

HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/../../../../etc/passwd")
echo "  Payload : /../../../../etc/passwd → HTTP $HTTP"

HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/assets/../../../etc/shadow")
echo "  Payload : /assets/../../../etc/shadow → HTTP $HTTP"

# PHASE 5 : Faux positif intentionnel
# WAF Tuning — requête légitime avec apostrophe (test de non-régression)
# Vérifie que le WAF ne bloque pas une recherche utilisateur normale contenant une apostrophe
echo -e "\n${YELLOW}[PHASE 5] Faux Positif — WAF Tuning${NC}"

HTTP=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/rest/products/search?q=O%27Reilly")
echo "  Payload : O'Reilly → HTTP $HTTP (attendu : 200, sinon faux positif)"

# Résumé
echo -e "\n${GREEN}==========================================${NC}"
echo -e "${GREEN}  SIMULATION TERMINÉE${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo -e "${BLUE}--- OWASP Top 10 2025 Mapping ---${NC}"
echo -e "  ${RED}A01${NC} — Broken Access Control       → Path Traversal"
echo -e "  ${RED}A02${NC} — Security Misconfiguration   → Reconnaissance"
echo -e "  ${RED}A05${NC} — Injection                   → SQLi + XSS"
echo ""
echo -e "Vérifie maintenant Grafana → Explore → Loki"
echo -e "LogQL : ${BLUE}{job=\"waf\"}${NC}"
echo -e "Filtre blocages : ${BLUE}{job=\"waf\"} |= \"403\"${NC}"
