# Rapport d'Incident Sécurité — DevSecOps Web Lab
**Date :** 2026-06-18  
**Analyste :** KPODONOU K. Gaël  
**Sévérité :** Haute (simulation contrôlée)  
**Statut :** Résolu

---

## 1. Résumé Exécutif

Une simulation de kill chain a été conduite sur l'infrastructure 
DevSecOps Web Lab afin de valider l'efficacité du WAF 
(Nginx + ModSecurity + OWASP CRS) déployé devant l'application 
OWASP Juice Shop. L'attaque a couvert quatre phases : 
reconnaissance, injection SQL, XSS, et path traversal. 
Le WAF a détecté et bloqué l'ensemble des payloads malveillants. 
Un faux positif a été identifié et corrigé via une règle 
d'exception déployée en IaC.

---

## 2. Infrastructure Cible

| Composant | Rôle | Technologie |
|---|---|---|
| WAF | Reverse proxy + pare-feu applicatif | Nginx + ModSecurity + OWASP CRS |
| Juice Shop | Application web vulnérable (cible) | Node.js / Angular |
| MySQL | Base de données | MySQL 8.0 (hardenée) |
| Loki + Grafana | Centralisation et visualisation des logs | Grafana Stack |

Réseau isolé `devsecops-net` — Juice Shop non exposé directement,
uniquement accessible via le WAF sur le port 8080.

---

## 3. Chronologie de l'Attaque

| Heure | Phase | Action | Résultat WAF |
|---|---|---|---|
| 09:43:50 | Reconnaissance | Scan de chemins sensibles (`/admin`, `/.git/config`) | 200 (Juice Shop SPA absorbe) |
| 09:44:03 | SQLi | `OR '1'='1` | **403 Bloqué** |
| 09:44:06 | SQLi | `UNION SELECT null,null,null--` | **403 Bloqué** |
| 09:44:12 | SQLi | `DROP TABLE users;--` | **403 Bloqué** |
| 09:44:20 | XSS | `<script>alert('XSS')</script>` | **403 Bloqué** |
| 09:44:26 | XSS encodé | `%3Cscript%3Ealert%281%29` | **403 Bloqué** |
| 09:44:31 | Path Traversal | `../../../../etc/passwd` | **403 Bloqué** |
| 09:44:45 | Faux positif | `O'Reilly` (recherche légitime) | 200 (OK) |

---

## 4. Analyse des Logs (LogQL)

**Requête de détection des blocages :**
```logql
{job="waf"} |= "403"
```

**Observation :** pic de 403 entre 09:44:00 et 09:45:00 
correspondant exactement à la simulation d'attaque. 
Toutes les requêtes légitimes (200) ont continué à passer 
normalement — aucune interruption de service.

---

## 5. Faux Positif Identifié

**Symptôme :** Les connexions WebSocket de Juice Shop vers 
`/socket.io/` recevaient des HTTP 403. L'application perdait 
sa connexion temps réel.

**Cause racine :** Les paramètres `EIO`, `transport` et `sid` 
dans l'URL Socket.IO déclenchent la règle CRS 
`REQUEST-920-PROTOCOL-ENFORCEMENT` (score d'anomalie trop élevé).

**Remédiation :**
```nginx
SecRule REQUEST_URI "@beginsWith /socket.io/" \
    "id:1001,phase:1,pass,nolog,\
    ctl:ruleEngine=DetectionOnly,\
    msg:'Exclusion socket.io - trafic legitime Juice Shop'"
```

Déployée via Ansible (`waf-setup.yml`) — idempotente et versionnée.

**Vérification post-remédiation :**
```bash
curl http://localhost:8080/socket.io/?EIO=4&transport=polling → 200 ✅
curl "http://localhost:8080/rest/products/search?q=UNION SELECT" → 403 ✅
```

---

## 6. Hardening Base de Données

En parallèle de l'analyse WAF, le playbook `db-hardening.yml` 
a appliqué les contrôles CIS Benchmark MySQL 8.0 :

- Suppression des utilisateurs anonymes
- Restriction de root aux connexions locales uniquement
- Politique de mots de passe (validate_password MEDIUM, 12 caractères)
- SSL/TLS activé (`require_secure_transport = ON`)
- Désactivation de `local-infile` et `symbolic-links`
- Création d'un utilisateur applicatif avec privilèges minimaux

---

## 7. Recommandations

**Court terme :**
- Activer les logs d'audit ModSecurity (`/var/log/modsec_audit.log`) 
  pour avoir le détail des règles déclenchées par ID
- Configurer une alerte Grafana sur `count_over_time({job="waf"} |= "403" [1m]) > 10`

**Moyen terme :**
- Remplacer les secrets Terraform (`terraform.tfvars`) par 
  Podman Secrets ou un gestionnaire de secrets dédié
- Passer les images Docker sur des versions pinned 
  (éviter `:latest` en production)

**Long terme :**
- Intégrer un SIEM (Wazuh) pour corréler les événements 
  WAF avec d'autres sources de logs
- Mettre en place un pipeline CI/CD qui relance `site.yml` 
  à chaque commit (GitOps)

---

## 8. Conclusion

L'infrastructure DevSecOps déployée en IaC (Terraform + Ansible) 
démontre une protection applicative efficace. Le WAF bloque 
les vecteurs d'attaque OWASP Top 10 les plus courants tout en 
permettant le tuning des faux positifs via des règles d'exception 
versionnées. La chaîne d'observabilité Promtail → Loki → Grafana 
permet une détection et une analyse en temps quasi-réel.