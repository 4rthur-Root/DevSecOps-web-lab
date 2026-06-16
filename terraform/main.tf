# Définition du bloc Terraform
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Provider Docker/Podman
provider "docker" {
  host = "unix:///run/user/1000/podman/podman.sock"
}

# Réseau isolé 
resource "docker_network" "devsecops_net" {
  name = "devsecops-net"
}

# Volume pour les logs WAF
resource "docker_volume" "waf_logs" {
  name = "waf-logs"
}

# Images 
resource "docker_image" "juiceshop" {
  name         = "bkimminich/juice-shop:latest"
  keep_locally = true
}

resource "docker_image" "mysql" {
  name         = "mysql:8.0"
  keep_locally = true
}

resource "docker_image" "waf" {
  name         = "owasp/modsecurity-crs:nginx"
  keep_locally = true
}

resource "docker_image" "loki" {
  name         = "grafana/loki:latest"
  keep_locally = true
}

resource "docker_image" "grafana" {
  name         = "grafana/grafana:latest"
  keep_locally = true
}

# Juice Shop 
resource "docker_container" "juiceshop" {
  name  = "juiceshop"
  image = docker_image.juiceshop.image_id

  networks_advanced {
    name = docker_network.devsecops_net.name
  }

  # Pas exposé directement - uniquement via le WAF
}

# MySQL
resource "docker_container" "mysql" {
  name  = "mysql-db"
  image = docker_image.mysql.image_id

  networks_advanced {
    name = docker_network.devsecops_net.name
  }

  env = [
    "MYSQL_ROOT_PASSWORD=${var.mysql_root_password}",
    "MYSQL_DATABASE=juiceshop",
  ]
}

# WAF (Nginx + ModSecurity + OWASP CRS)
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
    "MODSEC_RULE_ENGINE=DetectionOnly",  # Mode détection d'abord, on activera le blocage via Ansible
  ]

  # Volume pour les logs - Promtail lira ici plus tard
  volumes {
    volume_name    = docker_volume.waf_logs.name
    container_path = "/var/log/nginx"
  }
}

# Loki 
resource "docker_container" "loki" {
  name  = "loki"
  image = docker_image.loki.image_id

  networks_advanced {
    name = docker_network.devsecops_net.name
  }

  ports {
    internal = 3100
    external = 3100
  }
}

# Grafana
resource "docker_container" "grafana" {
  name  = "grafana"
  image = docker_image.grafana.image_id

  networks_advanced {
    name = docker_network.devsecops_net.name
  }

  ports {
    internal = 3000
    external = 3001
  }

  env = [
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
  ]

  # Grafana Provisioning (IaC : datasource + dashboard auto-chargés)
  volumes {
    host_path      = abspath("${path.module}/grafana_provisioning/datasources")
    container_path = "/etc/grafana/provisioning/datasources"
    read_only      = true
  }

  volumes {
    host_path      = abspath("${path.module}/grafana_provisioning/dashboards")
    container_path = "/etc/grafana/provisioning/dashboards"
    read_only      = true
  }
}
