# DevSecOps Web Lab — Roadmap V2

## Objective

Transform the project from a tool catalog into a **complete and functional SOC workflow**: detect, investigate, respond, document.

Final result: a portfolio that shows you know how to **defend**, not just **deploy**.

---

## Current State (V1) — What Works

| Component | Status | Notes |
|-----------|--------|-------|
| Terraform (5 containers) | OK | Stable infrastructure |
| Ansible (WAF + DB + monitoring) | OK | Functional but needs fixes |
| ModSecurity + OWASP CRS | OK | 846 rules in blocking mode |
| Juice Shop | OK | Functional target application |
| MySQL 8.0 hardened | OK | CIS Benchmark-style |
| Grafana + Loki + Promtail | ISSUE | Dashboard shows nothing or poorly |
| Attack script | BASIC | Bash, single pass, no SOC logic |
| Documentation | GOOD | ISSUES.md excellent, more to complete |

---

## Phase 1 — Fix Log Pipeline (2-3 days)

**Absolute priority.** Without visible logs, nothing else makes sense.

### 1.1 Verify Promtail

- Confirm Promtail is running in the WAF container
- Verify file paths: `/var/log/nginx/access.log` and `error.log`
- Ensure logs are in JSON format (current format)
- Test with `curl` to WAF and verify Loki receives data

### 1.2 Verify Loki

- Test Loki connectivity from Grafana
- Verify labels in Loki (job, filename, etc.)
- Ensure Loki datasource is properly configured

### 1.3 Fix Dashboard

- Valid and functional LogQL queries
- Panel 1: Log volume (real-time)
- Panel 2: Blocked requests (status 403) in red
- Panel 3: Top 10 attacked URIs
- Add Panel 4: Ratio of blocked vs total requests

### 1.4 Expected Result

A Grafana dashboard showing in real-time HTTP requests passing through the WAF, with clear distinction between normal requests (200) and blocked requests (403).

---

## Phase 2 — Setup Attacker with Kali Linux (3-4 days)

### 2.1 Network Architecture

```
┌─────────────────┐     ┌──────────────────────────────────────┐
│   Kali Linux    │────▶│  devsecops-net Network (Podman)      │
│   (VM or        │     │                                      │
│    container)   │     │  WAF :8080 → Juice Shop :3000        │
└─────────────────┘     │  Grafana :3001                       │
                        │  MySQL :3306 (internal)               │
                        └──────────────────────────────────────┘
```

**Options for Kali:**
- **Option A (recommended)**: Kali VM in VirtualBox/VMware, connected to same Podman network
- **Option B**: Kali container in Podman on same `devsecops-net` network
- **Option C**: Native Kali on host machine, access via `localhost:8080`

### 2.2 Attacks to Simulate

Each attack should be documented with:
- Tool used
- Exact command
- Expected result (blocked or not)
- OWASP Top 10 2025 mapping
- MITRE ATT&CK mapping

| Attack | Tool | OWASP | MITRE | Expected Result |
|--------|------|-------|-------|-----------------|
| SQL Injection | SQLMap | A03:2021 Injection | T1190 | Blocked by WAF (403) |
| Reflected XSS | curl/Burp | A03:2021 Injection | T1189 | Blocked by WAF (403) |
| Port Scan | Nmap | N/A | T1046 | Detected in logs |
| Login Brute Force | Hydra/curl | A07:2021 Identification | T1110 | Detected (multiple 401s) |
| Path Traversal | curl | A01:2021 Broken Access | T1083 | Blocked by WAF (403) |
| Reconnaissance | Nikto/curl | N/A | T1595 | Detected in logs |
| Command Injection | curl | A03:2021 Injection | T1059 | Blocked by WAF (403) |

### 2.3 Improved Attack Script

Replace current bash script with structured script:
- Phase by phase with pause between each
- Log of each attack in dedicated file
- Structured output (JSON) for Grafana import
- `--dry-run` option to test without attacking

---

## Phase 3 — Alerting and Thresholds (2-3 days)

### 3.1 Grafana Alert Rules

Create alerts based on thresholds:

| Alert | Condition | Severity | Action |
|-------|-----------|----------|--------|
| Spike in blocked requests | > 10 in 1 minute | HIGH | Email/Slack notification |
| High 403 rate | > 50% of requests in 5 min | CRITICAL | Immediate notification |
| Port scan detected | > 50 different requests in 1 min | MEDIUM | Log + investigation |
| Login brute force | > 10 attempts in 1 min | HIGH | Email/Slack notification |
| New attack type | Request with SQLi/XSS patterns | INFO | Log for investigation |

### 3.2 Notification Channels

- **Email** (SMTP) — Basic but functional
- **Slack/Discord Webhook** — More modern
- **Grafana OnCall** (optional) — For the ambitious

### 3.3 Expected Result

When you launch an attack from Kali, you receive an alert in Grafana within 30 seconds.

---

## Phase 4 — Investigation Workflow (3-4 days)

### 4.1 Investigation Dashboard

Create a second Grafana dashboard dedicated to investigation:

**Panels:**
- Raw logs with filters (by IP, by URI, by status code)
- Timeline of requests from a specific IP
- Suspicious User-Agents chart
- List of IPs with most blocked requests
- Correlation: attack → incoming log → outgoing log

### 4.2 Investigation Methodology

For each alert, follow this process:

