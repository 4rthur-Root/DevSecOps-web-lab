# Problèmes Rencontrés & Résolutions (Troubleshooting)

Ce document retrace les erreurs majeures rencontrées durant le déploiement et détaille la démarche de résolution (Root Cause Analysis). 

---

## 1. WAF : Nginx "Permission denied" sur les logs

### Le problème exact
Lors du déploiement initial via Terraform, le conteneur WAF (`owasp/modsecurity-crs:nginx`) refusait de démarrer ou redémarrait en boucle.
L'analyse des logs du conteneur (`podman logs waf`) affichait l'erreur critique suivante :
`nginx: [emerg] 1#1: open() "/var/log/nginx/access.log" failed (13: Permission denied)`

### Comment le problème a été identifié
L'erreur `Permission denied` sur un fichier de log est le symptôme absolu d'un conflit de droits entre le système de fichiers de l'hôte Linux et l'utilisateur interne du conteneur.
En analysant le code `main.tf`, nous avions utilisé un **Bind Mount** (montage direct d'un dossier de l'hôte) :
```hcl
  volumes {
    host_path      = abspath("${path.module}/../logs/waf")
    container_path = "/var/log/nginx"
  }
```
L'image officielle ModSecurity CRS applique les bonnes pratiques de sécurité : elle exécute le processus Nginx avec un utilisateur non privilégié (l'utilisateur `nginx`, UID 101) au lieu de l'utilisateur `root`.
Cependant, le dossier local `../logs/waf` sur la machine hôte était la propriété de l'utilisateur courant (UID 1000). Lorsque Nginx (UID 101) a tenté d'écrire dedans, le système de fichiers Linux a bloqué l'action.

### La Solution
Nous avons remplacé le *Bind Mount* par un **Volume Docker nommé**.
Dans Terraform, nous avons déclaré la ressource `docker_volume` et modifié le bloc `volumes` du conteneur :
```hcl
resource "docker_volume" "waf_logs" {
  name = "waf-logs"
}
# ...
  volumes {
    volume_name    = docker_volume.waf_logs.name
    container_path = "/var/log/nginx"
  }
```

### Pourquoi cette solution et ce qu'il faut en retenir
Un Volume Nommé est géré intégralement par le démon Docker/Podman, stocké dans un espace système dédié (souvent dans `/var/lib/docker/volumes` ou équivalent Podman). Lors de l'initialisation du conteneur, le moteur ajuste automatiquement les permissions pour s'assurer que l'utilisateur interne puisse y écrire. C'est l'approche "DevOps" de référence pour persister des données sans se heurter aux problèmes de droits liés à l'hôte.

### Et avec Docker natif ?
Si nous avions utilisé Docker (en mode daemon root) au lieu de Podman, **le problème aurait été similaire, bien que parfois masqué**.
Sur un système purement Linux, l'erreur aurait été exactement la même car l'UID 101 reste l'UID 101. En revanche, si on avait utilisé Docker Desktop (sous Windows ou macOS), la machine virtuelle intermédiaire (WSL2 ou HyperKit) ajuste souvent dynamiquement les permissions des *Bind Mounts* à la volée. Cela pardonne les erreurs et donne une fausse sensation de sécurité, mais le code échouerait brutalement une fois déployé sur un vrai serveur Linux de production ! Le fait d'être sous Linux/Podman t'a forcé à adopter la solution robuste dès le premier jour.

---

## 2. WAF : Connection reset by peer (Erreur 56 curl)

### Le problème exact
Une fois le problème de permissions résolu, le WAF était bien au statut `Up`. Toutefois, toute tentative de s'y connecter (`curl -s -i http://localhost:8080`) échouait avec une erreur réseau :
`curl: (56) Recv failure: Connection reset by peer`

