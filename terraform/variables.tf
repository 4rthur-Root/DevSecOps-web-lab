variable "mysql_root_password" {
  type        = string
  description = "Password for MySQL root user"
  sensitive   = true
}

variable "grafana_admin_password" {
  type        = string
  description = "Password for Grafana admin user"
  sensitive   = true
}