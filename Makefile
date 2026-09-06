.PHONY: help install deploy configure attack status destroy

SHELL := /bin/bash
PODMAN ?= podman

.DEFAULT_GOAL := help

help:
	@echo "=================================================="
	@echo "     DevSecOps Web Lab - Automation Makefile      "
	@echo "=================================================="
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  install    Install host dependencies and setup Podman socket"
	@echo "  deploy     Provision 6 containers, network, and volumes (Terraform)"
	@echo "  configure  Configure WAF, MySQL Hardening, and verify pipeline (Ansible)"
	@echo "  attack     Run the OWASP Top 10 automated kill chain simulation"
	@echo "  status     Display running lab containers and exposed ports"
	@echo "  destroy    Tear down and clean up all lab containers (Terraform)"
	@echo "  help       Show this help message"
	@echo "=================================================="

install:
	@echo "Installing dependencies..."
	@chmod u+x ./scripts/installs.sh
	@./scripts/installs.sh

# Fix for Issue 11: Ensure Grafana provisioning folders are readable and traversable by UID 472
deploy:
	@echo "Setting Grafana provisioning directory traversal permissions (Issue 11)..."
	@chmod -R a+rX terraform/grafana_provisioning
	@echo "Initializing and deploying infrastructure via Terraform (6 containers)..."
	@terraform -chdir=terraform init
	@terraform -chdir=terraform apply

configure:
	@echo "Applying configuration and hardening via Ansible..."
	@ansible-playbook ansible/playbooks/site.yml

attack:
	@echo "Executing OWASP Top 10 attack simulation..."
	@chmod u+x ./scripts/attacks/simulate_killchain.sh
	@bash ./scripts/attacks/simulate_killchain.sh

status:
	@$(PODMAN) ps --filter "name=waf|juiceshop|mysql-db|alloy|loki|grafana"

destroy:
	@echo "Destroying infrastructure via Terraform..."
	@terraform -chdir=terraform destroy