### Comment le problème a été identifié
Un *Connection Reset* (paquet TCP RST) provenant de l'hôte local vers un conteneur signifie que le moteur Docker a bien intercepté le trafic entrant sur le port exposé, l'a transféré à l'intérieur du réseau du conteneur, mais qu'**aucun processus applicatif n'écoutait de l'autre côté**. Le système d'exploitation du conteneur ferme alors violemment la connexion.
L'analyse du `main.tf` a révélé le problème dans le mappage de ports :
```hcl
  ports {
    internal = 80
    external = 8080
  }
```
Souviens-toi de notre analyse précédente : l'image s'exécute avec un utilisateur non-root. Sous Linux, un utilisateur non-root ne peut pas ouvrir de port inférieur à 1024 (il n'a pas la capability `CAP_NET_BIND_SERVICE`). Les développeurs de l'image CRS ont donc configuré Nginx pour écouter par défaut sur le port HTTP **8080** en interne, et non 80.
Notre trafic externe arrivait donc sur le port interne 80, qui était désert !

### La Solution
Nous avons corrigé le mappage pour s'aligner sur la configuration interne de l'image CRS :
```hcl
  ports {
    internal = 8080
    external = 8080
  }
```

### Pourquoi cette solution et ce qu'il faut en retenir
Il est primordial de toujours faire la distinction entre le port **externe** (celui exposé au monde / à ton navigateur) et le port **interne** (celui défini dans le `Dockerfile` de l'image via l'instruction `EXPOSE` ou la configuration logicielle).
Règle d'or en sécurité : les conteneurs "Hardened" ou "Rootless" utiliseront systématiquement des ports élevés (8080, 8443) pour contourner la restriction des ports privilégiés.

### Et avec Docker natif ?
Le comportement aurait été **strictement identique** avec n'importe quelle version de Docker. Le transfert de port est une mécanique réseau universelle des conteneurs. Si on redirige du trafic vers un port où rien ne tourne, un `Connection reset` est le comportement standard d'une pile TCP/IP saine.


### État final après résolution
- Volume nommé `waf-logs` géré par Podman
- Port mapping corrigé : `internal = 8080, external = 8080`
- Validation : `curl -s http://localhost:8080 | grep -i "juice"` ✅
- `podman ps` : 5 containers Up ✅



![Running Containers](./evidences/Containers.png)

---

## 3. Ansible : Impossible de se connecter et d'exécuter des modules sur les conteneurs

### Le problème exact
Lors des premiers tests de connexion d'Ansible vers les conteneurs cibles (`ansible all -m ping`), deux erreurs majeures sont apparues :
1. Sur le WAF (`owasp/modsecurity-crs:nginx`) : `Failed to create temporary directory [...] echo /nonexistent/.ansible/tmp`
2. Sur MySQL et WAF : `The module interpreter '/usr/bin/python3' was not found`

### Comment le problème a été identifié
- **Pour le répertoire temporaire (WAF)** : Par défaut, l'utilisateur `nginx` exécutant le conteneur n'a pas de véritable répertoire personnel (`/nonexistent`). Lorsque Ansible tente de créer son dossier de travail temporaire `~/.ansible/tmp`, le système refuse l'accès.
- **Pour l'interpréteur Python (WAF & MySQL)** : Ansible repose intrinsèquement sur l'envoi et l'exécution de scripts Python sur les machines cibles pour faire fonctionner ses modules standards (`ping`, `copy`, `mysql_db`, etc.). Or, les images Docker officielles telles que `mysql:8.0` et `owasp/modsecurity-crs:nginx` sont volontairement allégées pour des raisons de sécurité (réduction de la surface d'attaque) et ne contiennent donc pas Python par défaut.

### Les Solutions Déployées

#### 1. Correction du répertoire temporaire
Nous avons instruit Ansible d'utiliser le répertoire temporaire global `/tmp` (qui est accessible en écriture par tous) au lieu du répertoire personnel de l'utilisateur.
- **Action** : Ajout de la variable `remote_tmp = /tmp` dans la section `[defaults]` du fichier `ansible.cfg`.

#### 2. Installation de Python via le module `raw` (Bootstrap)
Pour installer Python sans utiliser les modules nécessitant... Python (comme le module `apt`), nous avons rédigé un playbook "Bootstrap" (`setup-python.yml`).
- Ce playbook désactive la collecte initiale de variables (`gather_facts: no`).
- Il utilise le seul module natif qui ne nécessite pas Python sur la cible : le module `raw`. Ce module envoie des commandes Bash brutes via le connecteur Docker.
- **Action** : Installation de `python3` via `apt-get` (sur le WAF basé Debian) et via `microdnf` (sur la BDD basée Oracle Linux), en forçant la connexion sous l'utilisateur root (`ansible_user=root` dans l'inventaire).

