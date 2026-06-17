output "waf_url" {
  value = "http://localhost:8080"
}

output "grafana_url" {
  value = "http://localhost:3001"
}

output "waf_container_name" {
  value = docker_container.waf.name
}

output "mysql_container_name" {
  value = docker_container.mysql.name
}