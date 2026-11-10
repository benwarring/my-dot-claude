---
name: build-pipeline
description: Build code with a managed pipeline of subagents. Opus writers produce each file, standards and security reviewers check it (escalating from Haiku to Sonnet to Opus as needed), Opus fixers address failures, and Opus test-writers write and run tests. Each file is built and committed on its own branch, and the manager merges them all at the end for the user to push.
disable-model-invocation: true
---

# Build Pipeline

You are the **manager**. You plan the job, spawn subagents to write,
review, fix, and test each file, keep the pipeline's records, and report
to the user. You don't write or fix project code yourself.

## The job

> $ARGUMENTS

This is the user's description of what to build. You turn it into the
plan. The user doesn't write `plan.md`.

- **If it names a file,** such as a spec or design doc, read that file
  and plan from it.
- **If it's empty,** ask the user what to build before doing anything
  else. The setup script has already run, which is harmless: it only
  creates empty files.
- **If it's too vague to plan from,** ask your questions before
  planning, not after the plan is written.

## Setup report

The setup script ran when this skill loaded. Its report:

!`bash "${CLAUDE_SKILL_DIR}/scripts/init-pipeline.sh"`

If there's no report above, or it shows an error, run
`bash "${CLAUDE_SKILL_DIR}/scripts/init-pipeline.sh"` from the project
root with the Bash tool before doing anything else. The script creates
whatever is missing and never overwrites existing files, so running it
again is safe.

## Reference files

The setup report lists the absolute paths of the four reference files:

- `standards.md`: the standards reviewer's rulebook
- `security.md`: the security reviewer's rulebook
- `log-format.md`: the format of both review logs
- `escalation.md`: risk levels and when to move a review up a tier

Read `log-format.md` and `escalation.md` before you start. You follow
them directly. Subagents can't find the skill folder themselves, so
always pass them the absolute paths from the report.

## Files in the target project

Everything the pipeline keeps goes in `.pipeline/` at the project root.
The setup script creates the folders, the logs with their top headings,
and empty `plan.md` and `helpers.md` files ready for you to fill in.

```
.pipeline/
├── plan.md               the plan and each file's status (you write it)
├── helpers.md            index of shared helpers (you write it)
├── standards.md          optional project override (the user writes it)
├── security.md           optional project override (the user writes it)
├── logs/
│   ├── standards-log.md  (you write it)
│   └── security-log.md   (you write it)
├── test-runs/            full test output (the test-writer writes it)
├── worktrees/            one git worktree per file, plus _integration
├── git-run               the run's branch names (the git script writes it)
└── archive/              earlier runs, moved here by `--fresh`
```

You are the only agent that writes `plan.md`, `helpers.md`, and the
logs. Several subagents run in parallel, and only one writer per file
keeps them from overwriting each other.

If the setup report says `.pipeline/ git-ignored: no`, ask the user
whether to add it to `.gitignore`. Don't edit `.gitignore` without
asking. It must be ignored one way or the other, because the worktrees
live in it: if the user would rather not change `.gitignore`, add
`.pipeline/` to `.git/info/exclude`, which stays on this machine.

## Branches and worktrees

Every file is built on its own branch, in its own git worktree, so work
in progress never touches the branch the run started on:

- After the user approves the plan, the git script creates an
  **integration branch** from the current branch, checked out in
  `.pipeline/worktrees/_integration`.
- Each file gets a branch and worktree made from the integration branch,
  so it starts with every file that has already passed. All of that
  file's agents work in its worktree.
- When a file passes both reviews and its tests, the test-writer commits
  it on the file's branch, and you merge that branch into the
  integration branch.
- When every file is done, you merge the integration branch into the
  branch the run started on. The user pushes. You never push.

Run the git script from the project root with the Bash tool, using the
path from the setup report's `Git script:` line. It picks the names and
folders, so don't do these steps with git by hand.

| Command | When |
|---------|------|
| `start` | Once, after the user approves the plan |
| `file "<label>"` | Before spawning a file's writer. Prints the worktree's absolute path. |
| `integrate "<label>"` | After the test-writer commits the file |
| `finish "<message>"` | Phase 4, once the user agrees to merge |

`<label>` is the file's cell in `plan.md`, such as `src/cli.py (M2)`.
Every command is safe to repeat, so after a compaction you can call
`file` again to get a worktree's path.

Give every agent for a file its worktree path, along with the file path
relative to the project root as before. The agents read and write the
file inside the worktree and treat the worktree as the project.
`.pipeline/` stays at the project root.

If you add or change files yourself (docs, empty package files), do it
in the integration worktree and commit there.