### Autres approches envisageables (Architecturales)
L'approche de bootstrap via `raw` est pratique, mais dans une approche GitOps/DevSecOps stricte, d'autres alternatives existent :
- **L'approche "Custom Dockerfile" (La plus recommandée en production)** : Au lieu de tirer les images brutes dans `main.tf`, nous aurions pu créer un `Dockerfile` qui hérite des images officielles et ajoute l'instruction `RUN apt-get update && apt-get install -y python3`. Terraform aurait alors provisionné ces nouvelles images "Ansible-Ready". (Note : cela aurait nécessité un `terraform apply` pour détruire et recréer les conteneurs).
- **L'approche "Local Connection"** : Utiliser la connexion `local` dans Ansible avec le module `community.docker.docker_container_exec` pour exécuter des commandes depuis la machine hôte vers les conteneurs, évitant ainsi le besoin de Python à l'intérieur. Mais cela s'éloigne de l'expérience classique d'Ansible.

### Ce qu'il faut en retenir
Une architecture 100% conteneurisée révèle rapidement les prérequis cachés des outils de Configuration Management. Ansible n'est pas "magique" : il a besoin d'un environnement d'exécution (Python) sur ses cibles. Comprendre la différence entre un système Linux complet (VM) et un conteneur allégé est essentiel pour tout ingénieur DevOps/SecOps.

![Pings réussis](./evidences/ping-reussi.png)

## 4. WAF | Playbook : Erreur de syntaxe Nginx dans `nginx.conf` — `invalid number of arguments in proxy_pass`

### Le problème exact
Après le premier `ansible-playbook waf-setup.yml`, le handler `Recharger Nginx` déclenchait une erreur fatale empêchant la config d'être prise en compte :
```
nginx: [emerg] invalid number of arguments in "proxy_pass" directive in /etc/nginx/conf.d/default.conf:25
```

### Comment le problème a été identifié
La commande `nginx -T` (test de configuration) a permis d'isoler la ligne en cause. En l'inspectant dans `ansible/files/waf/nginx.conf`, la directive `proxy_pass` contenait un backslash parasite avant le point-virgule de fin de ligne :
```nginx
# FAUX (généré par l'éditeur de texte)
proxy_pass http://juiceshop:3000\;

# CORRECT
proxy_pass http://juiceshop:3000;
```
Le backslash `\` est un caractère d'échappement valide dans certains langages (shell, Python), mais **il n'a aucune signification en syntaxe Nginx** et est donc traité comme un caractère illégitime supplémentaire, transformant la directive en une instruction avec "trop d'arguments".

### La Solution
Suppression du backslash parasite dans `ansible/files/waf/nginx.conf`.

### Ce qu'il faut en retenir
En Nginx, le point-virgule `;` est le terminateur de directive. Il ne doit jamais être échappé. Ce type de bug est classique lors d'une écriture de config dans un éditeur de code qui confond les contextes de langage.

---

## 5. WAF | Playbook : Variable Nginx `$modsec_inbound_anomaly_score` inconnue

### Le problème exact
Même après correction de la syntaxe `proxy_pass`, le reload Nginx échouait avec :
```
nginx: [emerg] unknown "modsec_inbound_anomaly_score" variable
```

### Comment le problème a été identifié
Le `log_format` JSON défini dans `nginx.conf` référençait deux variables ModSecurity : `$modsec_inbound_anomaly_score` et `$matched_var`. Ces variables sont injectées dans Nginx via le module dynamique `ngx_http_modsecurity_module`. Lorsque ce module n'est pas chargé **avant** l'évaluation du bloc `http`, ou que les variables n'ont pas encore été déclarées, Nginx refuse de démarrer.
L'image `owasp/modsecurity-crs:nginx` charge bien ModSecurity, mais le connecteur ne garantit pas l'exposition de toutes les variables internes de ModSecurity dans l'espace de variables Nginx standard.

### La Solution
Suppression des deux variables problématiques du `log_format` dans `nginx.conf`. Le log JSON conserve les champs essentiels pour l'analyse Grafana/Loki :
- `time`, `remote_addr`, `method`, `uri`, `status`, `body_bytes`, `http_referer`, `http_user_agent`

### Ce qu'il faut en retenir
Pour enrichir les logs avec le score ModSecurity (une vraie valeur ajoutée pour un dashboard SOC), il faut utiliser le **log d'audit ModSecurity** (`/var/log/modsec_audit.log`), qui est un fichier séparé géré par le moteur ModSecurity lui-même. On pourra configurer Promtail pour l'aspirer en Phase 3.

---

## 6. WAF | Playbook : `pkill`, `ps`, `pgrep` introuvables dans l'image

### Le problème exact
Toutes les commandes d'inspection ou d'arrêt de processus échouaient dans le conteneur WAF :
```
Error: crun: executable file `pgrep` not found in $PATH: No such file or directory
Error: crun: executable file `ps` not found in $PATH: No such file or directory
```
Concrètement, la tâche Ansible `pkill promtail || true` aurait silencieusement échoué sur le `pkill` sans le `|| true`, et les vérifications manuelles étaient impossibles.

### Comment le problème a été identifié
L'image Debian minimale (`owasp/modsecurity-crs:nginx`) n'installe que le strict nécessaire pour faire tourner Nginx. Les utilitaires `ps`, `pgrep` et `pkill` font partie du paquet `procps` qui n'est pas inclus.

### La Solution
Ajout du paquet `procps` dans la liste des dépendances installées par le playbook `waf-setup.yml`, en parallèle de `unzip` :
```yaml
- name: Télécharger "unzip" et "procps" (pour pkill)
  package:
    name:
      - unzip
      - procps
    state: present
