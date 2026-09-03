# 🛡️ Analyse Complète et Guide d'Architecture — DevSecOps Web Lab

> **Document de synthèse et de vulgarisation technique**  
> Ce document a pour objectif d'expliquer l'intégralité du projet **DevSecOps Web Lab**, de détailler le fonctionnement et pratique de **Terraform** et d'**Ansible** au travers d'exemples précis tirés du code, et de fournir une **explication et justification exhaustive, fichier par fichier**, de tous les éléments composant ce dépôt.

---

## 📑 Table des Matières

1. [Vue d'Ensemble & Vision Architecturale](#1-vue-densemble--vision-architecturale)
2. [Comprendre Terraform : Principes & Exemples Concrets du Projet](#2-comprendre-terraform--principes--exemples-concrets-du-projet)
3. [Comprendre Ansible : Principes & Exemples Concrets du Projet](#3-comprendre-ansible--principes--exemples-concrets-du-projet)
4. [Synergie Terraform + Ansible : La Séparation des Responsabilités](#4-synergie-terraform--ansible--la-séparation-des-responsabilités)
5. [Analyse et Justification Exhaustive Fichier par Fichier](#5-analyse-et-justification-exhaustive-fichier-par-fichier)
   - [5.1 Racine du Projet](#51-racine-du-projet)
   - [5.2 Infrastructure as Code — Dossier `terraform/`](#52-infrastructure-as-code--dossier-terraform)
   - [5.3 Configuration Management — Dossier `ansible/`](#53-configuration-management--dossier-ansible)
   - [5.4 Fichiers de Configuration Déployés — `ansible/files/`](#54-fichiers-de-configuration-déployés--ansiblefiles)
   - [5.5 Playbooks Ansible — `ansible/playbooks/`](#55-playbooks-ansible--ansibleplaybooks)
   - [5.6 Simulation Offensive — Dossier `attack_simulation/`](#56-simulation-offensive--dossier-attack_simulation)
   - [5.7 Tableaux de Bord & Observabilité — Dossier `grafana/`](#57-tableaux-de-bord--observabilité--dossier-grafana)
   - [5.8 Dossier `logs/`](#58-dossier-logs)
   - [5.9 Documentation Technique & Preuves — Dossier `docs/`](#59-documentation-technique--preuves--dossier-docs)
6. [Flux Opérationnel Bout en Bout (Cycle de Vie)](#6-flux-opérationnel-bout-en-bout-cycle-de-vie)
7. [Synthèse des Enseignements Clés et Pièges Résolus](#7-synthèse-des-enseignements-clés-et-pièges-résolus)

---

## 1. Vue d'Ensemble & Vision Architecturale

Le projet **DevSecOps Web Lab** est un environnement d'apprentissage et de démonstration technique orienté **SOC Analyst / DevSecOps**. Il implémente une chaîne complète de défense en profondeur, déployée de façon 100% locale, automatisée et reproductible sur Linux (via Podman/Docker rootless).

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                Linux Host (Podman Rootless)                             │
│  ┌──────────────────────────────────────────────────────────────────────────────────┐  │
│  │                     Réseau Isolé Docker : devsecops-net                          │  │
│  │                                                                                  │  │
│  │   ┌────────────────────────┐         ┌───────────────────┐     ┌──────────────┐  │  │
│  │   │     WAF Reverse Proxy  │────────▶│  OWASP Juice Shop │────▶│  MySQL 8.0   │  │  │
│  │   │  Nginx + ModSec 3 + CRS│         │ (App Vulnérable)  │     │ (Durci CIS)  │  │  │
│  │   │      :8080 (Public)    │         │   :3000 (Isolé)   │     │ :3306 (Isolé)│  │  │
│  │   └───────────┬────────────┘         └───────────────────┘     └──────────────┘  │  │
│  │               │ Écrit logs JSON                                                  │  │
│  │               ▼                                                                  │  │
│  │   ┌────────────────────────┐                                                     │  │
│  │   │    Volume : waf-logs   │                                                     │  │
│  │   └───────────┬────────────┘                                                     │  │
│  │               │ Lit /var/log/nginx/access.log                                    │  │
│  │   ┌───────────▼────────────┐         ┌───────────────────┐     ┌──────────────┐  │  │
│  │   │  Promtail (Sidecar WAF)│────────▶│    Grafana Loki   │◀────│   Grafana    │  │  │
│  │   │ (Agent d'ingestion)    │  Push   │ (Agrégateur Logs) │     │ (Dashboard)  │  │  │
│  │   └────────────────────────┘  :3100  │   :3100 (Isolé)   │     │ :3001 (Web)  │  │  │
│  │                                      └───────────────────┘     └──────┬───────┘  │  │
│  └───────────────────────────────────────────────────────────────────────┼──────────┘  │
└──────────────────────────────────────────────────────────────────────────┼─────────────┘
                                                                           │
                  ┌────────────────────────────────────────────────────────┴┐
                  │ Analyste SOC / Utilisateur : Visualisation & Requêtes   │
                  │ Grafana Dashboard (LogQL) & Tests offensifs (cURL)      │
                  └─────────────────────────────────────────────────────────┘
```

### Les 5 Piliers du Laboratoire
1. **Infrastructure as Code (IaC)** avec **Terraform** : instanciation automatique de 5 conteneurs, 1 réseau isolé, et 1 volume nommé.
2. **Configuration Management & Hardening** avec **Ansible** : injection des configurations WAF, conversion des flux de logs en JSON structuré, durcissement de la base de données MySQL 8.0 (selon les standards CIS Benchmark) et déploiement de Promtail.
3. **Sécurité Périmétrique Applicative (WAF)** : Nginx armé de ModSecurity 3 et des 846 règles de l'**OWASP Core Rule Set (CRS)** en mode bloquant strict (`SecRuleEngine On`, `SecDefaultAction deny:403`).
4. **Observabilité & SOC Monitoring** : Chaîne d'ingestion `Nginx JSON -> Promtail -> Loki -> Grafana` pour visualiser en temps réel les volumes d'attaques, les codes HTTP 403 et les endpoints ciblés via des requêtes **LogQL**.
5. **Validation Offensive (Kill Chain)** : Script de simulation d'attaques reproduisant le top des vulnérabilités web (**OWASP Top 10 2025**) : Reconnaissance (A02), Injections SQL (A05), Cross-Site Scripting XSS (A05), Path Traversal (A01), et gestion fine des faux positifs.

---

## 2. Comprendre Terraform : Principes & Exemples Concrets du Projet

### 2.1 Qu'est-ce que Terraform ?
Terraform (édité par HashiCorp) est un outil d'**Infrastructure as Code (IaC)** déclaratif. Contrairement à un script Bash procédural (qui dit *comment* faire étape par étape), Terraform décrit l'**état final souhaité** (*ce que l'infrastructure doit être*).

Terraform s'appuie sur :
- **Des Providers** : des plugins qui dialoguent avec les APIs des plateformes cibles (AWS, Azure, Google Cloud, Docker, Kubernetes, etc.).
- **Des Resources** : les objets d'infrastructure à créer (machines virtuelles, réseaux, conteneurs, disques).
- **Des Variables & Outputs** : pour paramétrer le code et récupérer des valeurs dynamiques (ex: URLs générées).
- **Un State File (`terraform.tfstate`)** : un registre JSON où Terraform enregistre la correspondance exacte entre le code et les ressources réelles déployées.

---

### 2.2 Exemples Concrets Tirés du Projet

#### Exemple 1 : Déclarer le Provider Docker / Podman
Dans `terraform/main.tf` :
```hcl
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = "unix:///run/user/1000/podman/podman.sock"
}
```
**Explication :**
- Le bloc `terraform` impose l'utilisation du provider `kreuzwerker/docker` (le standard communautaire pour piloter Docker en Terraform).
- Le bloc `provider "docker"` spécifie à Terraform comment contacter le moteur de conteneurisation. Ici, on pointe sur le socket UNIX local de Podman en mode utilisateur rootless (`unix:///run/user/1000/podman/podman.sock`). Terraform pilote ainsi Podman de façon transparente exactement comme s'il s'agissait de Docker !

#### Exemple 2 : Isoler le Réseau et Créer un Volume Nommé
Dans `terraform/main.tf` :
```hcl
resource "docker_network" "devsecops_net" {
  name = "devsecops-net"
}

resource "docker_volume" "waf_logs" {
  name = "waf-logs"
}
```
**Explication :**
- `docker_network.devsecops_net` crée un pont réseau isolé. Aucun conteneur rattaché à ce réseau n'est accessible depuis l'extérieur à moins qu'un port ne soit explicitement mappé sur l'hôte.
- `docker_volume.waf_logs` crée un volume Docker/Podman géré par le moteur. **Pourquoi un volume nommé et pas un dossier local (bind mount) ?** Nginx dans le conteneur WAF s'exécute avec l'utilisateur non privilégié `nginx` (UID 101). Si l'on utilisait un dossier local appartenant à l'utilisateur hôte (UID 1000), Nginx planterait immédiatement avec une erreur `13: Permission denied`. Un volume nommé permet au moteur de gérer correctement les permissions.

#### Exemple 3 : Déclarer un Conteneur Sécurisé (Le WAF)
Dans `terraform/main.tf` :
```hcl
resource "docker_container" "waf" {
  name  = "waf"
  image = docker_image.waf.image_id

  networks_advanced {
    name = docker_network.devsecops_net.name
  }

  ports {
    internal = 8080
    external = 8080
  }

  env = [
    "BACKEND=http://juiceshop:3000",
    "MODSEC_RULE_ENGINE=On",
  ]

  volumes {
    volume_name    = docker_volume.waf_logs.name
    container_path = "/var/log/nginx"
  }
}
```
**Explication :**
- `image = docker_image.waf.image_id` : Terraform gère les dépendances implicites. Il télécharge d'abord l'image avant de lancer le conteneur.
- `ports` : On mappe le port externe 8080 sur le port interne 8080. (L'image CRS tourne sur 8080 en interne car un utilisateur non-root ne peut pas écouter sur le port 80 standard).
- `env` : On configure l'application en amont (`http://juiceshop:3000`) et on force le moteur ModSecurity en mode bloquant direct (`MODSEC_RULE_ENGINE=On`).
- `volumes` : On attache le volume de logs partagé.

#### Exemple 4 : Variables Sensibles et Sorties (Outputs)
Dans `terraform/variables.tf` et `terraform/outputs.tf` :
```hcl
# variables.tf
variable "mysql_root_password" {
  type        = string
  description = "Password for MySQL root user"
  sensitive   = true # Masque la valeur dans les logs de la console
}

# outputs.tf
output "waf_url" {
  value = "http://localhost:8080"
}
```
**Explication :**
- `sensitive = true` garantit que Terraform n'affichera jamais le mot de passe en clair lors des commandes `terraform plan` ou `terraform apply`.
- Les `outputs` fournissent directement à l'administrateur ou aux scripts automatisés les URLs d'accès aux services une fois le déploiement terminé.

---

## 3. Comprendre Ansible : Principes & Exemples Concrets du Projet

### 3.1 Qu'est-ce qu'Ansible ?
Ansible (édité par Red Hat) est un outil de **Gestion de Configuration (Configuration Management)** et d'orchestration. Il est **agentless** (il n'a pas besoin d'agent installé à l'avance sur la machine cible ; il se connecte en SSH ou directement via l'API Docker).

Ansible fonctionne selon 4 concepts fondamentaux :
1. **L'Idempotence** : Exécuter un playbook une fois ou dix fois produit exactement le même résultat sans altérer l'état si rien n'a changé (`changed=0`).
2. **L'Inventaire (`inventory.ini`)** : La liste des cibles (serveurs, conteneurs, VMs) organisées par groupes.
3. **Les Playbooks (`*.yml`)** : Les scripts YAML décrivant les tâches à appliquer sur chaque groupe.
4. **Les Handlers** : Des actions déclenchées uniquement si une tâche précédente a provoqué un changement (ex: recharger Nginx seulement si le fichier de configuration a été modifié).

---

### 3.2 Exemples Concrets Tirés du Projet

#### Exemple 1 : Connexion Directe aux Conteneurs sans SSH
Dans `ansible/inventory.ini` :
```ini
[waf_servers]
waf ansible_connection=community.docker.docker

[db_servers]
mysql-db ansible_connection=community.docker.docker

[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_user=root
```
**Explication :**
- Plutôt que d'installer un serveur SSH lourd et risqué dans chaque conteneur, Ansible utilise le connecteur Docker (`community.docker.docker`). Il communique directement via le socket du conteneur (`docker exec / podman exec`).
- On précise l'interpréteur Python cible (`/usr/bin/python3`) et l'utilisateur d'exécution (`root`).

#### Exemple 2 : Le Défi du "Bootstrap" Python (`setup-python.yml`)
Ansible s'appuie en interne sur des modules Python qu'il envoie et exécute sur la cible. Or, les images de conteneurs de sécurité (`owasp/modsecurity-crs` ou `mysql:8.0`) sont minimalistes et **ne contiennent pas Python** !
Dans `ansible/playbooks/setup-python.yml` :
```yaml
- name: Installer Python sur les conteneurs
  hosts: all
  gather_facts: false # INDISPENSABLE : évite d'exécuter le module facts qui requiert Python
  tasks:
    - name: Installer Python3 sur le WAF (Debian)
      raw: apt-get update && apt-get install -y python3
      when: inventory_hostname in groups['waf_servers']

    - name: Installer Python3 sur MySQL (Oracle Linux)
      raw: microdnf install -y python3
      when: inventory_hostname in groups['db_servers']
```
**Explication :**
- `gather_facts: false` empêche Ansible de sonder le conteneur avant que Python ne soit installé.
- Le module `raw` est le seul module d'Ansible qui exécute une commande shell brute sans faire appel à Python sur la machine cible. C'est le "bootstrap" qui rend la machine compatible avec tous les autres modules Ansible.

#### Exemple 3 : Déploiement de Configuration et Handlers Idempotents
Dans `ansible/playbooks/waf-setup.yml` :
```yaml
- name: "WAF | Déployer la config Nginx (reverse proxy + logs JSON)"
  copy:
    src: ../files/waf/nginx.conf
    dest: /etc/nginx/conf.d/default.conf
    mode: '0644'
  notify: Recharger Nginx

handlers:
  - name: Recharger Nginx
    command: nginx -s reload
```
**Explication :**
- Le module `copy` compare le hash du fichier source et du fichier de destination. Si le fichier n'a pas changé, Ansible passe sans rien faire (`ok`).
- Si le fichier a été modifié (`changed`), le mot-clé `notify` active le handler `Recharger Nginx`. Nginx est alors rechargé à chaud sans coupure de service à la fin du playbook.

#### Exemple 4 : Modification Chirurgicale de Fichiers (`lineinfile`)
Dans `ansible/playbooks/waf-setup.yml` :
```yaml
- name: "WAF | Forcer le blocage (deny 403) dans les actions par défaut du CRS"
  lineinfile:
    path: /etc/modsecurity.d/owasp-crs/crs-setup.conf
    regexp: '^SecDefaultAction'
    line: 'SecDefaultAction "phase:{{ item }},log,deny,status:403,tag:''modsecurity''"'
    backup: yes
  loop:
    - "1"
    - "2"
  notify: Recharger Nginx
```
**Explication :**
- `lineinfile` cherche une ligne correspondant à l'expression régulière (`regexp: '^SecDefaultAction'`) et la remplace par la ligne sécurisée (`deny,status:403`).
- `backup: yes` crée automatiquement une copie de sauvegarde du fichier avant modification.
- `loop` itère sur les phases 1 (analyse des en-têtes) et 2 (analyse du corps de requête).

#### Exemple 5 : Durcissement MySQL avec Modules Dédiés
Dans `ansible/playbooks/db-hardening.yml` :
```yaml
- name: "DB | Supprimer les utilisateurs anonymes"
  community.mysql.mysql_user:
    login_user: root
    login_password: "{{ mysql_root_password }}"
    login_unix_socket: /var/run/mysqld/mysqld.sock
    name: ''
    host_all: true
    state: absent

- name: "DB | Restreindre root aux connexions locales uniquement"
  community.mysql.mysql_user:
    login_user: root
    login_password: "{{ mysql_root_password }}"
    login_unix_socket: /var/run/mysqld/mysqld.sock
    name: root
    host: '%'
    state: absent
```
**Explication :**
- Les modules spécialisés comme `community.mysql.mysql_user` garantissent l'état (`state: absent`). Même si on relance le playbook 50 fois, aucun utilisateur anonyme ne sera recréé et aucune erreur ne sera levée.

---

## 4. Synergie Terraform + Ansible : La Séparation des Responsabilités

Une bonne pratique fondamentale en ingénierie DevSecOps consiste à **ne pas mélanger le provisionnement d'infrastructure et la gestion de configuration** :

| Étape | Outil | Responsabilité | Ce qu'il fait dans ce lab |
|---|---|---|---|
| **1. Provisioning** | **Terraform** | Création de la structure / "coquille" | Réseau `devsecops-net`, volume `waf-logs`, instanciation des 5 conteneurs |
| **2. Configuration & Hardening** | **Ansible** | Paramétrage fin et sécurisation interne | Injection des configs Nginx/ModSecurity, installation de Promtail, durcissement MySQL CIS, règles d'exclusion WAF |

```
   [ Code Terraform (.tf) ]
              │
              ▼  (terraform apply)
   ┌─────────────────────────────────────────────────────────────┐
   │ Infrastructure Brute Instanciée                             │
   │ - Conteneurs Up (Images brutes officielles)                 │
   │ - Ports exposés, Volumes & Réseau reliés                    │
   └─────────────────────────────────────────────────────────────┘
              │
              ▼  (ansible-playbook site.yml)
   ┌─────────────────────────────────────────────────────────────┐
   │ Infrastructure Configurée & Durcie                          │
   │ - Python bootstrappé                                        │
   │ - WAF configuré en blocage (403) + logs JSON                │
   │ - Base de données MySQL verrouillée (CIS Benchmark)         │
   │ - Promtail injecté & actif pour envoyer les logs à Loki    │
   └─────────────────────────────────────────────────────────────┘
```

---

## 5. Analyse et Justification Exhaustive Fichier par Fichier

Chaque fichier présent dans le dépôt remplit un rôle technique précis et justifié dans l'architecture globale. Voici l'inventaire complet :

```
devsecops-web-lab/
├── .gitignore
├── LICENSE
├── README.md
├── V2_ROADMAP.md
├── tests.sh
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── grafana_provisioning/
│       ├── datasources/
│       │   └── loki_datasource.yml
│       └── dashboards/
│           ├── dashboard_provider.yml
│           └── security_overview.json
├── ansible/
│   ├── ansible.cfg
│   ├── inventory.ini
│   ├── inventory/
│   │   └── hosts
│   ├── group_vars/
│   │   ├── all/
│   │   │   └── vars.yml
│   │   └── all.yml.vault
│   ├── playbooks/
│   │   ├── site.yml
│   │   ├── setup-python.yml
│   │   ├── waf-setup.yml
│   │   ├── db-hardening.yml
│   │   └── monitoring.yml
│   └── files/
│       ├── waf/
│       │   ├── nginx.conf
│       │   ├── modsec.conf
│       │   └── exclusion_rules.conf
│       └── promtail/
│           └── config.yml
├── attack_simulation/
│   └── simulate_killchain.sh
├── grafana/
│   └── dashboards/
│       └── security-dashboard.json
├── logs/
│   └── .gitignore
└── docs/
    ├── architecture.md
    ├── incident-report.md
    ├── ISSUES.md
    ├── Resources.md
    └── evidences/
        └── *.png (19 captures d'écran de validation)
```

---

### 5.1 Racine du Projet

#### 📄 `.gitignore`
- **Rôle technique** : Spécifie à Git les fichiers et motifs qui ne doivent jamais être commités dans le dépôt (fichiers d'état Terraform `.tfstate`, fichiers de variables secrètes `*.tfvars`, fichiers de coffre-fort Ansible non chiffrés `vault.yml`, fichiers temporaires d'éditeurs `*.swp`, `.DS_Store`).
- **Justification de son existence** : Indispensable pour la sécurité opérationnelle. Il empêche la fuite de secrets (mots de passe root de base de données, clés d'API) et évite de polluer le versionnement avec des fichiers binaires ou des états locaux de Terraform.

#### 📄 `LICENSE`
- **Rôle technique** : Définit les termes légaux de distribution et d'utilisation du code sous la licence **MIT**.
- **Justification de son existence** : Permet de rendre ce projet open-source et réutilisable dans le cadre d'un portfolio professionnel tout en dégageant les auteurs de toute responsabilité liée à des tests de sécurité.

#### 📄 `README.md`
- **Rôle technique** : Point d'entrée principal du projet. Il décrit la stack technique, le schéma architectural, les prérequis, la procédure de déploiement en 3 commandes, la simulation de la kill chain, les requêtes LogQL et la synthèse du troubleshooting.
- **Justification de son existence** : C'est la vitrine du laboratoire pour les recruteurs et pairs techniques. Il permet à quiconque de comprendre le but du projet et de le reproduire en quelques minutes.

#### 📄 `V2_ROADMAP.md`
- **Rôle technique** : Feuille de route d'évolution du lab vers une V2 (intégration d'une machine offensive Kali Linux, règles d'alerting Grafana avec Webhooks Discord/Slack, dashboards d'investigation forensique et formalisation de templates de réponse à incident).
- **Justification de son existence** : Démontre la maturité de la démarche d'ingénierie en fixant des objectifs d'amélioration continue et en structurant les étapes futures de montée en compétences.

#### 📄 `tests.sh`
- **Rôle technique** : Script Bash universel de préparation de la machine hôte. Il détecte automatiquement la distribution Linux et son gestionnaire de paquets (`dnf`, `microdnf`, `apt`, `pacman`), installe Ansible, Terraform, Podman, Nmap, Python3 et SQLMap (via `pipx`), configure et démarre le socket Podman rootless (`systemctl --user enable --now podman.socket`), et teste le bon fonctionnement d'un conteneur témoin.
- **Justification de son existence** : Automatise l'onboarding complet et élimine l'étape fastidieuse de configuration des prérequis système selon l'OS utilisé.

---

### 5.2 Infrastructure as Code — Dossier `terraform/`

#### 📄 `terraform/main.tf`
- **Rôle technique** : Fichier principal d'IaC. Il déclare le provider Docker pointant sur Podman, le réseau isolé `devsecops-net`, le volume nommé `waf-logs`, télécharge les 5 images Docker nécessaires (`owasp/modsecurity-crs:nginx`, `bkimminich/juice-shop`, `mysql:8.0`, `grafana/loki`, `grafana/grafana`) et instancie les 5 conteneurs associés avec leurs variables d'environnement, ports et volumes.
- **Justification de son existence** : Cœur battant du provisionnement. Il garantit que l'infrastructure complète est déployée de manière déterministe et reproductible en une seule commande (`terraform apply`).

#### 📄 `terraform/variables.tf`
- **Rôle technique** : Déclare les variables d'entrée de Terraform (`mysql_root_password`, `grafana_admin_password`) avec leur typage et le drapeau `sensitive = true`.
- **Justification de son existence** : Évite de coder des mots de passe en dur (hardcoding) dans `main.tf` et permet de les injecter via des fichiers `.tfvars` ou des variables d'environnement tout en masquant ces secrets dans la console.

#### 📄 `terraform/outputs.tf`
- **Rôle technique** : Exporte les informations clés après le déploiement (URL publique du WAF `http://localhost:8080`, URL de Grafana `http://localhost:3001`, noms des conteneurs WAF et MySQL).
- **Justification de son existence** : Permet à l'utilisateur ou à des scripts externes de récupérer instantanément les points d'entrée des services déployés sans avoir à inspecter manuellement les conteneurs.

#### 📄 `terraform/grafana_provisioning/datasources/loki_datasource.yml`
- **Rôle technique** : Fichier de configuration déclaratif pour Grafana Provisioning. Il configure automatiquement Loki (`http://loki:3100`) comme source de données par défaut au démarrage de Grafana.
- **Justification de son existence** : Permet le principe de *Monitoring as Code*. L'administrateur n'a pas besoin de configurer manuellement la connexion à la base de logs dans l'interface graphique.

#### 📄 `terraform/grafana_provisioning/dashboards/dashboard_provider.yml`
- **Rôle technique** : Indique au moteur de Grafana où chercher les fichiers JSON de tableaux de bord à charger automatiquement au démarrage (`/etc/grafana/provisioning/dashboards`).
- **Justification de son existence** : Fait le pont entre Grafana et les fichiers JSON de dashboards versionnés dans le dépôt.

#### 📄 `terraform/grafana_provisioning/dashboards/security_overview.json`
- **Rôle technique** : Définition au format JSON du tableau de bord Grafana "Security Overview". Il comprend 3 panels :
  1. *Volume de logs WAF* (courbe temporelle de tout le trafic).
  2. *Requêtes bloquées 403* (courbe temporelle en rouge vif des attaques stoppées).
  3. *Top URIs attaquées* (histogramme horizontal classant les 10 cibles d'attaques les plus fréquentes via `topk()`).
- **Justification de son existence** : Fournit une interface SOC clé en main pré-configurée avec les requêtes LogQL optimales pour visualiser l'activité du WAF dès le lancement du lab.

---

### 5.3 Configuration Management — Dossier `ansible/`

#### 📄 `ansible/ansible.cfg`
- **Rôle technique** : Fichier de configuration du comportement global d'Ansible pour ce projet. Il définit l'inventaire par défaut (`inventory = inventory.ini`), désactive la vérification stricte des clés d'hôte (`host_key_checking = False`), active le formattage lisible de sortie (`stdout_callback = debug`), et surtout configure `remote_tmp = /tmp`.
- **Justification de son existence** : Résout un bug critique avec l'utilisateur `nginx` du conteneur WAF qui n'a pas de dossier personnel (`/nonexistent`) et échouerait sans `remote_tmp = /tmp` (problème répertorié dans `ISSUES.md` #3).

#### 📄 `ansible/inventory.ini`
- **Rôle technique** : Fichier d'inventaire INI. Il déclare les groupes d'hôtes `[waf_servers]`, `[db_servers]`, `[monitoring_servers]` en assignant à chaque conteneur le connecteur Docker direct (`community.docker.docker`), ainsi que les variables globales (`ansible_python_interpreter=/usr/bin/python3`, `ansible_user=root`).
- **Justification de son existence** : Indique à Ansible quelles cibles atteindre et comment s'y connecter sans nécessiter de serveur SSH.

#### 📄 `ansible/inventory/hosts`
- **Rôle technique** : Fichier d'inventaire par défaut alternatif (vide).
- **Justification de son existence** : Conservé pour respecter la structure d'arborescence conventionnelle d'Ansible tout en redirigeant le fonctionnement vers `inventory.ini` spécifié dans `ansible.cfg`.

#### 📄 `ansible/group_vars/all/vars.yml`
- **Rôle technique** : Dictionnaire des variables de configuration non sensibles et variables de pontage vers le coffre-fort (`mysql_database: juiceshop`, `waf_container_name: waf`, `loki_url: http://loki:3100`, `app_user: oracle_user`, `mysql_root_password: "{{ vault_mysql_root_password }}"`).
- **Justification de son existence** : Centralise les paramètres de configuration du projet au même endroit, ce qui facilite la maintenance et la personnalisation sans modifier le code des playbooks.

#### 📄 `ansible/group_vars/all.yml.vault`
- **Rôle technique** : Modèle/espace réservé pour le fichier de variables chiffré par Ansible Vault (`ansible-vault`).
- **Justification de son existence** : Sert de référence pour la structure des variables secrètes chiffrées (`vault_mysql_root_password`, `vault_app_password`) sans exposer les clés en clair sur un dépôt public.

---

### 5.4 Fichiers de Configuration Déployés — `ansible/files/`

#### 📄 `ansible/files/waf/nginx.conf`
- **Rôle technique** : Configuration Nginx pour le WAF. Il définit le format de journalisation structuré JSON `json_combined` (capturant `time`, `remote_addr`, `method`, `uri`, `status`, `body_bytes`, `http_referer`, `http_user_agent`), active le serveur mandataire sur le port 8080, et redirige le trafic vers le backend Juice Shop (`proxy_pass http://juiceshop:3000;`).
- **Justification de son existence** : Permet au WAF de fonctionner comme Reverse Proxy tout en émettant des logs directement au format JSON, ce qui est indispensable pour un parsing ultra-rapide et sans regex par Promtail et Loki.

#### 📄 `ansible/files/waf/modsec.conf`
- **Rôle technique** : Fichier de surcharge pour les paramètres spécifiques de ModSecurity.
- **Justification de son existence** : Prévu pour accueillir des directives bas niveau personnalisées du moteur ModSecurity si nécessaire.

#### 📄 `ansible/files/waf/exclusion_rules.conf`
- **Rôle technique** : Fichier de règles de tuning ModSecurity (gestion des faux positifs). Il contient la directive :
  ```nginx
  SecRuleUpdateTargetById 930110 "!ARGS:q"
  ```
- **Justification de son existence** : Résout un faux positif majeur où la recherche de produits Juice Shop contenant `../` était bloquée par la règle anti-Path-Traversal 930110. Cette exclusion affine la règle sur le paramètre `q` sans abaisser la garde sur le reste du site (voir `ISSUES.md` #12 et Phase 5 de la kill chain).

#### 📄 `ansible/files/promtail/config.yml`
- **Rôle technique** : Fichier de configuration de Promtail. Il configure le serveur local sur le port 9080, définit l'URL de push vers Loki (`http://loki:3100/loki/api/v1/push`), et déclare deux jobs de scraping :
  - `waf_access_logs` (sur `/var/log/nginx/access.log` avec les labels `job: waf`, `container: waf`).
  - `waf_error_logs` (sur `/var/log/nginx/error.log` avec le label `job: waf_errors`).
- **Justification de son existence** : Permet à Promtail de lire en continu les logs Nginx du WAF et de les pousser étiquetés dans la base de logs Loki.

---

### 5.5 Playbooks Ansible — `ansible/playbooks/`

#### 📄 `ansible/playbooks/site.yml`
- **Rôle technique** : Playbook maître (Master Playbook). Il orchestre séquentiellement l'exécution des 4 phases de configuration :
  1. Phase 0 : `setup-python.yml`
  2. Phase 1 : `waf-setup.yml`
  3. Phase 2 : `db-hardening.yml`
  4. Phase 3 : `monitoring.yml`
- **Justification de son existence** : Point d'entrée unique pour la configuration complète du laboratoire (`ansible-playbook ansible/playbooks/site.yml`). Il garantit que les tâches sont exécutées dans le bon ordre logique.

#### 📄 `ansible/playbooks/setup-python.yml`
- **Rôle technique** : Playbook de bootstrap. Il désactive `gather_facts` et utilise le module `raw` pour installer `python3` via `apt-get` sur le conteneur WAF (Debian) et via `microdnf` sur le conteneur MySQL (Oracle Linux).
- **Justification de son existence** : Élimine la dépendance circulaire d'Ansible (qui a besoin de Python sur la cible pour exécuter ses modules).

#### 📄 `ansible/playbooks/waf-setup.yml`
- **Rôle technique** : Déploie `nginx.conf`, active le blocage dans ModSecurity (`SecRuleEngine On`), configure l'action par défaut du CRS en rejet (`SecDefaultAction deny:403`), injecte les règles d'exclusion de faux positifs, remplace les liens symboliques de logs par de vrais fichiers, installe le binaire Promtail et le lance en arrière-plan.
- **Justification de son existence** : Transforme le conteneur Nginx en un véritable WAF actif et connecte la collecte de journaux vers Loki.

#### 📄 `ansible/playbooks/db-hardening.yml`
- **Rôle technique** : Durcissement MySQL 8.0 selon les recommandations CIS Benchmark :
  - Installation de `PyMySQL`.
  - Suppression des utilisateurs anonymes et de la base `test`.
  - Restriction de l'utilisateur `root` à `localhost`.
  - Activation du composant `validate_password` (politique de complexité `MEDIUM`, longueur minimale 12).
  - Verrouillage des options du serveur dans `/etc/my.cnf` (`bind-address = 127.0.0.1`, `local-infile = 0`, `symbolic-links = 0`, etc.).
  - Génération de certificats SSL auto-signés et obligation de connexions chiffrées (`require_secure_transport = ON`).
  - Création d'un utilisateur applicatif `oracle_user` avec le moindre privilège.
  - Audit final des utilisateurs et variables de sécurité.
- **Justification de son existence** : Démontre la mise en œuvre de contrôles stricts de sécurité sur les données (couche stockage et DBMS).

#### 📄 `ansible/playbooks/monitoring.yml`
- **Rôle technique** : Playbook de validation du pipeline d'observabilité. Il vérifie que le processus Promtail tourne (`pgrep`), s'assure que `/var/log/nginx/access.log` existe et se remplit, envoie une requête HTTP test via le WAF, inspecte les dernières lignes JSON générées et teste la disponibilité de l'API de santé de Loki (`http://loki:3100/ready`).
- **Justification de son existence** : Automatise le smoke test de la chaîne de journalisation pour s'assurer que le SOC reçoit bien les événements avant de démarrer les attaques.

---

### 5.6 Simulation Offensive — Dossier `attack_simulation/`

#### 📄 `attack_simulation/simulate_killchain.sh`
- **Rôle technique** : Script Bash de simulation d'attaque automatisée en 5 phases alignées sur le référentiel **OWASP Top 10 2025** :
  - *Phase 1 — Reconnaissance (A02)* : Scan de fichiers et répertoires sensibles (`/admin`, `/phpinfo.php`, `/.git/config`).
  - *Phase 2 — SQL Injection (A05)* : Payloads `OR '1'='1`, `UNION SELECT`, `DROP TABLE`.
  - *Phase 3 — Cross-Site Scripting XSS (A05)* : Payloads `<script>alert('XSS')</script>`, versions encodées.
  - *Phase 4 — Path Traversal (A01)* : Payloads `../../../../etc/passwd`.
  - *Phase 5 — Validation de WAF Tuning* : Test de recherche produit légitime `?q=../juice` démontrant la résolution du faux positif sans régression sur les autres attaques.
- **Justification de son existence** : Fournit une preuve dynamique et concrète de l'efficacité du WAF et génère les flux de données nécessaires pour alimenter les dashboards du SOC.

---

### 5.7 Tableaux de Bord & Observabilité — Dossier `grafana/`

#### 📄 `grafana/dashboards/security-dashboard.json`
- **Rôle technique** : Export JSON complet du tableau de bord Grafana SOC Overview.
- **Justification de son existence** : Permet l'importation manuelle directe via l'UI de Grafana si l'importation automatique par volume est restreinte par Podman rootless (voir `ISSUES.md` #11).

---

### 5.8 Dossier `logs/`

#### 📄 `logs/.gitignore`
- **Rôle technique** : Contient la règle `*.log`.
- **Justification de son existence** : Assure que le dossier `logs/` est conservé dans l'arborescence Git sans que les fichiers journaux générés localement lors des tests ne soient versionnés.

---

### 5.9 Documentation Technique & Preuves — Dossier `docs/`

#### 📄 `docs/architecture.md`
- **Rôle technique** : Documentation technique approfondie de l'architecture avec schéma Mermaid, description détaillée des flux légitimes et bloqués, tableau de correspondance des conteneurs/ports/volumes et pipeline de déploiement.
- **Justification de son existence** : Document de référence pour comprendre la topologie réseau et le modèle de données du laboratoire.

#### 📄 `docs/ISSUES.md`
- **Rôle technique** : Journal de dépannage (Troubleshooting) documentant **12 problèmes réels** rencontrés durant le développement avec analyse de cause racine (Root Cause Analysis - RCA), code erroné vs code corrigé, et enseignements techniques tirés.
- **Justification de son existence** : Pièce maîtresse d'un portfolio technique démontrant les compétences réelles de diagnostic, de compréhension bas niveau (Linux, UID/GID, Nginx, ModSec, MySQL) et de résolution de bugs d'infrastructure.

#### 📄 `docs/incident-report.md`
- **Rôle technique** : Rapport d'incident de sécurité formalisé au standard SOC (synthèse exécutive, timeline d'attaque, requêtes LogQL utilisées, remédiation du faux positif Socket.IO, durcissement DB et recommandations court/moyen/long terme).
- **Justification de son existence** : Démontre la capacité à formaliser un livrable professionnel d'analyse d'incident exploitable par une équipe de sécurité ou un management technique.

#### 📄 `docs/Resources.md`
- **Rôle technique** : Bibliographie exhaustive des ressources officielles, documentations techniques, benchmarks CIS, guides de sécurité MySQL/Nginx/OWASP CRS, matrice des nouveautés OWASP Top 10 2025 et CVEs récentes.
- **Justification de son existence** : Prouve la rigueur méthodologique et l'ancrage du projet dans les standards industriels en vigueur.

#### 📁 `docs/evidences/` (Captures d'écran)
- **Rôle technique** : 19 captures d'écran prouvant l'exécution et la réussite des différentes étapes :
  - `Containers.png` (5 conteneurs Up)
  - `ping-reussi.png` (ping Ansible réussi)
  - `Sqli-bloque.png` & `attaque-bloque-1.png` à `7.png` (requêtes 403 bloquées par le WAF)
  - `pipeline-valide.png`, `queries-presents.png`, `reussite-monitoring.png` (Grafana & Loki fonctionnels)
  - `reussite-site-yml.png` (succès du playbook maître)
  - `ansible-vault.png` (chiffrement des secrets)
- **Justification de son existence** : Fournit les preuves visuelles irréfutables du bon fonctionnement de la stack technique.

---

## 6. Flux Opérationnel Bout en Bout (Cycle de Vie)

Pour appréhender la logique complète du laboratoire, voici la chronologie exacte des opérations :

```
      [ 1. Préparation Système ]
         $ ./tests.sh
         -> Détection OS, installation Terraform, Ansible, Podman, SQLMap, démarrage socket.
                    │
                    ▼
      [ 2. Provisionnement IaC ]
         $ terraform -chdir=terraform apply
         -> Téléchargement des 5 images, création de devsecops-net, volume waf-logs, démarrage conteneurs.
                    │
                    ▼
      [ 3. Configuration & Hardening ]
         $ ansible-playbook ansible/playbooks/site.yml
         -> Phase 0 : Bootstrap Python sur les cibles via module raw.
         -> Phase 1 : WAF Nginx (reverse proxy, logs JSON), ModSec (SecRuleEngine On, deny 403, Promtail).
         -> Phase 2 : MySQL Hardening (anonymes supprimés, root restreint, validate_password, my.cnf, SSL).
         -> Phase 3 : Smoke tests du pipeline de logs.
                    │
                    ▼
      [ 4. Validation Offensive ]
         $ bash attack_simulation/simulate_killchain.sh
         -> Injection de 5 phases d'attaque (OWASP 2025) : blocage 403 et validation tuning faux positif.
                    │
                    ▼
      [ 5. Surveillance & Analyse SOC ]
         Navigateur sur http://localhost:3001 (Grafana)
         -> Requêtes LogQL ({job="waf"} |= "403") et analyse en temps réel sur le tableau de bord.
```

---

## 7. Synthèse des Enseignements Clés et Pièges Résolus

Ce projet met en lumière plusieurs principes incontournables en ingénierie DevSecOps et administration système :

1. **Permissions & Utilisateurs non-root (Bind Mount vs Volume)** :  
   Un conteneur sécurisé n'exécute pas son service en `root`. Pour Nginx (UID 101), l'utilisation d'un *Named Volume* évite les conflits d'UID/GID avec le système de fichiers hôte (`Permission denied`).
2. **Ports Privilégiés vs Ports Hauts** :  
   Un processus non privilégié ne peut pas ouvrir de port inférieur à 1024. Le WAF écoute donc sur le port 8080 en interne, nécessitant un mapping `internal = 8080, external = 8080`.
3. **Le WAF en mode Actif vs Détectif** :  
   Un WAF configuré avec `MODSEC_RULE_ENGINE=DetectionOnly` ou avec `SecDefaultAction pass` n'offre aucune protection. Pour bloquer efficacement les cyberattaques, il est impératif d'aligner `SecRuleEngine On` ET `SecDefaultAction "phase:1,log,deny,status:403"`.
4. **Gestion des Faux Positifs (Tuning)** :  
   Bloquer une attaque ne doit pas empêcher le trafic légitime de fonctionner. L'utilisation de directives ciblées (`SecRuleUpdateTargetById 930110 "!ARGS:q"`) permet d'autoriser des caractères spécifiques sur un endpoint précis sans désactiver la règle pour le reste du serveur.
5. **Observabilité Structurée** :  
   Remplacer les formats de logs bruts par du **JSON structuré** dès la couche Nginx permet aux outils comme Promtail, Loki et Grafana de parser, filtrer et agréger les métriques d'attaque instantanément avec **LogQL**.

---
*Fin du document d'explication. Ce fichier constitue la référence technique complète du DevSecOps Web Lab.*
