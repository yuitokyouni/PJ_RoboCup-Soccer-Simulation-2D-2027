SHELL := /bin/bash
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := $(ROOT)/scripts
EVAL := $(ROOT)/evaluation

.DEFAULT_GOAL := help

.PHONY: help doctor probe smoke batch aggregate build-baseline clean

help:
	@echo "Phase 1 harness targets:"
	@echo "  make doctor          Check required binaries are installed"
	@echo "  make probe           Inspect installed rcssserver + harness assumptions"
	@echo "  make smoke           Run a single baseline-vs-baseline smoke match"
	@echo "  make build-baseline  (not automated) build librcsc + helios-base; see setup/SETUP.md"
	@echo "  make clean           Remove generated logs (keeps logs/runs/.gitkeep)"
	@echo "Phase 2 batch evaluation:"
	@echo "  make batch           Run an N-match experiment; requires EXPERIMENT=path/to.yaml"
	@echo "                       (optional: NUM_MATCHES, TIMEOUT, FORCE=1, DRY_RUN=1)"
	@echo "  make aggregate       Re-aggregate summary.csv/summary.json for EXPERIMENT_DIR"

doctor:
	@bash $(SCRIPTS)/doctor.sh

probe:
	@bash $(SCRIPTS)/probe_rcssserver.sh

smoke:
	@bash $(SCRIPTS)/run_smoke_match.sh

aggregate:
	@if [[ -z "$(EXPERIMENT_DIR)" ]]; then \
	  echo "EXPERIMENT_DIR is required, e.g. make aggregate EXPERIMENT_DIR=logs/experiments/<id>" >&2; \
	  exit 2; \
	fi
	@python3 $(EVAL)/aggregate_results.py --experiment-dir "$(EXPERIMENT_DIR)"

build-baseline:
	@echo "build-baseline is not automated yet."
	@echo "See setup/SETUP.md sections 4-5 for librcsc + helios-base build steps."
	@exit 1

clean:
	@find $(ROOT)/logs/runs -mindepth 1 -not -name .gitkeep -exec rm -rf {} +
	@echo "[clean] logs/runs/ wiped (placeholder kept)."
