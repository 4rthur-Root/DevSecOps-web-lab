.PHONY: help install

SHELL := /bin/bash
PODMAN ?= podman

.DEFAULT_GOAL := help

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
    @echo "  install - Install dependencies"
	@echo "  help - Shows this help"
	
install:
    @echo "Installing dependencies..."
	@chmod u+x ./scripts/installs.sh
	@./scripts/installs.sh
