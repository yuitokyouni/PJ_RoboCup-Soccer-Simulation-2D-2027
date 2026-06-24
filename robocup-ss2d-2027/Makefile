SHELL := /bin/bash
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := $(ROOT)/scripts

.DEFAULT_GOAL := help

.PHONY: help doctor probe smoke build-baseline clean

help:
	@echo "Phase 1 harness targets:"
	@echo "  make doctor          Check required binaries are installed"
	@echo "  make probe           Inspect installed rcssserver + harness assumptions"
	@echo "  make smoke           Run a single baseline-vs-baseline smoke match"
	@echo "  make build-baseline  (not automated) build librcsc + helios-base; see setup/SETUP.md"
	@echo "  make clean           Remove generated logs (keeps logs/runs/.gitkeep)"

doctor:
	@bash $(SCRIPTS)/doctor.sh

probe:
	@bash $(SCRIPTS)/probe_rcssserver.sh

smoke:
	@bash $(SCRIPTS)/run_smoke_match.sh

build-baseline:
	@echo "build-baseline is not automated yet."
	@echo "See setup/SETUP.md sections 4-5 for librcsc + helios-base build steps."
	@exit 1

clean:
	@find $(ROOT)/logs/runs -mindepth 1 -not -name .gitkeep -exec rm -rf {} +
	@echo "[clean] logs/runs/ wiped (placeholder kept)."