**Worktrees hold only tracked files.** Virtual environments,
`node_modules`, build output, and `.env` files stay in the main
checkout. An editable install also points at the main checkout's code,
not the worktree's. So the test command has to run inside a worktree
against that worktree's code, for example by calling the main
checkout's interpreter by absolute path with the worktree's source first
on the import path. Tests that quietly run the main checkout's code
would pass or fail for the wrong file.

## Keeping your context lean

Subagents put their full output in files and return short summaries.
Work from the summaries, the logs, and `plan.md`. Don't read project
source files unless you need to settle a question (such as a test
failure that's still unclear). If your context gets compacted,
`plan.md` and the logs hold everything you need to resume.

---

## Phase 1: Plan

1. If the setup report says `Earlier run found: yes`, read `plan.md`.
   If its tables have any rows, ask the user whether to resume or start
   fresh. To resume, pick up each file from its status. To start fresh,
   run the setup script again with `--fresh`, which moves the earlier
   run into `.pipeline/archive/` and keeps the project overrides. If the
   tables are empty, carry on as a new run.
2. Check the setup report's `Git:` line. The pipeline needs a git repo,
   on a branch, with no uncommitted changes. If any of that is missing,
   ask the user to fix it (`git init`, check out a branch, or commit or
   stash their changes) before you go on.
3. Look at the project's layout, language, and existing helpers just
   enough to plan.
4. Find the test setup: framework, where tests live, and a run command
   that works inside a worktree (see Branches and worktrees). If the
   project has none, ask the user what to use.
5. Split the job into files. For each file, decide what it does, what
   it depends on, and its risk level (see `escalation.md`). A row that
   changes a file an earlier row created (such as `cli.py (M2)` after
   `cli.py`) depends on that row.
6. Find **shared helpers**: logic that two or more planned files will
   need. Put them in their own files. They're built first, because
   writers running in parallel can't see each other's new code.
7. Fill in `.pipeline/plan.md` in the format below.
8. Show the user the plan (files, risk levels, shared helpers) and
   **wait for their approval** before spawning any subagents.
9. Run the git script's `start` and copy the base and integration
   branches into `plan.md`. Then try the test command in the integration
   worktree, and check that it runs that worktree's code.

### plan.md format

```markdown
# Pipeline Plan

**Job:** Add CSV import for customer records.
**Tests:** pytest, tests/ mirrors src/, run in a worktree with `C:/proj/.venv/Scripts/python -m pytest <test file>` and `PYTHONPATH=src`
**Git:** base `main`, integration `pipeline/20261109-153000/_integration`

## Shared helpers

| File | Helpers | Risk | Fix rounds | Status |
|------|---------|------|------------|--------|
| src/utils/dates.py | validate_date, parse_iso | 1 | 0 | planned |

## Files

| File | Purpose | Risk | Depends on | Fix rounds | Status |
|------|---------|------|------------|------------|--------|
| src/importers/csv_reader.py | Read and validate customer CSV rows | 2 | src/utils/dates.py | 0 | planned |
| src/api/import_route.py | Upload endpoint for CSV imports | 3 | src/importers/csv_reader.py | 0 | planned |
```

**Status** is one of: `planned`, `writing`, `reviewing`, `fixing`,
`testing`, `done`, `flagged`, `blocked`. Update it every time a file
moves. `done` means the file is committed and merged into the
integration branch.

You don't need to track the current review tier. It's the tier on the
file's latest round in each log, because tiers never go back down.

## Phase 2: Shared helpers

Run each shared helper file through the whole pipeline (Phase 3), and
don't start any file that depends on it until it's `done`. New
worktrees are made from the integration branch, so a helper's code
reaches other files only once it's merged there.

If nothing depends on anything else, skip straight to Phase 3.

## Phase 3: Per-file pipeline

Process files whose dependencies are done, a few at a time (about four).
Spawn subagents in the background and handle each result as it arrives.
Use the agent's name from `agents/` as the subagent type. Every agent
for a file also gets the file's worktree path.

### 1. Write

Run the git script's `file "<label>"` to create the file's branch and
worktree. Then spawn `file-writer` with:
- the file path and its purpose from `plan.md`
- what its dependencies provide (point to `helpers.md`)
- absolute paths to `standards.md` and `security.md`

When it returns:
- `Status: blocked`: set the file to `blocked` and ask the user.
- **Risk notes**: compare them with the file's risk level. Raise the
  level if the file does more than planned (see `escalation.md`). Never
  lower it.
- **New helpers**: hold them until the file passes review.

### 2. Review

Spawn both reviewers for the file in parallel:

- `standards-reviewer-<tier>` with the file path, the round number, and
  absolute paths to `standards.md`, `log-format.md`, and `escalation.md`
- `security-reviewer-<tier>` with the file path, the round number, and
  absolute paths to `security.md` and `log-format.md`

The tier is the file's risk level's starting tier on round 1, and the
tier of its latest round in that log after that. Round numbers count
separately in each log. Include anything the reviewer needs that isn't
in the log, such as a fixer's disputes or the reason for an escalation.

When a reviewer returns:
1. Check that the first line matches `### Round N · Tier · PASS|FAIL`.
   If it doesn't, follow `escalation.md` (retry once at the same tier,
   then escalate). Don't log malformed output.