```
1. IDENTIFY      → What? When? From where?
2. CONTAIN       → Block IP? Disable endpoint?
3. ERADICATE     → Clean up traces? Fix vulnerability?
4. RECOVER       → Restore service?
5. LESSONS       → What do we improve?
```
3. ÉRADIQUER     → Nettoyer les traces ? Corriger la vulnérabilité ?
4. RÉCUPÉRER     → Remettre le service en place ?
5. LEÇONS        → Qu'est-ce qu'on améliore ?
```

### 4.3 IOCs (Indicators of Compromise)

Extraire et documenter pour chaque attaque :
- IP source
- User-Agent utilisé
- Patterns dans les URLs/body
- Timestamps
- Status codes retournés

---

## Phase 5 — Rapports d'Incident (2-3 jours)

### 5.1 Template de rapport

Créer un template structuré pour chaque incident :

```markdown
# Incident Report — [DATE] — [TYPE ATTAQUE]

## Résumé
- **Date/Heure** :
- **Source** :
- **Type** :
- **Sévérité** :
- **Statut** : Ouvert / En cours / Résolu

## Chronologie
| Heure | Événement |
|-------|-----------|
| HH:MM | Première détection |
| HH:MM | Escalade |
| HH:MM | Contention |
| HH:MM | Résolution |

## Détails techniques
- **IOCs** :
- **Logs concernés** :
- **OOT Réponse du WAF** :

## Impact
- **Services affectés** :
- **Données exposées** : Aucune / Limitée / Critique

## Actions correctives
- [ ] Action 1
- [ ] Action 2

## Leçons apprises
- Ce qui a bien fonctionné :
- Ce qui peut être amélioré :
```

### 5.2 Exemples remplis

Créer 3-4 rapports d'incident réels basés sur les attaques Kali :
- Rapport SQL Injection
- Rapport Scan de ports
- Rapport Brute force
- Rapport multi-attack (campaign)

---

## Phase 6 — Polish et Portfolio (2 jours)

### 6.1 README.md réécrit

- Architecture claire avec diagramme Mermaid
- Comment lancer le projet (3 commandes)
- Comment lancer les attaques (depuis Kali)
- Comment consulter les alertes
- Compétences démontrées
- Technologies utilisées

### 6.2 Démo

- Vidéo GIF ou screenshots montrant le workflow complet
- Attaque depuis Kali → Alerte dans Grafana → Investigation → Rapport

### 6.3 Structure finale du projet

```
DevSecOps-web-lab/
├── terraform/                    # Infrastructure
├── ansible/                      # Configuration
├── attack_simulation/            # Scripts d'attaque (ancien + nouveau)
├── kali/                         # Config Kali VM / conteneur
├── docs/
│   ├── architecture.md
│   ├── incident-reports/         # NOUVEAU — rapports d'incident
│   │   ├── 2026-08-26_sqli.md
│   │   ├── 2026-08-26_portscan.md
│   │   └── 2026-08-26_bruteforce.md
│   ├── investigation/            # NOUVEAU — notebooks d'investigation
│   │   └── methodology.md
│   ├── ISSUES.md
│   └── Resources.md
├── grafana/
│   ├── dashboards/
│   │   ├── security-overview.json    # Dashboard principal
│   │   └── investigation.json        # NOUVEAU — Dashboard investigation
│   └── alerting/                     # NOUVEAU — Règles d'alerte
├── V2_ROADMAP.md                  # Ce fichier
└── README.md
```

---

## Timeline Résumé

| Semaine | Focus | Livrable |
|---------|-------|----------|
| **S1** | Fix Grafana + Kali setup | Pipeline de logs fonctionnel + VM prête |
| **S2** | Attaques + Alerting | Attaques documentées + alertes fonctionnelles |
| **S3** | Investigation + Incident Response | Workflow complet + rapports remplis |
| **S4** (optionnel) | Polish | README, démo, structure finale |

**Total : 3-4 semaines à ~2h/jour = 40-55 heures**

---

## Ce que le portfolio démontrera à la fin

1. **Infrastructure IaC** — Terraform + Ansible (V1, déjà acquis)
2. **WAF Management** — ModSecurity + OWASP CRS, tuning faux positifs
3. **Monitoring SOC** — Grafana + Loki, alertes, dashboards
4. **Threat Detection** — Corrélation d'événements, patterns d'attaque
5. **Incident Investigation** — IOCs, timeline, analyse forensique basique
6. **Incident Response** — Processus structuré, rapports, leçons apprises
7. **Offensive Security** — Attaques depuis Kali (SQLi, XSS, scan, brute force)

---

## Limite du projet (à savoir)

- Pas de vrai SIEM (Splunk/QRadar) — mais la chaîne est identique en miniature
- Pas de réseau complexe — un seul sous-réseau, pas de DMZ
- Pas de vraie base de données production — Juice Shop est volontairement vulnérable
- Pas d'automatisation de remédiation — la réponse est manuelle (pour apprendre)

**Ce que ça ne remplace PAS :** Une vraie expérience SOC en entreprise. Mais ça montre que tu comprends le workflow, les outils, et la démarche. Et en entretien, pouvoir dire "j'ai détecté une SQLi, j'ai investigué, j'ai documenté l'IOC, j'ai proposé une remédiation" — ça vaut plus que n'importe quel certificat.
