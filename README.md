# my-dot-claude

My Claude Code setup: agents and skills that live in `~/.claude`, kept in
git. The main piece is **build-pipeline**, a skill where the main Claude
Code session acts as a manager and has subagents write, review, fix, and
test code to a set of standards.

## How to run

Install first if you haven't (see [Install](#install)). Then, in Claude
Code, from the root of the project you want to build in:

```
/build-pipeline <what to build>
```

For example:

```
/build-pipeline Add CSV import for customer records: a reader that validates rows, and an upload endpoint that uses it
```

`<what to build>` is a plain description of what you want. For a bigger
job, write a spec file and point to it:

```
/build-pipeline Build what's described in docs/csv-import-spec.md
```

You don't write `.pipeline/plan.md` yourself. The manager writes it from
your description and shows it to you before building anything. If the
description is too vague to plan from, it asks you questions first.

Run the manager session on Opus. It does the planning and makes the
judgment calls.

### What happens

1. **Setup.** A script creates `.pipeline/` in the project, holding the
   plan, a helper index, the review logs, and test output. It never
   overwrites existing files.
2. **Plan.** The manager splits the job into files, gives each a risk
   level from 1 to 3, and pulls logic that several files need into
   shared helpers. It shows you the plan and **waits for your approval**.
   Nothing is written before you approve.
3. **Build.** Shared helpers are built first, then the other files, about
   four at a time. Each file is written, reviewed for standards and
   security, fixed if a review fails (up to 3 rounds), and then tested.
4. **Report.** Each file's final status, anything that needs your
   attention, and test results.

### When the manager stops to ask you

- To approve the plan.
- Whether to add `.pipeline/` to `.gitignore`, if it isn't there.
- Whether to resume or start fresh, if an earlier run exists.
- Which test framework to use, if the project doesn't have one.
- When a file still fails after 3 fix rounds, or a subagent is blocked.
- Right away, if a review finds a committed secret. Removing it from the
  code isn't enough; **rotate the key**.

### Watching progress

- `.pipeline/plan.md`: every file and its current status.
- `.pipeline/logs/standards-log.md` and `.pipeline/logs/security-log.md`:
  a plain-language summary of every review round, plus the issues found.

### Resuming or starting over

Run `/build-pipeline` again in the same project. The manager sees the
earlier run and asks whether to resume it or start fresh. Starting fresh
moves the old plan, logs, and test output into `.pipeline/archive/`.

### Project-specific rules

To change the rules for one project, add `.pipeline/standards.md` or
`.pipeline/security.md` to it. Where a project file conflicts with the
defaults, the project file wins. Starting fresh keeps these files.

## Install

You need:

- Claude Code, with access to Opus, Sonnet, and Haiku.
- bash. On Windows, that's the Git Bash that Claude Code already uses.

Clone the repo anywhere, then link its pieces into `~/.claude`. Don't
make `~/.claude` itself the repo, because Claude Code also keeps its
runtime files there (sessions, caches, settings).

**macOS, Linux, or WSL:**

```bash
git clone git@github.com:benwarring/my-dot-claude.git ~/my-dot-claude
REPO=~/my-dot-claude

mkdir -p ~/.claude/skills
ln -s "$REPO/agents" ~/.claude/agents
ln -s "$REPO/skills/build-pipeline" ~/.claude/skills/build-pipeline
```

In WSL, `~` is your Linux home, not your Windows one. If the clone lives
on the Windows drive, set `REPO` to its `/mnt/c/...` path.

**Windows (PowerShell):** junctions work without admin rights.

```powershell
git clone git@github.com:benwarring/my-dot-claude.git C:\Projects\my-dot-claude
$repo = "C:\Projects\my-dot-claude"

New-Item -ItemType Directory -Force "$HOME\.claude\skills" | Out-Null
New-Item -ItemType Junction -Path "$HOME\.claude\agents" -Target "$repo\agents"
New-Item -ItemType Junction -Path "$HOME\.claude\skills\build-pipeline" -Target "$repo\skills\build-pipeline"
```

**If you already have agents** in `~/.claude/agents`, link the files one
by one instead of replacing the folder:
`ln -s "$REPO"/agents/*.md ~/.claude/agents/`. Rerun it when agents are
added.

**Restart Claude Code** after linking. To check the install, typing
`/build-pipeline` should autocomplete, and asking Claude which subagents
it has should list the pipeline agents.

## How it works

### Roles

| Agent | Model | Job |
|-------|-------|-------|
| Manager (your main session) | Opus | Plans, spawns subagents, keeps the logs, reports to you |
| `file-writer` | Opus | Writes one file from the plan |
| `standards-reviewer-{haiku,sonnet,opus}` | Varies | Checks one file against `standards.md` |
| `security-reviewer-{haiku,sonnet,opus}` | Varies | Checks one file against `security.md` |
| `file-fixer` | Opus | Fixes the blocking issues from a failed review or test |
| `test-writer` | Opus | Writes and runs tests, never edits the source |

Reviewers can read the project but not change it. Each one returns its
log entry to the manager, and only the manager writes the logs, so
reviewers running in parallel can't overwrite each other.

### Reviews

Each issue a reviewer finds is either **blocking**, which fails the
file, or a **suggestion**, which is logged and doesn't. A file passes
when neither review has a blocking issue. After any fix, both reviews
run again, because a fix for one can break something the other checks.

### Risk levels and escalation

The manager gives every file a risk level while planning. The level sets
which model starts the reviews:

| Level | Starts at | For |
|-------|-----------|-----|
| 1 | Haiku | Code with no external input or sensitive data |
| 2 | Sonnet | External input, I/O, databases, outside APIs, concurrency |
| 3 | Opus | Auth, crypto, payments, permissions, untrusted file parsing, deleting data |

A review moves up a tier when the reviewer asks for it, when a fixer
disputes a finding, or when the output can't be trusted. Tiers never go
back down for a file. When an Opus reviewer still asks to escalate, the
file goes on a "needs human review" list in the final report. The full
rules are in [escalation.md](skills/build-pipeline/references/escalation.md).

### Cost

Every file gets at least two Opus runs (writing and testing) plus two
reviews, and each fix round adds a fixer run and two more reviews. Large
jobs add up, so check the plan's size before you approve it.

## Customizing

- **Default rules:** edit
  [standards.md](skills/build-pipeline/references/standards.md) and
  [security.md](skills/build-pipeline/references/security.md). The
  "Additional rules" sections are optional, so delete any you don't want.
- **Reviewer tiers:** the three files for each reviewer are identical
  apart from the model and the tier name. If you change one, change all
  three.
- **Log format:** [log-format.md](skills/build-pipeline/references/log-format.md).
  The manager reads each review's `### Round N · Tier · PASS|FAIL` line
  to decide what happens next, so keep that line's pattern exactly.

## Repo layout

```
my-dot-claude/
├── README.md
├── agents/                       subagents spawned by the manager
│   ├── file-writer.md
│   ├── file-fixer.md
│   ├── test-writer.md
│   ├── standards-reviewer-{haiku,sonnet,opus}.md
│   └── security-reviewer-{haiku,sonnet,opus}.md
└── skills/build-pipeline/
    ├── SKILL.md                  the manager's playbook
    ├── scripts/
    │   └── init-pipeline.sh      creates .pipeline/ in the target project
    └── references/
        ├── standards.md          code standards rulebook
        ├── security.md           security rulebook
        ├── log-format.md         review log format
        └── escalation.md         risk levels and model escalation
```
