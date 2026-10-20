# Model Escalation

This file sets the rules for moving a review to a stronger model. The
manager follows these rules to decide which tier runs each review.
Reviewers read the "For reviewers" section to know when to ask for one.

Escalation applies to **reviewers only**. Writers, fixers, and
test-writers always run on Opus.

## Tiers

Each reviewer type (standards and security) has three tiers, in order:

1. **Haiku**: the default. Fast and cheap, good enough for most files.
2. **Sonnet**: for files that need more careful reading.
3. **Opus**: the last tier. Nothing sits above it.

A file's starting tier comes from the risk level the manager gives it
during planning (see below). Escalation moves up **one tier at a time**
from there. Don't skip from Haiku to Opus. The one exception is raising
a file's risk level, which jumps straight to the new level's starting
tier if that tier is higher than the current one.

Each reviewer type is tracked separately. If the security review of a
file escalates to Sonnet, its standards review stays wherever it was.

---

## For the manager

### Assigning risk levels

While planning, before any writer is spawned, give every file a risk
level from 1 to 3. Record it next to the file in `.pipeline/plan.md`,
and update it there if it changes. The level sets
the starting tier for **both** of the file's reviews:

| Level | Starting tier | Use for |
|-------|---------------|---------|
| 1 | Haiku | Code that touches no external input and no sensitive data: pure helpers, formatting, data structures, non-secret config, UI layout. |
| 2 | Sonnet | Code that crosses a boundary or is tricky to get right: handling external input, network or file I/O, database queries, calls to outside APIs, reading secrets from the environment, concurrency, non-trivial algorithms. |
| 3 | Opus | Code where a subtle bug is a security hole or loses data: authentication, sessions and tokens, cryptography, payments, permissions, parsing untrusted file formats, migrations or deletes on real data. |

Judge by what the file will do, not by its size. A short token-checking
function is level 3. A long report formatter is level 1.

When a file sits between two levels, choose the higher one. Starting one
tier too high costs one more expensive review. Starting too low can
cost a missed vulnerability plus the escalation round that catches it.

**Recheck after writing.** When the writer reports back, compare what the
file actually does with the level you planned. If the writer added
something riskier (a file planned as a helper ended up handling auth
tokens), raise the level before the first review. Never lower a level
once it's set.

### When to escalate

Re-run a review at the next tier when any of these is true:

1. **The reviewer asked.** Its summary ends with a sentence starting
   `Escalate:`. Always honor this; a re-review costs less than a missed
   problem.
2. **The file was under-rated.** A review shows the file does something
   above its risk level, such as a level 1 file that turns out to build
   SQL from user input. Raise the level and re-review at the new level's
   starting tier. If a review below Opus passed a file that belongs at
   level 3 and didn't ask for escalation, don't trust that review. It
   missed the escalation rule at the end of `security.md`, so it may have
   missed other things too.
3. **The output is malformed twice.** The round line doesn't match
   `### Round N · Tier · PASS|FAIL`, an issue cites a rule that doesn't
   exist, or the line numbers point at code that doesn't match the
   description. Re-run once at the same tier. If the second attempt is
   also malformed, escalate.
4. **A finding is disputed.** The fixer reports that a blocking issue is
   a false positive and explains why. Don't settle it yourself. Have the
   next tier review the file. Its verdict decides.
5. **The reviewer contradicts itself.** A re-review flags something that
   an earlier fix was made specifically to satisfy (for example, round 1
   asks for a helper to be extracted and round 2 asks for it to be
   inlined). Escalate rather than sending the fixer in circles.

Don't escalate just because a file has many issues. A `FAIL` with clear,
well-located issues means the review worked.

### Escalate before fixing

If a review returns `FAIL` and also asks for escalation, run the
higher-tier review **before** spawning a fixer. The fixer should work
from the stronger review, not spend a fix round on findings that may
change.

### How to run an escalated review

- Log it as a **new round** under the same file heading, with the new
  tier on the round line. The earlier round stays in the log as written.
- Give the higher-tier reviewer the reason for escalation and the
  previous round's issues, and tell it to do a **full, independent
  review** rather than only checking those items. Earlier findings are
  context, not a checklist.
- The higher tier's verdict replaces the lower tier's. If Haiku said
  `FAIL` and Sonnet says `PASS`, the file passes.

### Tiers don't go back down

Once a reviewer type escalates for a file, every later review of that
file by that reviewer type uses the higher tier. A lower tier checking
fixes to a higher tier's findings may miss them or judge them
differently.

Tiers are per file. Escalating one file doesn't change the starting tier
or risk level of any other file.

### Escalation and the fix-round cap

The 3-round cap counts **fixer runs**, not reviews. Escalated reviews,
and retries after malformed output, don't use up a fix round.

### When Opus asks for escalation

There's no tier above Opus, so an `Escalate:` from Opus means the file
needs a person. Let the verdict stand: a `PASS` moves on to testing and a
`FAIL` goes to the fixer as usual. Add the file and the escalation reason
to a **needs human review** list, and include that list in your final
report to the user.

If the Opus reviewer suspects a security vulnerability it couldn't
confirm, tell the user right away rather than waiting for the final
report.

---

## For reviewers

End your summary with a sentence starting with `Escalate:` when a
stronger model would review this file meaningfully better. The format is
in `log-format.md`.

**Security reviewers:** follow the escalation triggers at the end of
`security.md`.

**Standards reviewers:** ask for escalation when:

- You searched for an existing helper (Rule 1a) and couldn't tell
  whether one matches, for example because the project is large or
  helpers are spread across many modules.
- The file's structure is complex enough (heavy indirection, generated
  code, unusual metaprogramming) that you aren't confident your review
  covered it.
- A project override in `.pipeline/standards.md` conflicts with this
  rulebook in a way you can't resolve.

Example: `Escalate: two existing helpers in src/utils/ look close to
format_row(), and I couldn't tell whether either one fits.`

Don't ask for escalation to have someone double-check a clean file, or
because you found many issues. Report what you found, and let the
manager decide.