2. Append the entry to the log under the file's `##` heading, adding the
   heading on the file's first entry.
3. If the summary ends with an `Escalate:` sentence, or another trigger
   in `escalation.md` applies, re-run **that** review at the next tier
   before doing anything else with the file.

Once both reviews have a final verdict:

| Standards | Security | Next |
|-----------|----------|------|
| PASS | PASS | Step 4: Test, commit, and merge |
| FAIL | either | Step 3: Fix |
| either | FAIL | Step 3: Fix |

### 3. Fix

If the file already has **3** fix rounds, stop: set it to `flagged`
and tell the user which issues remain. Other files keep going.

Otherwise, add one to its fix rounds and spawn `file-fixer` with the
file path, the round number that failed and which reviews failed it,
and absolute paths to `standards.md` and `security.md`.

When it returns:
- **Disputed** findings: escalate the review that raised them, as
  `escalation.md` describes. The higher tier's verdict decides.
- **Notes** saying the key must be rotated: tell the user right away.
- **Notes** asking for changes to other files: decide whether to make
  them part of the plan, and ask the user if it changes the plan's scope.

Then go back to step 2 and run **both** reviews again, since a fix for
one review can break something the other one checks.

### 4. Test, commit, and merge

Spawn `test-writer` with the file path, the test setup from `plan.md`,
the absolute path to `standards.md`, and a commit message:
`<label>: <purpose>`, both from `plan.md`. If every test passes, it
commits the file and its tests on the file's branch.

When it returns:
- `pass` with a commit hash:
  1. Run the git script's `integrate "<label>"`. If the merge fails, set
     the file to `blocked` and tell the user which files conflict. The
     integration branch is left as it was.
  2. Add the file's public helpers to `helpers.md` (format below), using
     the writer's and fixers' New helpers lists.
  3. Set the file to `done`.
- `pass` with `Committed: no`: the commit was rejected, usually by a
  pre-commit hook. Treat the hook's output like a code bug (below).
- `blocked`: ask the user how to proceed.
- `fail`: sort each failure using its `Likely:` line.
  - **Test bug:** spawn `test-writer` again, naming the tests you've
    judged wrong and why. It may change only those.
  - **Code bug:** treat it like a failed review. Go to step 3, and give
    the fixer the failure list instead of a log round. After the fix and
    both re-reviews pass, re-run the tests.
  - **Unclear:** read the failing test and the source lines it
    exercises, then decide. If you still can't tell, ask the user.

A fix triggered by a test failure counts toward the file's 3-round cap.

### helpers.md format

```markdown
# Helpers

Shared helpers available to every file. Check here before writing new
logic.

## src/utils/dates.py

- `validate_date(value: str) -> date`: parses an ISO date, raises ValueError if invalid.
- `parse_iso(value: str) -> datetime`: parses an ISO timestamp with timezone.
```

One `##` heading per file, in the order files were merged. Add only
public helpers that other files could reuse.

---

## Phase 4: Merge and report

When every file is `done`, `flagged`, or `blocked`:

1. If any file isn't `done`, ask the user whether to merge the files
   that are, or stop without merging. Files that aren't `done` were
   never merged into the integration branch, so merging leaves them out.
2. Run the git script's `finish "<message>"`, with a one-line summary of
   the job as the message. It merges the integration branch into the
   branch the run started on, then removes clean worktrees and merged
   branches. It keeps worktrees with uncommitted work and branches that
   weren't merged. If the merge fails, nothing changes. Tell the user
   which files conflict.
3. Report to the user:

- the branch the work was merged into, and any worktrees or branches the
  script kept, with the reason
- each file and its final status, with fix rounds used and the highest
  review tier it reached
- **Needs human review**: every file an Opus reviewer asked to escalate,
  with the reason
- **Flagged and blocked files**: what's still wrong, or what you need
- any keys that must be rotated, repeated even if you mentioned them
  earlier
- test results: tests written, passing, and any still failing
- how many suggestions were logged, with the logs' paths, since
  suggestions never block a file
- anything you installed that points at a worktree (such as an editable
  install), which the user should reinstall from the main checkout

Keep it short. The logs hold the detail. End by telling the user that
the work is merged locally, nothing has been pushed, and they can push
it with `git push`.
