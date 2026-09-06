.PHONY: help install

SHELL := /bin/bash
PODMAN ?= podman

.DEFAULT_GOAL := help

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  install   Install required dependencies"
	@echo "  deploy    Deploy the five containers"
	@echo "  help      Shows this help"

install:
	@echo "Installing dependencies..."
	@chmod u+x ./scripts/installs.sh
	@./scripts/installs.sh

# Here I Ensure the provisionning folder is executable ISSUE 11
deploy:
	@echo "Deploying the containers..."
	@chmod -R a+X terraform/grafana/grafana_provisionning
	@terraform init
	@terraform -chdir=terraform apply

