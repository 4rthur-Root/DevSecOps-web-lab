# DevOps Security Lab - Resources & References

> This document brings together all resources, documentation and tools that enabled the design and deployment of this DevSecOps lab. Each section is organized by technical domain with a brief explanation of its usefulness in the project.

---

## Table of Contents

- [DevOps Security Lab - Resources \& References](#devops-security-lab---resources--references)
  - [Table of Contents](#table-of-contents)
  - [🔗 Inspiration Resources](#-inspiration-resources)
  - [📖 Official Documentation by Technology](#-official-documentation-by-technology)
  - [🛡️ Sécurité Applicative \& WAF](#️-sécurité-applicative--waf)
    - [🔑 Key Concepts Applied in This Project](#-key-concepts-applied-in-this-project)
  - [🐳 Conteneurisation \& Orchestration](#-conteneurisation--orchestration)
    - [Podman Rootless Issue Encountered](#podman-rootless-issue-encountered)
  - [🏗️ Infrastructure as Code (Terraform)](#️-infrastructure-as-code-terraform)
  - [⚙️ Configuration Management (Ansible)](#️-configuration-management-ansible)
  - [📊 Monitoring \& Observability (Grafana + Loki + Promtail)](#-monitoring--observability-grafana--loki--promtail)
    - [Requêtes LogQL utilisées](#requêtes-logql-utilisées)
  - [🕵️ Outils d'Attaque \& Simulation](#️-outils-dattaque--simulation)
  - [🔐 Références Hardening MySQL](#-références-hardening-mysql)
    - [📋 Récapitulatif](#-récapitulatif)
    - [🔧 Améliorations Critiques Apportées](#-améliorations-critiques-apportées)
      - [1. Politique de Mots de Passe (validate\_password)](#1-politique-de-mots-de-passe-validate_password)
      - [2. Configuration Sécurisée my.cnf](#2-configuration-sécurisée-mycnf)
      - [3. SSL/TLS pour les Connexions](#3-ssltls-pour-les-connexions)
      - [4. Audit Logging](#4-audit-logging)
    - [⚠️ Remarques Importantes](#️-remarques-importantes)
    - [🔍 Audit Final - Vérifications Intégrées](#-audit-final---vérifications-intégrées)
  - [📚 Sources Officielles](#-sources-officielles)
    - [Documentation de Référence](#documentation-de-référence)
    - [Vulnérabilités Récentes (Exemples)](#vulnérabilités-récentes-exemples)
  - [🎯 OWASP Top 10 2025 (en vigueur)](#-owasp-top-10-2025-en-vigueur)
    - [Évolution OWASP 2021 → 2025](#évolution-owasp-2021--2025)
  - [📚 Lectures Complémentaires DevSecOps](#-lectures-complémentaires-devsecops)
    - [Culture et Méthodologie](#culture-et-méthodologie)
    - [Outils DevSecOps](#outils-devsecops)
    - [Chaînes YouTube et Formations](#chaînes-youtube-et-formations)
  - [🎯 Conclusion du Projet](#-conclusion-du-projet)

---

## 🔗 Inspiration Resources

These resources inspired the overall design of the project:

| Resource | Usefulness in the project |
|----------|--------------------------|
| [OWASP Juice Shop](https://hub.docker.com/r/bkimminich/juice-shop) — Official Docker image | Intentionally vulnerable target application to test the WAF and simulate the kill chain |
| [OWASP ModSecurity CRS (Core Rule Set)](https://coreruleset.org/) — Official site | Set of OWASP rules for ModSecurity that equips the WAF (846 rules loaded) |
| [Grafana Loki](https://grafana.com/oss/loki/) — Official site | Centralized log aggregator, SOC monitoring backend |
| [Promtail](https://grafana.com/docs/loki/latest/send-data/promtail/) — Grafana documentation | Log collection agent deployed in the WAF container to feed Loki |
| [Database Hardening - Medium Guide](https://medium.com/@abhijitgm5/database-hardening-for-mysql-postgresql-oracle-mongodb-6f661b7ccd7c) | Comparative hardening MySQL / PostgreSQL / Oracle / MongoDB |
| [Oracle MySQL Security Guide](https://docs.oracle.com/en/database/oracle/mysql/8.0/security.html) | Official Oracle security guide for MySQL 8.0 |

---

## 📖 Official Documentation by Technology

Technical documentation used for development and debugging:

| Technologie | Documentation | Usage |
|-------------|---------------|-------|
| **Terraform** | [Provider Docker (kreuzwerker)](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs) | Provisioning 5 containers, Docker network, named volumes |
| **Terraform** | [docker_container resource](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/container) | Container configuration: ports, env vars, volumes |
| **Terraform** | [docker_network resource](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/network) | Isolated devsecops-net network for container isolation |
| **Terraform** | [docker_volume resource](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs/resources/volume) | Named waf-logs volume to work around bind mount permission issues (ISSUES.md #1) |
| **Ansible** | [lineinfile module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/lineinfile_module.html) | Modification of Nginx, ModSecurity and MySQL config files |
| **Ansible** | [community.mysql module](https://docs.ansible.com/ansible/latest/collections/community/mysql/index.html) | Execution of MySQL hardening queries |
| **Ansible** | [get_url module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/get_url_module.html) | Download Promtail binary to WAF container |
| **Ansible** | [raw module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/raw_module.html) | Bootstrap Python on target containers (workaround: no native Python) |
| **Ansible** | [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html) | Encryption of MySQL and Grafana passwords in vault.yml |
| **Ansible** | [Docker Connection](https://docs.ansible.com/ansible/latest/collections/community/docker/docker_connection.html) | Direct connection to containers via Docker socket (no SSH) |

---

## 🛡️ Sécurité Applicative & WAF

| Ressource | Description |
|-----------|-------------|
| [OWASP Top 10 2025](https://owasp.org/Top10/2025/) — Official page | Repository of the 10 most critical web security risks (2025 version in effect) |
| [OWASP ModSecurity CRS GitHub](https://github.com/coreruleset/coreruleset) | Source code and documentation of OWASP CRS rules |
| [ModSecurity Reference Manual](https://github.com/owasp-modsecurity/ModSecurity/wiki/Reference-Manual) | Comprehensive guide to ModSecurity directives (SecRuleEngine, SecDefaultAction, SecRule, etc.) |
| [ModSecurity-nginx Connector](https://github.com/owasp-modsecurity/ModSecurity-nginx) | Linking module between Nginx and ModSecurity |
| [OWASP CRS Documentation](https://coreruleset.org/docs/) | Official documentation: tuning, false positives, deployment |
| [OWASP CRS - Admin Guide](https://coreruleset.org/docs/admin/) | Administration guide: advanced installation, rule disabling, scoring |
| [Nginx ngx_http_modsecurity_module](https://nginx.org/en/docs/http/ngx_http_modsecurity_module.html) | Nginx documentation for ModSecurity activation |
| [CIS Benchmarks](https://www.cisecurity.org/benchmark/nginx) | CIS Benchmark for Nginx (secure configuration best practices) |
| [Mozilla Observatory](https://observatory.mozilla.org/) | Tool for analyzing HTTP security headers |

### 🔑 Key Concepts Applied in This Project

- **SecRuleEngine**: `DetectionOnly` (detection only) vs `On` (active blocking) — see ISSUES.md #12 for the impact of this distinction
- **SecDefaultAction**: Default action (`pass`, `deny`, `status:403`) when a CRS rule is triggered — critical parameter to transition from detection to prevention mode
- **Anomaly Scoring**: The CRS uses a cumulative scoring system (inbound/outbound) rather than immediate blocking — more flexible but requires explicit threshold configuration
- **Paranoia Level**: The CRS defines 4 paranoia levels (PL1 to PL4). PL1 is default (security/false positive balance), PL4 is extreme.

---

## 🐳 Conteneurisation & Orchestration

| Ressource | Description |
|-----------|-------------|
| [Podman Rootless Guide](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md) | Podman rootless mode guide (used in this project) |
| [Podman Socket Activation](https://www.redhat.com/sysadmin/podman-rootless-systemd) | Activating Podman socket for Terraform access |
| [Docker Volumes vs Bind Mounts](https://docs.docker.com/storage/volumes/) | Official documentation on volume/bind mount differences (see ISSUES.md #1) |
| [owasp/modsecurity-crs Docker Image](https://hub.docker.com/r/owasp/modsecurity-crs) | Official OWASP CRS image with Nginx — entrypoint and environment variables documented |
| [Image CRS - Environment Variables](https://github.com/coreruleset/modsecurity-crs-docker?tab=readme-ov-file#environment-variables) | Complete list of configurable `MODSEC_*`, `BACKEND`, `PARANOIA` variables |
| [Podman Secrets](https://docs.podman.io/en/latest/markdown/podman-secret.1.html) | Native Podman mechanism to manage secrets without exposing via `podman inspect` (see ISSUES.md #10) |

### Podman Rootless Issue Encountered

Automatic Grafana provisioning (mounting local folders) doesn't work with Podman rootless — see ISSUES.md #11. The workaround is manual datasource configuration. For a production environment, using Docker in root mode or a custom Dockerfile with proper permissions would be recommended.

---

## 🏗️ Infrastructure as Code (Terraform)

| Ressource | Description |
|-----------|-------------|
| [Terraform Docker Provider](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs) | Provider Docker pour Terraform — documentation complète |
| [Terraform Best Practices](https://developer.hashicorp.com/terraform/language/ best-practices) | Bonnes pratiques HashiCorp pour l'organisation du code Terraform |
| [Terraform sensitive variables](https://developer.hashicorp.com/terraform/language/values/variables#suppressing-values-in-cli-output) | Gestion des variables sensibles (`sensitive = true`) |
| [Terraform Grafana Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/) | Provisioning automatique des datasources et dashboards Grafana via Terraform |

---

## ⚙️ Configuration Management (Ansible)

| Ressource | Description |
|-----------|-------------|
| [Ansible Docker Connection Plugin](https://docs.ansible.com/ansible/latest/collections/community/docker/docker_connection.html) | Direct connection to Docker containers (no SSH) — used in inventory.ini |
| [Ansible Best Practices](https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html) | Project structure, role and playbook organization |
| [Ansible Vault Guide](https://docs.ansible.com/ansible/latest/vault_guide/index.html) | Encryption of sensitive variables with ansible-vault |
| [Ansible lineinfile](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/lineinfile_module.html) | Modification of lines in configuration files |
| [Ansible MySQL modules](https://docs.ansible.com/ansible/latest/collections/community/mysql/index.html) | `mysql_user`, `mysql_db`, `mysql_query` modules for MySQL hardening |
| [Ansible raw module](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/raw_module.html) | Execution of raw commands without Python dependency (bootstrap) |
| [Ansible Jinja2 templating](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_templating.html) | Using templates and variables in playbooks |

---

## 📊 Monitoring & Observability (Grafana + Loki + Promtail)

| Ressource | Description |
|-----------|-------------|
| [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/) | Complete Loki documentation: architecture, configuration, LogQL |
| [LogQL Reference](https://grafana.com/docs/loki/latest/logql/) | LogQL query language: filters, aggregations, transformations |
| [LogQL Sample Queries](https://grafana.com/docs/loki/latest/query/sample_queries/) | Concrete examples of LogQL queries used in dashboards |
| [Promtail Configuration](https://grafana.com/docs/loki/latest/send-data/promtail/configuration/) | Promtail config file: scrape_configs, labels, pipeline |
| [Grafana Dashboard JSON](https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/manage-version/) | Grafana dashboard JSON structure for IaC |
| [Grafana Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/) | Automatic provisioning of datasources and dashboards |
| [Loki API](https://grafana.com/docs/loki/latest/reference/api/) | Loki REST API for direct HTTP queries |

### Requêtes LogQL utilisées

```logql
# Volume total de logs
count_over_time({job="waf"} [$__interval])

# Logs bloqués (403)
count_over_time({job="waf"} |= "403" [$__interval])

# Top URIs attaquées
topk(10, sum by (uri) (count_over_time({job="waf"} |= "403" | json | __error__="" [$__interval])))
```

---

## 🕵️ Outils d'Attaque & Simulation

| Outil | Documentation | Utilisation dans le projet |
|-------|---------------|---------------------------|
| [SQLMap](https://github.com/sqlmapproject/sqlmap) — GitHub officiel | Outil d'injection SQL automatisé | Test avancé d'exploitation SQLi (Phase 2 de la kill chain) |
| [SQLMap Wiki](https://github.com/sqlmapproject/sqlmap/wiki) | Usage détaillé : options, techniques d'injection, contournement WAF | Documentation des paramètres de test |
| [Nmap](https://nmap.org/docs.html) — Documentation officielle | Scanner de ports et de services | Reconnaissance réseau (Phase 1 de la kill chain) |
| [Nmap Scripting Engine (NSE)](https://nmap.org/nsedoc/) | Scripts NSE automatisés pour la découverte de vulnérabilités | Scan de vulnérabilités sur l'infrastructure |
| [Gobuster](https://github.com/OJ/gobuster) | Outil de brute-force de chemins web et DNS | Découverte de chemins cachés sur Juice Shop |
| [cURL Guide](https://curl.se/docs/manual.html) | Guide d'utilisation de cURL pour les requêtes HTTP | Envoi des payloads malveillants dans le script de kill chain |

---

## 🔐 Références Hardening MySQL

### 📋 Récapitulatif

**Objectif**  
Ce playbook Ansible implémente un hardening de niveau production pour MySQL 8.0, conforme aux recommandations CIS Benchmarks et aux bonnes pratiques de sécurité actuelles.

**Structure du Playbook**

| Section | Description |
|---------|-------------|
| Prérequis | Installation de Python3-Pip et PyMySQL |
| Nettoyage initial | Suppression utilisateurs anonymes, base test, restriction root |
| Politique de mots de passe | Activation du composant validate_password (niveau MEDIUM) |
| Configuration serveur | Application des paramètres sécurisés dans my.cnf |
| SSL/TLS | Chiffrement des communications avec certificats |
| Moindre privilège | Création d'un utilisateur applicatif dédié |
| Audit logging | Installation et configuration du plugin audit_log |
| Vérifications finales | Audit des utilisateurs, plugins et variables SSL |

---

### 🔧 Améliorations Critiques Apportées

#### 1. Politique de Mots de Passe (validate_password)

Le composant validate_password impose une politique de mots de passe robuste :

```yaml
validate_password.policy = MEDIUM      # Longueur + caractères obligatoires
validate_password.length = 12           # Longueur minimale
validate_password.mixed_case_count = 1    # Majuscule/minuscule
validate_password.number_count = 1      # Chiffre
validate_password.special_char_count = 1  # Caractère spécial
```

> **Pourquoi c'est critique** : Selon la documentation MySQL, sans ce composant, les comptes peuvent se voir attribuer des mots de passe de moins de 8 caractères, voire aucun mot de passe. La politique MEDIUM ajoute des conditions de complexité essentielles.

#### 2. Configuration Sécurisée my.cnf

Paramètres de durcissement applicables :

```ini
bind-address = 127.0.0.1                   # Écoute locale uniquement
max_connections = 100                        # Limite de connexions
max_connect_errors = 10                    # Protection contre les attaques par force brute
log_error = /var/log/mysql/error.log       # Chemin du log d'erreurs
general_log = 0                            # Désactivation du log général
secure-file-priv = /var/lib/mysql-files     # Restriction des opérations de fichier
sql_mode = STRICT_TRANS_TABLES,NO_ENGINE_SUBSTITUTION
local-infile = 0                           # Désactivation LOAD DATA LOCAL INFILE
symbolic-links = 0                         # Désactivation des liens symboliques
skip-name-resolve = 1                      # Résolution DNS désactivée
max_allowed_packet = 16M                     # Limite de taille des paquets
```

#### 3. SSL/TLS pour les Connexions

Configuration SSL pour chiffrer toutes les connexions :

```ini
ssl-ca = /etc/mysql/ssl/server-cert.pem
ssl-cert = /etc/mysql/ssl/server-cert.pem
ssl-key = /etc/mysql/ssl/server-key.pem
require_secure_transport = ON              # Rend SSL obligatoire
```

> **Note** : L'activation de `require_secure_transport` impose que tous les clients se connectent en utilisant des connexions chiffrées.

#### 4. Audit Logging

Le plugin audit_log permet de tracer toutes les activités :

```ini
audit_log_policy = ALL                    # Journalisation de toutes les actions
audit_log_format = JSON                   # Format structuré
audit_log_rotate_on_size = 104857600       # Rotation automatique à 100 Mo
```

> **Fonctionnalités** : Le plugin enregistre les connexions/déconnexions clients et les actions effectuées (accès aux bases de données, tables).

---

### ⚠️ Remarques Importantes

- **Certificats SSL auto-signés** : Utilisés pour l'exemple. En production, préférez des certificats signés par une CA interne ou externe.
- **Variables sensibles** : Les mots de passe (`mysql_root_password`, `app_password`) doivent être stockés dans Ansible Vault, pas en clair.
- **Adaptation conteneur** : Si vous utilisez un conteneur sans systemd, le handler de redémarrage doit être adapté (redémarrage du conteneur).
- **Sockets Unix** : Vérifiez le chemin du socket (`/var/run/mysqld/mysqld.sock` ou `/var/lib/mysql/mysql.sock`) selon votre installation.
- **MySQL Enterprise Audit** : Le plugin audit_log est inclus dans MySQL Enterprise Edition (commercial). Pour la version Community, des alternatives existent (logs généraux, plugins tiers).

---

### 🔍 Audit Final - Vérifications Intégrées

Le playbook exécute automatiquement :

| Vérification | Commande | Objectif |
|--------------|----------|----------|
| Utilisateurs | `SELECT user, host FROM mysql.user;` | Auditer les comptes restants |
| Plugins de sécurité | `SHOW PLUGINS;` | Vérifier installation validate_password et audit_log |
| Variables SSL | `SHOW VARIABLES LIKE '%ssl%';` | Vérifier configuration SSL active |

---

## 📚 Sources Officielles

### Documentation de Référence

| Source | Description |
|--------|-------------|
| [CIS Benchmark MySQL 8.0](https://ncp.nist.gov/checklist/993) | Guide prescriptif pour la configuration sécurisée de MySQL 8.0 - Référence NIST |
| [MySQL validate_password Component](https://dev.mysql.com/doc/refman/8.0/en/validate-password-component.html) | Documentation officielle sur la politique de mots de passe |
| [MySQL Encrypted Connections](https://docs.oracle.com/cd/E17952_01/mysql-8.0-en/using-encrypted-connections.html#using-encrypted-connections-server-side-runtime-configuration) | Configuration SSL/TLS pour MySQL |
| [MySQL Enterprise Audit](https://dev.mysql.com/doc/refman/8.0/en/audit-log.html) | Documentation du plugin d'audit |
| [TLS Protocol Configuration](https://docs.oracle.com/cd/E17952_01/mysql-5.7-en/encrypted-connection-protocols-ciphers.html#encrypted-connection-deprecated-protocols) | Configuration des protocoles TLS et dépréciation TLSv1/TLSv1.1 |

### Vulnérabilités Récentes (Exemples)

| CVE | Produit | Version concernée | Impact |
|-----|---------|-------------------|--------|
| [CVE-2025-53053](https://vuldb.com/vuln/329177) | MySQL | 8.0.0-8.0.43, 8.4.0-8.4.6 | Impropre autorisation dans le composant DML — accès non autorisé et déni de service |
| CVE-2025-50104 | MySQL | 8.0.0-8.0.42, 8.4.0-8.4.5 | Déni de service dans le composant DDL |
| [CVE-2025-53044](https://vuldb.com/vuln/329168) | Nginx | < 1.30.1 | Problème de chemin dans le module MP4 pouvant causer un déni de service |
| [CVE-2025-24016](https://security.archlinux.org/AVG-2677) | Wazuh | < 4.11.2 | Path traversal via l'API REST permettant l'exécution de code arbitraire |
| [CVE-2024-56137](https://github.com/jupyter-server/jupyter_server/security/advisories/GHSA-rj9v-hgc9-xc4c) | Jupyter | < 2.15.0 | Cross-Site Scripting (XSS) dans l'interface web |
| [CVE-2024-47533](https://nvd.nist.gov/vuln/detail/CVE-2024-47533) | Nginx | < 1.27.3 | Problème de gestion mémoire dans le module auth-jwt |
| [CVE-2025-29927](https://github.com/advisories/GHSA-q2j7-f5f3-83r6) | Next.js | < 15.2.3 | Middleware bypass — contournement des vérifications d'authentification |
| [CVE-2024-21626](https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2024-21626) | Podman / Docker | runc < 1.1.12 | Échappement de conteneur via `runc` — fuite du descripteur de fichier du processus |

> **Enseignement** : Ces vulnérabilités récentes démontrent l'importance de maintenir l'ensemble de la stack à jour. Un WAF peut bloquer des attaques applicatives, mais la sécurité de l'infrastructure sous-jacente (conteneurisation, serveur web, base de données) reste primordiale.

---

## 🎯 OWASP Top 10 2025 (en vigueur)

Le référentiel officiel pour les risques de sécurité web, version 2025 (active depuis début 2026) :

| Rang | Catégorie | Lien | Correspondance dans le projet |
|------|-----------|------|-------------------------------|
| **A01** | Broken Access Control | [OWASP A01](https://owasp.org/Top10/2025/A01/) | Path Traversal (Phase 4 kill chain) |
| **A02** | Security Misconfiguration | [OWASP A02](https://owasp.org/Top10/2025/A02/) | Reconnaissance — chemins exposés (/admin, /phpinfo.php, /.git) |
| **A03** | Software Supply Chain Failures | [OWASP A03](https://owasp.org/Top10/2025/A03/) | Images Docker et dépendances tierces (Juice Shop, MySQL, Grafana) |
| **A04** | Cryptographic Failures | [OWASP A04](https://owasp.org/Top10/2025/A04/) | Chiffrement SSL/TLS MySQL — certificats auto-signés |
| **A05** | Injection | [OWASP A05](https://owasp.org/Top10/2025/A05/) | SQLi + XSS (Phases 2 et 3 kill chain) |
| **A06** | Insecure Design | [OWASP A06](https://owasp.org/Top10/2025/A06/) | Architecture du projet — principe de défense en profondeur |
| **A07** | Authentication Failures | [OWASP A07](https://owasp.org/Top10/2025/A07/) | Endpoint /api/users retourne 401 — authentification manquante contournée |
| **A08** | Software or Data Integrity Failures | [OWASP A08](https://owasp.org/Top10/2025/A08/) | Ansible Vault pour l'intégrité des secrets — signature des playbooks |
| **A09** | Security Logging and Alerting Failures | [OWASP A09](https://owasp.org/Top10/2025/A09/) | Stack Loki + Grafana — logging centralisé et alerting SOC |
| **A10** | Mishandling of Exceptional Conditions | [OWASP A10](https://owasp.org/Top10/2025/A10/) | Gestion des erreurs — analyse des faux positifs WAF et tuning |

### Évolution OWASP 2021 → 2025

Les changements majeurs de cette version :
- **A03:2025 Software Supply Chain Failures** — nouvelle catégorie (fusion d'A06:2021 Vulnerable Components et A08:2021 Integrity Failures)
- **A10:2025 Mishandling of Exceptional Conditions** — nouvelle catégorie (remplace SSRF)
- **A02:2025 Security Misconfiguration** — remonté de A05:2021 (reconnaissance des risques de mauvaise configuration)
- XSS déplacé dans **A05:2025 Injection** (auparavant A07:2017, puis fusionné dans A03:2021)

---

## 📚 Lectures Complémentaires DevSecOps

### Culture et Méthodologie

| Ressource | Description |
|-----------|-------------|
| [DevSecOps Manifesto](https://www.devsecops.org/) | Principes fondamentaux du mouvement DevSecOps |
| [STRIDE Threat Model (Microsoft)](https://learn.microsoft.com/en-us/azure/security/develop/threat-modeling-tool-threats) | Modélisation des menaces : Spoofing, Tampering, Repudiation, Information Disclosure, DoS, Elevation of Privilege |
| [MITRE ATT&CK Framework](https://attack.mitre.org/) | Base de connaissances des tactiques et techniques d'attaque (utilisé pour structurer la kill chain) |
| [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework) | Framework de cybersécurité du NIST : Identify, Protect, Detect, Respond, Recover |
| [NSA Kubernetes Hardening](https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF) | Guide de durcissement Kubernetes de la NSA |
| [CIS Controls v8](https://www.cisecurity.org/controls/v8) | Liste des 18 contrôles de sécurité prioritaires du CIS |

### Outils DevSecOps

| Outil | Documentation | Usage dans un contexte professionnel |
|-------|---------------|--------------------------------------|
| [Trivy](https://github.com/aquasecurity/trivy) | Scanner de vulnérabilités pour conteneurs et IaC | Scan des images Docker (Juice Shop, MySQL) pour les CVE |
| [Checkov](https://www.checkov.io/) | Analyse statique de code Terraform | Détection des misconfigurations IaC avant apply |
| [Dockle](https://github.com/goodwithtech/dockle) | Linter de sécurité pour Dockerfiles | Vérification des bonnes pratiques de construction d'images |
| [HashiCorp Vault](https://www.vaultproject.io/docs) | Gestionnaire de secrets | Alternative Enterprise à Ansible Vault pour la gestion centralisée des secrets |
| [SonarQube](https://www.sonarsource.com/products/sonarqube/) | Analyse statique de code | Détection des vulnérabilités dans le code source applicatif |
| [ZAP (Zed Attack Proxy)](https://www.zaproxy.org/) | Scanner de sécurité web open-source | Alternative/supplément aux attaques manuelles pour l'audit de Juice Shop |
| [Wazuh](https://documentation.wazuh.com/current/) | SIEM open-source | Alternative à Loki/Grafana — corrélation d'événements et alerting avancé |
| [OpenSCAP](https://www.open-scap.org/) | Scanning de conformité (CIS, DISA) | Vérification de conformité des hôtes et conteneurs aux benchmarks CIS |

### Chaînes YouTube et Formations

| Ressource | Description |
|-----------|-------------|
| [IppSec](https://www.youtube.com/@ippsec) — YouTube | Walkthroughs de machines HackTheBox — excellent pour comprendre les techniques d'attaque |
| [John Hammond](https://www.youtube.com/@_JohnHammond) — YouTube | Analyse de malwares, CTFs et défis de cybersécurité |
| [The Cyber Mentor](https://www.youtube.com/@TCMSecurityAcademy) — YouTube | Formations gratuites en pentesting et rédaction de rapports d'incident |
| [HackerSploit](https://www.youtube.com/@HackerSploit) — YouTube | Sécurité offensive et défensive, déploiements DevSecOps |
| [PwnFunction](https://www.youtube.com/@PwnFunction) — YouTube | Explications claires des vulnérabilités web (XSS, CSRF, SSRF) avec animations |
| [Cours OWASP Top 10 (PortSwigger)](https://portswigger.net/web-security) | Academy interactive de PortSwigger (Burp Suite) — labs gratuits sur chaque catégorie OWASP |
| [HackTheBox Academy](https://academy.hackthebox.com/) | Modules structurés sur l'énumération, l'exploitation et la post-exploitation |

---

## 🎯 Conclusion du Projet

Ce laboratoire couvre l'ensemble des phases d'un projet DevSecOps :

| Phase | Réalisé | Technologie |
|-------|---------|-------------|
| **Provisionnement** | ✅ 5 conteneurs, réseau isolé, volumes | Terraform + Docker/Podman |
| **Configuration** | ✅ Durcissement WAF, DB, monitoring | Ansible + Ansible Vault |
| **Détection** | ✅ Logs centralisés, format JSON, LogQL | Grafana + Loki + Promtail |
| **Attaque** | ✅ Kill chain complète (recon → SQLi → XSS → path traversal) | SQLMap + Nmap + cURL |
| **Défense** | ✅ Blocage WAF (403), règles OWASP CRS, tuning faux positif | ModSecurity + OWASP CRS |
| **Documentation** | ✅ Troubleshooting (11 incidents), mapping OWASP 2025, rapport d'incident | ISSUES.md, Resources.md |
| **IaC** | ✅ Versionné, reproductible, sensible chiffré | Terraform + Ansible Vault |

> **Leçon principale** : Un WAF en mode `DetectionOnly` sans `SecDefaultAction = deny` n'est qu'un observateur passif. La sécurité réelle naît de l'alignement de toute la chaîne — provisioning, configuration, surveillance et réponse aux incidents.