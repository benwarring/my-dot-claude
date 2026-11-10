#!/usr/bin/env bash
# Git branches and worktrees for a build-pipeline run.
#
# Each planned file is built on its own branch, in its own worktree, made
# from an integration branch that collects every file once it passes. At
# the end, the integration branch is merged into the branch the run
# started on. Nothing is ever pushed. Run from the project root.
#
# Usage:
#   pipeline-git.sh start              Create the integration branch and
#                                      its worktree from the current branch.
#   pipeline-git.sh file <label>       Create a file's branch and worktree
#                                      from the integration branch. Prints
#                                      the worktree's absolute path.
#   pipeline-git.sh integrate <label>  Merge a file's branch into the
#                                      integration branch.
#   pipeline-git.sh finish [message]   Merge the integration branch into the
#                                      starting branch, then remove clean
#                                      worktrees and merged branches.
#
# <label> is the file's cell in plan.md, such as "src/cli.py (M2)".
# Every command is safe to repeat.

set -euo pipefail

STATE=.pipeline/git-run
WORKTREES=.pipeline/worktrees
INTEGRATION_DIR="$WORKTREES/_integration"

die() {
  echo "error: $*" >&2
  exit 1
}

# Prints a directory's absolute path, in C:/... form on Git Bash for Windows.
abs_dir() {
  (cd "$1" && { pwd -W 2>/dev/null || pwd; })
}

# Turns a plan.md label into a branch and folder name:
# "src/cli.py (M2)" -> "src-cli-py-m2".
# ponytail: labels that differ only in punctuation share a slug; rename one
# in plan.md if that ever happens.
slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# Reads the base branch and run prefix that `start` saved.
load_state() {
  [[ -f "$STATE" ]] || die "no run started; run 'start' first"
  { read -r base; read -r run; } < "$STATE"
}

branch_exists() {
  git rev-parse -q --verify "refs/heads/$1" >/dev/null
}

# Merges branch $2 into the branch checked out at $1, with merge commit
# message $3. On failure, undoes the merge and exits, naming any conflicts.
merge_into() {
  local dir="$1" branch="$2" message="$3" conflicts
  if ! git -C "$dir" merge -q --no-ff -m "$message" "$branch"; then
    conflicts="$(git -C "$dir" diff --name-only --diff-filter=U | paste -sd ' ' -)"
    git -C "$dir" merge --abort 2>/dev/null || true
    die "merging $branch failed${conflicts:+ (conflicts: $conflicts)}; nothing was changed"
  fi
}

# Removes a worktree unless git refuses, usually because it has uncommitted
# files. Those are left for a person to look at.
remove_worktree() {
  [[ -d "$1" ]] || return 0
  if git worktree remove "$1" 2>/dev/null; then
    echo "Removed worktree $1"
  else
    echo "Kept worktree $1 (it has uncommitted files)"
  fi
}

cmd_start() {
  if [[ -f "$STATE" ]]; then
    load_state
    echo "Run already started."
  else
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repo"
    base="$(git symbolic-ref --short -q HEAD)" || die "HEAD is detached; check out a branch first"
    git check-ignore -q .pipeline/ || die ".pipeline/ isn't git-ignored; add it to .gitignore or .git/info/exclude"
    [[ -z "$(git status --porcelain)" ]] || die "uncommitted changes on $base; commit or stash them first"
    run="pipeline/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$WORKTREES"
    git worktree add -q -b "$run/_integration" "$INTEGRATION_DIR" "$base"
    printf '%s\n%s\n' "$base" "$run" > "$STATE"
  fi
  echo "Base branch: $base"
  echo "Integration branch: $run/_integration"
  echo "Integration worktree: $(abs_dir "$INTEGRATION_DIR/$prefix")"
}

cmd_file() {
  [[ -n "${1:-}" ]] || die "usage: file <label>"
  load_state
  local name dir
  name="$(slug "$1")"
  dir="$WORKTREES/$name"
  if [[ ! -d "$dir" ]]; then
    if branch_exists "$run/$name"; then
      git worktree add -q "$dir" "$run/$name"
    else
      git worktree add -q -b "$run/$name" "$dir" "$run/_integration"
    fi
  fi
  abs_dir "$dir/$prefix"
}

cmd_integrate() {
  [[ -n "${1:-}" ]] || die "usage: integrate <label>"
  load_state
  local name branch tip
  name="$(slug "$1")"
  branch="$run/$name"
  branch_exists "$branch" || die "no branch $branch"
  tip="$(git rev-parse "$branch")"
  # Our --no-ff merges record the file branch's tip as the second parent.
  if git rev-list --merges --parents "$run/_integration" | grep -q " $tip\$"; then
    echo "$branch is already integrated."
  elif git merge-base --is-ancestor "$branch" "$run/_integration"; then
    die "$branch has no commits of its own; was the file committed?"
  else
    merge_into "$INTEGRATION_DIR" "$branch" "Merge $1"
    echo "Integrated $branch into $run/_integration"
  fi
  remove_worktree "$WORKTREES/$name"
}

cmd_finish() {
  load_state
  local current
  current="$(git symbolic-ref --short -q HEAD || true)"
  [[ "$current" == "$base" ]] || die "the main checkout is on '${current:-detached HEAD}', not '$base'; check out $base first"
  branch_exists "$run/_integration" || die "no integration branch; was the run already finished?"
  merge_into . "$run/_integration" "${1:-Merge build-pipeline run ${run#pipeline/}}"
  echo "Merged $run/_integration into $base. Nothing has been pushed."
  local dir branch
  for dir in "$WORKTREES"/*/; do
    remove_worktree "${dir%/}"
  done
  # -d deletes only branches that are merged and not checked out in a kept worktree.
  for branch in $(git for-each-ref --format='%(refname:short)' "refs/heads/$run/"); do
    if git branch -q -d "$branch" 2>/dev/null; then
      echo "Deleted branch $branch"
    else
      echo "Kept branch $branch"
    fi
  done
}

# Worktrees check out the whole repo, so a project in a subfolder of its
# repo sits at the same subfolder inside each worktree.
prefix="$(git rev-parse --show-prefix 2>/dev/null || true)"

case "${1:-}" in
  start) cmd_start ;;
  file) cmd_file "${2:-}" ;;
  integrate) cmd_integrate "${2:-}" ;;
  finish) cmd_finish "${2:-}" ;;
  *) die "usage: pipeline-git.sh start | file <label> | integrate <label> | finish [message]" ;;
esac