```

### Ce qu'il faut en retenir
Regrouper les installations de dépendances systèmes dans une seule tâche `package` avec une liste est une bonne pratique Ansible (une seule transaction apt, idempotent, plus lisible).

---

## 7. WAF | Playbook : Logs Nginx symlinkés vers `/dev/stdout` — Promtail ne peut pas les lire

### Le problème exact
Pendant les tests de validation, la commande `podman exec waf cat /var/log/nginx/access.log` bloquait indéfiniment et ne retournait rien. L'inspection du répertoire révélait :
```bash
podman exec waf ls -la /var/log/nginx/
# lrwxrwxrwx. root root 11 May 19  access.log -> /dev/stdout
# lrwxrwxrwx. root root 11 May 19  error.log -> /dev/stderr
```
Promtail essayait de « lire » un fichier qui n'était qu'un lien symbolique vers la sortie standard du conteneur — un pseudo-fichier en écriture seule. Il ne pouvait donc jamais envoyer un seul log vers Loki.

### Comment le problème a été identifié
C'est une convention Docker très répandue : par défaut, les images redirigent les logs applicatifs vers `stdout/stderr` pour que le démon Docker (ou Podman) les collecte via `docker logs`. C'est un excellent réflexe pour un déploiement classique, mais c'est **incompatible avec un agent de collecte de fichiers** comme Promtail, qui a besoin de vrais fichiers à « tail ».

### La Solution
Ajout d'une tâche Ansible exécutée avant le lancement de Promtail pour substituer les symlinks par de vrais fichiers vides :
```yaml
- name: "WAF | Remplacer les symlinks de logs Nginx par de vrais fichiers (pour Promtail)"
  shell: |
    if [ -L /var/log/nginx/access.log ]; then rm /var/log/nginx/access.log && touch /var/log/nginx/access.log; fi
    if [ -L /var/log/nginx/error.log ]; then rm /var/log/nginx/error.log && touch /var/log/nginx/error.log; fi
    chown nginx:adm /var/log/nginx/access.log /var/log/nginx/error.log
  changed_when: false
```

### Ce qu'il faut en retenir
Lors du déploiement d'une stack observabilité (Promtail, Filebeat, Fluentd…) sur des conteneurs Docker, **toujours vérifier si les logs sont de vrais fichiers ou des symlinks vers stdout/stderr**. C'est un piège quasi-systématique avec les images officielles.

### État final après résolution de toutes les erreurs WAF (Phase 2)
- Nginx se recharge correctement sans erreur de syntaxe ✅
- Config JSON active, les requêtes génèrent des logs structurés ✅
- `pgrep` et `pkill` disponibles dans le conteneur ✅
- Logs dans de vrais fichiers, lisibles par Promtail ✅

**Validation :**
```bash
# Requête test à travers le WAF
curl -s http://localhost:8080/rest/products/search\?q\=test
# → Réponse JSON de Juice Shop ✅

