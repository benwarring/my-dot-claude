#!/usr/bin/env bash
# Sets up the .pipeline/ folder for a build-pipeline run.
#
# Creates any missing folders and files, and never overwrites existing
# ones, so it's safe to run on a project with a run already in progress.
# Prints a short report for the manager: what was created, whether an
# earlier run exists, whether .pipeline/ is git-ignored, and the absolute
# paths of the reference files to pass to subagents.
#
# Usage: init-pipeline.sh [--fresh] [project-root]
#   --fresh       Move an earlier run's plan, helpers, logs, and test output
#                 into .pipeline/archive/<timestamp>/ before setting up.
#                 Project overrides (standards.md, security.md) stay put.
#   project-root  Defaults to the current directory.

set -euo pipefail

# Files and folders that belong to a single run, as opposed to the
# project's overrides, which carry over between runs.
RUN_STATE=(plan.md helpers.md logs test-runs)

# Prints a directory's absolute path. On Git Bash for Windows, `pwd -W`
# gives the C:/... form that Windows tools can open. Elsewhere it fails,
# and plain `pwd` is used.
abs_dir() {
  (cd "$1" && { pwd -W 2>/dev/null || pwd; })
}

# Joins the remaining arguments with ", ", or prints "none" if there are none.
join_or_none() {
  if (($# == 0)); then
    echo "none"
  else
    local IFS=","
    echo "$*" | sed 's/,/, /g'
  fi
}

fresh=false
if [[ "${1:-}" == "--fresh" ]]; then
  fresh=true
  shift
fi

skill_dir="$(abs_dir "$(dirname "${BASH_SOURCE[0]}")/..")"
cd "${1:-.}"
project_root="$(abs_dir .)"

created=()
existing=()
archived=""

# Creates folder $1 unless it already exists.
make_dir() {
  if [[ -d "$1" ]]; then
    existing+=("$1/")
  else
    mkdir -p "$1"
    created+=("$1/")
  fi
}

# Writes $2 to file $1 unless the file already exists.
make_file() {
  if [[ -e "$1" ]]; then
    existing+=("$1")
  else
    printf '%s' "$2" > "$1"
    created+=("$1")
  fi
}

if $fresh && [[ -e .pipeline/plan.md ]]; then
  archived=".pipeline/archive/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$archived"
  for item in "${RUN_STATE[@]}"; do
    if [[ -e ".pipeline/$item" ]]; then
      mv ".pipeline/$item" "$archived/"
    fi
  done
fi

earlier_run=no
if [[ -e .pipeline/plan.md ]]; then
  earlier_run=yes
fi

make_dir .pipeline
make_dir .pipeline/logs
make_dir .pipeline/test-runs

make_file .pipeline/plan.md '# Pipeline Plan

**Job:**
**Tests:**

## Shared helpers

| File | Helpers | Risk | Fix rounds | Status |
|------|---------|------|------------|--------|

## Files

| File | Purpose | Risk | Depends on | Fix rounds | Status |
|------|---------|------|------------|------------|--------|
'

make_file .pipeline/helpers.md '# Helpers

Shared helpers available to every file. Check here before writing new
logic.
'

make_file .pipeline/logs/standards-log.md '# STANDARDS REVIEWER LOG

'

make_file .pipeline/logs/security-log.md '# SECURITY REVIEWER LOG

'

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ignored="not a git repo"
elif git check-ignore -q .pipeline/; then
  ignored=yes
else
  ignored=no
fi

overrides=()
for name in standards.md security.md; do
  if [[ -e ".pipeline/$name" ]]; then
    overrides+=(".pipeline/$name")
  fi
done

echo "build-pipeline setup"
echo "Project root: $project_root"
echo "Earlier run found: $earlier_run"
if [[ -n "$archived" ]]; then
  echo "Archived earlier run to: $archived/"
fi
echo "Created: $(join_or_none "${created[@]}")"
echo "Already existed: $(join_or_none "${existing[@]}")"
echo "Project overrides: $(join_or_none "${overrides[@]}")"
echo ".pipeline/ git-ignored: $ignored"
echo "Reference files:"
for ref in standards security log-format escalation; do
  echo "  $ref.md: $skill_dir/references/$ref.md"
done
