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