# Log JSON généré
podman exec waf cat /var/log/nginx/access.log | tail -1
# → {"time":"2026-06-17T07:15:57+00:00","remote_addr":"10.89.2.3","method":"GET","uri":"/rest/products/search?q=test","status":200,...}

# Promtail actif
podman exec waf pgrep -a promtail
# → 2246 /usr/local/bin/promtail -config.file=/etc/promtail-config.yml ✅
```

---

## 8. DB | Playbook : Mot de passe MySQL incorrect dans le vault — `Access denied for user 'root'`

### Le problème exact
Lors de la première exécution du playbook `db-hardening.yml`, la tâche de suppression des utilisateurs anonymes échouait immédiatement :
```
fatal: [mysql-db]: FAILED! => {}
MSG: unable to connect to database, check login_user and login_password are correct
Exception message: (1045, "Access denied for user 'root'@'localhost' (using password: YES)")
```

### Comment le problème a été identifié
Le vault Ansible (`group_vars/all/vault.yml`) avait été initialisé avec un mot de passe de test (`SOCops@#`) au lieu du vrai mot de passe utilisé lors de la création du conteneur MySQL par Terraform.

Le mot de passe réel a été retrouvé grâce à la commande d'inspection du conteneur :
```bash
podman inspect mysql-db | grep -A 5 "Env"
# → "MYSQL_ROOT_PASSWORD=My_@password"
```
Cette commande liste toutes les variables d'environnement du conteneur, y compris le mot de passe root passé par Terraform via la variable `MYSQL_ROOT_PASSWORD`.

### La Solution
Modification du fichier `vault.yml` (via `ansible-vault edit`) pour aligner `mysql_root_password` avec la valeur réellement passée à Terraform dans `terraform.tfvars`.

### Ce qu'il faut en retenir
Les secrets Terraform et les secrets Ansible sont deux systèmes distincts. **Il faut s'assurer dès le départ que la même valeur de mot de passe est déclarée dans les deux endroits**, ou mieux, n'en avoir qu'une seule source de vérité (voir entry #10 pour les approches alternatives).

---

## 9. DB | Playbook : Plugin `audit_log` absent — MySQL Community Edition

### Le problème exact
La tâche d'installation du plugin d'audit échouait avec une erreur de bibliothèque partagée introuvable :
```
Cannot execute SQL 'INSTALL PLUGIN audit_log SONAME 'audit_log.so';' args [None]:
(1126, "Can't open shared library '/usr/lib64/mysql/plugin/audit_log.so'
(errno: 0 [...]: No such file or directory)")
```

### Comment le problème a été identifié
Le plugin `audit_log` (sous forme de fichier `.so`) est une fonctionnalité **exclusive à MySQL Enterprise Edition**. L'image Docker utilisée (`mysql:8.0`) est la version **Community Edition** distribuée sous licence GPL, qui ne l'inclut pas.

**Alternatives existantes pour l'audit dans MySQL Community :**
| Méthode | Description | Inconvénient |
|---|---|---|
| `audit_log.so` | Plugin natif, logs JSON/XML structurés | **Enterprise uniquement** |
| `general_log` | Log de toutes les requêtes SQL | **Extrêmement verbeux**, impact performance sévère, non recommandé en prod |
| **`component_validate_password`** | Composant de validation de mot de passe (installé dans ce projet) | Validation seulement, pas d'audit |
| **MariaDB Audit Plugin** | Plugin open-source, fonctionne avec certaines versions MySQL | Compatibilité non garantie avec MySQL 8.0 |

`general_log` a été mentionné comme option mais volontairement écarté en raison de sa verbosité excessive et de l'impact sur les performances.

