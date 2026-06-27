SHELL := /bin/bash
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS := $(ROOT)/scripts
EVAL := $(ROOT)/evaluation

.DEFAULT_GOAL := help

.PHONY: help doctor probe smoke batch aggregate fetch-externals build-externals real-smoke build-baseline clean test

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
	@echo "  make compare         Compare two summary.json files; refuses strong claims under SMOKE_ONLY"
	@echo "                       (BASELINE=path/sum.json VARIANT=path/sum.json required)"
	@echo "Phase 2.5 real integration:"
	@echo "  make fetch-externals Fetch rcssserver/librcsc/helios-base/cyrus2dbase tarballs into externals/src/"
	@echo "                       (optional: FORCE=1, ONLY=name)"
	@echo "  make build-externals Build the fetched externals into externals/install/"
	@echo "                       (optional: ONLY=name, JOBS=N)"
	@echo "  make real-smoke      Run 1 real helios-base-vs-helios-base match (REAL_SMOKE_EXPERIMENT overridable)"
	@echo "                       (optional: NUM_MATCHES, TIMEOUT, FORCE=1, DRY_RUN=1)"
	@echo "  make test            Run the attestation self-tests"
	@echo "  make highlights      Render a goals-only highlights mp4 from a match"
	@echo "                       (RUN_DIR=logs/.../match_NNNNNN OUTPUT=video.mp4 required)"

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
	  $(if $(ONLY),--only $(ONLY))

build-externals:
	@bash $(SCRIPTS)/build_externals.sh \
	  $(if $(ONLY),--only $(ONLY)) \
	  $(if $(JOBS),--jobs $(JOBS))

REAL_SMOKE_EXPERIMENT ?= $(ROOT)/experiments/helios_vs_helios_smoke.yaml

real-smoke:
	@bash $(SCRIPTS)/run_batch_matches.sh \
	  --experiment "$(REAL_SMOKE_EXPERIMENT)" \
	  --num-matches $(if $(NUM_MATCHES),$(NUM_MATCHES),1) \
	  $(if $(TIMEOUT),--timeout $(TIMEOUT)) \
	  $(if $(FORCE),--force) \
	  $(if $(DRY_RUN),--dry-run)

build-baseline:
	@echo "build-baseline is not automated yet."
	@echo "See setup/SETUP.md sections 4-5 for librcsc + helios-base build steps,"
	@echo "or run: make fetch-externals && make build-externals (Phase 2.5)."
	@exit 1

clean:
	@find $(ROOT)/logs/runs -mindepth 1 -not -name .gitkeep -exec rm -rf {} +
	@echo "[clean] logs/runs/ wiped (placeholder kept)."

test:
	@bash $(ROOT)/tests/test_attestation.sh

highlights:
	@if [[ -z "$(RUN_DIR)" || -z "$(OUTPUT)" ]]; then \
	  echo "RUN_DIR and OUTPUT are required, e.g." >&2; \
	  echo "  make highlights RUN_DIR=logs/experiments/<id>/matches/match_NNNNNN OUTPUT=highlights.mp4" >&2; \
	  exit 2; \
	fi
	@bash $(SCRIPTS)/make_highlights.sh \
	  --run-dir "$(RUN_DIR)" --output "$(OUTPUT)" \
	  $(if $(PRE),--pre $(PRE)) \
	  $(if $(POST),--post $(POST)) \
	  $(if $(TIMER_MS),--timer-ms $(TIMER_MS))

compare:
	@if [[ -z "$(BASELINE)" || -z "$(VARIANT)" ]]; then \
	  echo "BASELINE and VARIANT are required, e.g." >&2; \
	  echo "  make compare BASELINE=path/baseline/summary.json VARIANT=path/variant/summary.json" >&2; \
	  exit 2; \
	fi
	@python3 $(EVAL)/../scripts/compare_summaries.py "$(BASELINE)" "$(VARIANT)"
