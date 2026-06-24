SHELL := /bin/bash
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := $(ROOT)/scripts
EVAL := $(ROOT)/evaluation

.DEFAULT_GOAL := help

.PHONY: help doctor probe smoke batch aggregate fetch-externals build-externals build-baseline clean

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
	@echo "Phase 2.5 real integration:"
	@echo "  make fetch-externals Clone rcssserver/librcsc/helios-base/cyrus2dbase into externals/src/"
	@echo "                       (optional: FORCE=1, FULL=1, ONLY=name)"
	@echo "  make build-externals Build the fetched externals into externals/install/"
	@echo "                       (optional: ONLY=name, JOBS=N)"

doctor:
	@bash $(SCRIPTS)/doctor.sh

probe:
	@bash $(SCRIPTS)/probe_rcssserver.sh

smoke:
	@bash $(SCRIPTS)/run_smoke_match.sh

batch:
	@if [[ -z "$(EXPERIMENT)" ]]; then \
	  echo "EXPERIMENT is required, e.g. make batch EXPERIMENT=experiments/baseline_vs_baseline.yaml" >&2; \
	  exit 2; \
	fi
	@bash $(SCRIPTS)/run_batch_matches.sh \
	  --experiment "$(EXPERIMENT)" \
	  $(if $(NUM_MATCHES),--num-matches $(NUM_MATCHES)) \
	  $(if $(TIMEOUT),--timeout $(TIMEOUT)) \
	  $(if $(FORCE),--force) \
	  $(if $(DRY_RUN),--dry-run)

aggregate:
	@if [[ -z "$(EXPERIMENT_DIR)" ]]; then \
	  echo "EXPERIMENT_DIR is required, e.g. make aggregate EXPERIMENT_DIR=logs/experiments/<id>" >&2; \
	  exit 2; \
	fi
	@python3 $(EVAL)/aggregate_results.py --experiment-dir "$(EXPERIMENT_DIR)"

fetch-externals:
	@bash $(SCRIPTS)/fetch_externals.sh \
	  $(if $(FORCE),--force) \
	  $(if $(FULL),--full) \
	  $(if $(ONLY),--only $(ONLY))

build-externals:
	@bash $(SCRIPTS)/build_externals.sh \
	  $(if $(ONLY),--only $(ONLY)) \
	  $(if $(JOBS),--jobs $(JOBS))

build-baseline:
	@echo "build-baseline is not automated yet."
	@echo "See setup/SETUP.md sections 4-5 for librcsc + helios-base build steps,"
	@echo "or run: make fetch-externals && make build-externals (Phase 2.5)."
	@exit 1

clean:
	@find $(ROOT)/logs/runs -mindepth 1 -not -name .gitkeep -exec rm -rf {} +
	@echo "[clean] logs/runs/ wiped (placeholder kept)."