### La Solution
La tâche d'installation du plugin `audit_log` et les tâches de configuration associées (`audit_log_policy`, `audit_log_format`) ont été **conservées dans le playbook mais gérées de manière non bloquante** via `failed_when`. La stratégie d'audit adoptée s'appuie sur :
- La journalisation des erreurs MySQL (`log_error = /var/log/mysql/error.log`)
- Le composant `validate_password` pour renforcer la politique de mots de passe
- Les logs du WAF (Nginx + ModSecurity) pour tracer les tentatives d'attaque au niveau applicatif

### Ce qu'il faut en retenir
Toujours vérifier la matrice de fonctionnalités Community vs Enterprise d'un SGBD avant de planifier des contrôles de sécurité. Pour un projet de portfolio, le choix conscient et documenté d'une alternative vaut autant qu'une implémentation parfaite.

---

## 10. 🔐 Réflexion Sécurité : Secrets exposés via `podman inspect`

### Le constat
La commande `podman inspect mysql-db | grep Env` a permis de retrouver le mot de passe root MySQL **en clair** dans la sortie :
```json
"Env": [
  "MYSQL_ROOT_PASSWORD=My_@password",
  ...
]
```
Ce comportement est le comportement par défaut de Docker/Podman : les variables d'environnement passées à un conteneur sont stockées dans ses métadonnées et accessibles à tout utilisateur ayant accès au socket Docker/Podman (c'est-à-dire, par défaut, tout membre du groupe `docker` ou tout utilisateur rootless sur sa propre session).

### Pourquoi c'est une vraie menace
Dans un environnement partagé (serveur de CI/CD, machine de dev mutualisée), n'importe quel utilisateur ayant accès aux commandes Podman/Docker peut exfiltrer l'ensemble des secrets de tous les conteneurs en quelques secondes. C'est une surface d'attaque critique en post-exploitation.

### Politiques de sécurité qui auraient pu être appliquées

#### 1. Ne jamais passer de secrets via des variables d'environnement
Utiliser des **fichiers de secrets montés** en volume, qui ne sont pas exposés par `inspect` :
```hcl
# Dans main.tf : monter un fichier de secrets au lieu de passer une env var
volumes {
  host_path      = "/run/secrets/mysql_root_password"
  container_path = "/run/secrets/mysql_root_password"
  read_only      = true
}
```

#### 2. Docker/Podman Secrets (mode Swarm ou Podman Secrets)
Podman dispose d'un mécanisme natif de secrets qui monte le secret en tant que fichier en mémoire (`tmpfs`) et ne l'expose pas via `inspect` :
```bash
# Créer le secret
echo "My_@password" | podman secret create mysql_root_password -

# Référencer dans le conteneur (via --secret, pas --env)
podman run --secret mysql_root_password,type=env,target=MYSQL_ROOT_PASSWORD mysql:8.0
```

#### 3. HashiCorp Vault (approche Enterprise)
Intégrer un gestionnaire de secrets dédié (Vault) qui délivre les credentials dynamiquement au moment du démarrage du conteneur, sans jamais les stocker dans les métadonnées.

#### 4. Limiter l'accès au socket Podman/Docker
Appliquer le principe du moindre privilège : seuls les utilisateurs/processus strictement nécessaires doivent pouvoir exécuter des commandes `podman inspect`.

### État actuel dans ce projet
Le mot de passe est géré via **Ansible Vault** (`vault.yml`) pour la partie configuration, ce qui est correct. La faiblesse réside côté Terraform : le mot de passe est passé via une variable d'environnement Docker. Pour un projet de portfolio, ce niveau est acceptable et documenté. Pour une mise en production réelle, les approches 1 ou 2 ci-dessus seraient obligatoires.


## 11. Grafana : Provisioning automatique échoue (Permission denied)

### Problème
Le dossier `/etc/grafana/provisioning/datasources/` est inaccessible 
en lecture depuis le container Grafana avec Podman rootless.

### Solution de contournement
Configuration manuelle de la datasource Loki via l'UI Grafana 
(URL: http://loki:3100). La datasource est persistée dans le 
volume Grafana interne.

### Impact
Mineur — la datasource est configurée et fonctionnelle. 
Le fichier `loki_datasource.yml` reste dans le repo à titre 
documentaire mais n'est pas chargé automatiquement avec Podman rootless.
