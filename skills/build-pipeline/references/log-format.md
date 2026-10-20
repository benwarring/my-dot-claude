# Review Log Format

The pipeline keeps two logs per project, both in the same format:

- `.pipeline/logs/standards-log.md`, written from standards reviews
- `.pipeline/logs/security-log.md`, written from security reviews

Two readers use these logs. The person running the pipeline skims them to
see progress while it runs. The manager reads them to decide what happens
next. The format serves both: a plain-language summary for the person, and
a fixed verdict line and issue list the manager can rely on.

## Who writes the log

Reviewers do **not** edit the log files directly. Several reviewers run in
parallel, and two of them appending to the same file at once can overwrite
each other's entries. Each reviewer instead returns its entry, in exactly
the format below, as its final response. The manager is the only agent that
writes to the logs, and it appends each entry as it arrives.

## Structure

```markdown
# STANDARDS REVIEWER LOG

## src/utils/parser.py

### Round 1 · Haiku · FAIL

**Summary:** The parsing logic is solid and well named, but the same
date-validation block appears twice and one public function has no
docstring. Both need fixing before this file passes. There's also one
small cleanup suggestion.

* Lines 42–51 · blocking · Rule 1
   * Date-validation logic is repeated almost exactly at lines 88–97.
     If the accepted date format changes, one copy will likely be missed.
* Line 12 · blocking · Rule 3
   * `parse_record()` is public but has no docstring, so callers can't
     tell what it returns or that it raises `ValueError` on bad input.
* Line 3 · suggestion · Rule 7
   * `import json` is never used.

### Round 2 · Haiku · PASS

**Summary:** Both blocking issues from round 1 are fixed. Date validation
now lives in one helper, `validate_date()`, and `parse_record()` is
documented. No new issues.

## src/api/client.py

### Round 1 · Haiku · PASS

**Summary:** Clean file. Helpers are small and documented, and it reuses
`build_headers()` from `src/utils/http.py` rather than writing its own.
```

The security log is identical except for its top heading,
`# SECURITY REVIEWER LOG`.

## Rules for each part

### File heading (`##`)

Use the file's path relative to the project root, not just the file name.
Two files named `utils.py` in different folders must not share a heading.

Each file gets **one** heading. When a file is reviewed again, the new
round goes under the same heading, below the earlier rounds. Never delete
or rewrite an earlier round; the history shows what was fixed and when.

### Round line (`###`)

Always three parts, separated by ` · `:

1. **Round N**: 1 for the first review, increasing with each re-review.
2. **Model tier**: `Haiku`, `Sonnet`, or `Opus`, whichever reviewer ran it.
3. **Verdict**: `PASS` or `FAIL`, in capitals.

The verdict is `FAIL` if there is **at least one blocking issue**, and
`PASS` otherwise. Suggestions alone never fail a file.

The manager reads this line to decide the next step, so it must match
this pattern exactly. Put nothing else on it.

### Summary

Written for the person watching the pipeline, not for another agent. Use
one to three sentences of plain language covering what's good, what's
wrong, and whether the file passes. A reader who sees only the summaries
should still know where every file stands.

On a re-review, say whether the earlier blocking issues were fixed, and
mention any new issues the fix introduced.

If the review calls for a stronger model, end the summary with one
sentence starting with `Escalate:` and give the reason. The rules for when
to do this are at the end of `security.md` and in `escalation.md`. The
manager looks for this exact word, so don't rephrase it.

### Issues

One bullet per issue, in order of line number. Each bullet has two
levels.

**Top level:** location · severity · rule, separated by ` · `

- **Location**: `Line 12` for a single line, `Lines 42–51` for a range, or
  `File-level` for an issue with no specific line (such as a missing
  module docstring).
- **Severity**: `blocking` or `suggestion`, as defined at the top of
  `standards.md`. Security reviews use the same two levels, defined in
  `security.md`.
- **Rule**: the rule number from `standards.md` or `security.md`, such as
  `Rule 1a`.

**Nested level:** what the problem is and why it matters, in one to three
sentences. Name the specific function, variable, or line content so the
fixer can find it without re-reading the whole review. If the fix isn't
obvious, add a short hint about the fix direction.

If there are no issues, leave out the issue list entirely. A `PASS` with
no bullets is a clean review.

## Starting a new log

The setup script (`scripts/init-pipeline.sh`) creates both logs at the
start of a run, each with only its top heading (`# STANDARDS REVIEWER
LOG` or `# SECURITY REVIEWER LOG`) and a blank line. The manager appends
entries from there.