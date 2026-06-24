# CLAUDE.md

## Project

This repository targets RoboCup Soccer Simulation 2D participation in RoboCup 2027.

The immediate focus is harness engineering:
- reproducible setup
- baseline team execution
- log collection
- batch match evaluation
- metrics extraction
- experiment documentation

## Hard Rules

Do not implement RL unless explicitly requested.
Do not modify agent behavior during harness phases.
Do not claim performance improvements without batch evaluation.
Do not delete logs or experiment results.
Do not introduce heavyweight frameworks before a minimal shell/Python harness works.

## Preferred Workflow

1. Inspect existing files.
2. Propose a small change.
3. Implement only that change.
4. Run or document tests.
5. Update notes.
6. Stop.

## File Conventions

- `setup/`: environment setup docs and dependency scripts
- `scripts/`: executable shell scripts
- `evaluation/`: Python parsers and analysis tools
- `experiments/`: YAML experiment definitions
- `logs/runs/`: generated match logs, ignored by git except `.gitkeep`
- `notes/`: development logs
- `paper/`: TDP drafts

## Acceptance Standard

A task is done only if:
- commands are documented
- failure modes are clear
- outputs are written to predictable paths
- metrics are machine-readable
- any untested assumption is marked as unverified
