---
name: build-pipeline
description: Build code with a managed pipeline of subagents. Opus writers produce each file, standards and security reviewers check it (escalating from Haiku to Sonnet to Opus as needed), Opus fixers address failures, and Opus test-writers write and run tests.
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
└── archive/              earlier runs, moved here by `--fresh`
```

You are the only agent that writes `plan.md`, `helpers.md`, and the
logs. Several subagents run in parallel, and only one writer per file
keeps them from overwriting each other.

If the setup report says `.pipeline/ git-ignored: no`, ask the user
whether to add it to `.gitignore`. Don't edit `.gitignore` without
asking.

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
2. Look at the project's layout, language, and existing helpers just
   enough to plan.
3. Find the test setup: framework, where tests live, and the run
   command. If the project has none, ask the user what to use.
4. Split the job into files. For each file, decide what it does, what
   it depends on, and its risk level (see `escalation.md`).
5. Find **shared helpers**: logic that two or more planned files will
   need. Put them in their own files. They're built first, because
   writers running in parallel can't see each other's new code.
6. Fill in `.pipeline/plan.md` in the format below.
7. Show the user the plan (files, risk levels, shared helpers) and
   **wait for their approval** before spawning any subagents.

### plan.md format

```markdown
# Pipeline Plan

**Job:** Add CSV import for customer records.
**Tests:** pytest, tests/ mirrors src/, run with `pytest <test file>`

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
moves.

You don't need to track the current review tier. It's the tier on the
file's latest round in each log, because tiers never go back down.

## Phase 2: Shared helpers

Run each shared helper file through the whole pipeline (Phase 3) before
spawning any writer that depends on it. Once its reviews pass, add its
helpers to `helpers.md` so the next writers can find them. Its tests can
run alongside the later phases.

If nothing depends on anything else, skip straight to Phase 3.

## Phase 3: Per-file pipeline

Process files whose dependencies are done, a few at a time (about four).
Spawn subagents in the background and handle each result as it arrives.
Use the agent's name from `agents/` as the subagent type.

### 1. Write

Spawn `file-writer` with:
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
| PASS | PASS | Step 4: Register helpers and test |
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

### 4. Register helpers and test

1. Add the file's public helpers to `helpers.md` (format below), using
   the writer's and fixers' New helpers lists.
2. Spawn `test-writer` with the file path, the test setup from
   `plan.md`, and the absolute path to `standards.md`.

When it returns:
- `pass`: set the file to `done`.
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

One `##` heading per file, in the order files passed review. Add only
public helpers that other files could reuse.

---

## Phase 4: Report

When every file is `done`, `flagged`, or `blocked`, give the user:

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

Keep it short. The logs hold the detail.
