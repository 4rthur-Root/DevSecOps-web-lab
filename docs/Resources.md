# DevOps Security Lab - Ressources & Références

## 🔗 Ressources d'Inspiration

Ces ressources ont guidé les choix de configuration du playbook :

- [OWASP Juice Shop](https://hub.docker.com/r/bkimminich/juice-shop) - Application vulnérable pour tests de sécurité
- [Grafana Loki](https://grafana.com/oss/loki/) - Système de logging et monitoring
- [Database Hardening - Guide Medium](https://medium.com/@abhijitgm5/database-hardening-for-mysql-postgresql-oracle-mongodb-6f661b7ccd7c) - Hardening comparatif des bases de données
- [Oracle MySQL Security Guide](https://docs.oracle.com/en/database/oracle/mysql/8.0/security.html) - Guide de sécurité Oracle MySQL

---

## 🛡️ MySQL Database Hardening Playbook

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

| CVE | Version concernée | Impact |
|-----|-------------------|--------|
| [CVE-2025-53053](https://vuldb.com/vuln/329177) | MySQL 8.0.0-8.0.43, 8.4.0-8.4.6 | Impropre autorisation dans le composant DML - Accès non autorisé et déni de service |
| CVE-2025-50104 | MySQL 8.0.0-8.0.42, 8.4.0-8.4.5 | Déni de service dans le composant DDL |

> **Enseignement** : Ces vulnérabilités récentes (2025) démontrent l'importance de maintenir une base de données durcie et à jour, car même des composants critiques comme DML et DDL peuvent être exploités pour des accès non autorisés ou des dénis de service.

---

## 🎯 Conclusion

Ce playbook implémente un hardening de niveau production avec :

- ✅ Politique de mots de passe forte
- ✅ Configuration sécurisée du serveur
- ✅ Chiffrement SSL/TLS des communications
- ✅ Moindre privilège pour l'utilisateur applicatif
- ✅ Audit logging pour la traçabilité
- ✅ Vérifications automatiques post-durcissement

> Pour une sécurité maximale, combinez ce durcissement avec une mise à jour régulière de MySQL (les CVE citées sont corrigées dans les versions ultérieures) et une surveillance active des logs.