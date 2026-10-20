# Code Standards

This file is the rulebook for the standards reviewer. Each rule says what to
check, why it matters, and where the line is, so reviews stay consistent
across model tiers (Haiku, Sonnet, Opus) and across files.

If a project has its own `.pipeline/standards.md`, that file takes precedence
over this one wherever they conflict.

## Severity

Every issue you report gets one of two severities. The manager uses this to
decide whether to send the file back for fixes.

- **blocking**: breaks a rule below. The file does not pass until it is fixed.
- **suggestion**: an improvement that isn't required. Log it, but it does not
  fail the review.

When unsure, choose `suggestion`. Sending a file back costs a full fix cycle,
so only block on clear violations.

---

## Core rules

### 1. No repeated code chunks

**Check:** the same logic appearing in more than one place, whether copied
exactly or with only names or literal values changed.

**Why:** duplicated logic gets fixed in one copy and forgotten in the other.
That divergence is a common source of bugs.

**Where the line is:**
- Blocking: a block of roughly 3 or more lines of logic repeated 2 or more
  times in the file, or a block clearly copied from another file in the
  project.
- Not a violation: short, idiomatic patterns that every function naturally
  shares (a guard clause, opening a file, a standard loop shape). Pulling
  those into a helper would make the code harder to read, not easier.

**Fix direction:** extract the shared logic into a helper (see rule 2), with
the parts that differ passed in as parameters.

#### 1a. Reuse helpers that already exist elsewhere

**Check:** logic in this file that re-implements something an existing
helper elsewhere in the project already does. Start with the helper index
at `.pipeline/helpers.md`, then search the codebase for likely matches
(similar function names, the same library calls, the same transformation).

**Why:** two helpers that do the same job are duplicated code spread across
files, which is harder to notice and just as likely to drift apart.

**Where the line is:**
- Blocking: an existing helper does the same job and could be called as-is
  or with a small added parameter.
- Suggestion: an existing helper is close but would need real changes to
  fit. Note it, and leave it to the manager whether to generalize it.
- Not a violation: the existing helper lives in a module this file
  shouldn't depend on (for example, a test utility, or a layer the
  architecture keeps separate). Say so in the log.

**Fix direction:** import and call the existing helper. If it's close but
not quite right, report that rather than editing the other file. Changes
to a file outside the one under review go through the manager.

### 2. Use helper functions to keep code modular

**Check:** functions that do several distinct jobs, or long functions that
would be easier to follow as a few named steps.

**Why:** small, single-purpose functions are easier to test, reuse, and
read. The test-writer subagent depends on this; a function that does five
things needs five times the test setup.

**Where the line is:**
- Blocking: a function that mixes clearly separate responsibilities (for
  example, fetching data, transforming it, and writing output all in one
  body), or a function long enough that you have to scroll to follow it
  (as a rough guide, more than about 50 lines of logic).
- Not a violation: a longer function that does one thing in a straight
  line. Do not demand splitting a function into pieces that would each be
  called only once and say nothing new by their names. Over-fragmenting
  is its own readability problem.

**Fix direction:** split along responsibilities, and name each helper for
what it does (`parse_header`, not `helper2`).

### 3. Clear comments and documentation

**Check:**
- Every public function, class, method, and module has a docstring (or the
  language's equivalent, such as JSDoc or `///` doc comments).
- Docstrings say what the code does, what each parameter is, what it
  returns, and what errors it can raise.
- Non-obvious logic has a comment explaining *why* it is done this way.

**Why:** the next reader, human or agent, should understand a function
without reading its body.

**Where the line is:**
- Blocking: a public function, class, or module with no docstring; a
  docstring that is wrong about what the code does; tricky logic (a
  workaround, an unusual algorithm, a magic-looking condition) with no
  explanation.
- Suggestion: private helpers without docstrings, when their name and
  signature already make the purpose clear.
- Not wanted: comments that restate the code (`# increment i` above
  `i += 1`). Flag these as suggestions to remove.

---

## Additional rules

These go beyond the core list. Delete any you don't want.

### 4. Clear, consistent naming

**Check:** names that describe what a thing is or does. No single-letter
names outside short loops and math, no unexplained abbreviations, and
consistency with the naming style already used in the project.

**Blocking:** names that are misleading (`user_list` holding a dict) or
meaningless (`data2`, `tmp_thing`) for anything that lives longer than a
few lines.

### 5. No magic numbers or hardcoded configuration

**Check:** unexplained literal values in logic (`if retries > 7`), and
values like file paths, URLs, timeouts, or limits written directly into
the code.

**Blocking:** hardcoded environment-specific values (paths, hostnames,
ports). Secrets are the security reviewer's job, so don't duplicate that
check here.
**Suggestion:** other unnamed literals that would read better as a named
constant.

### 6. Errors are handled, not hidden

**Check:** errors that are caught and silently ignored, overly broad
catches (`except:` / `catch (e) {}`) with no handling, and failures that
return a misleading value instead of raising or reporting.

**Blocking:** any swallowed error with no logging, re-raise, or comment
explaining why ignoring it is safe.

### 7. No dead code

**Check:** commented-out code, unused imports, unused variables, and
functions that nothing calls.

**Blocking:** commented-out blocks of code. Git keeps history, so the file
doesn't need to.
**Suggestion:** unused imports and variables.

### 8. Type information where the language supports it

**Check:** type hints (Python), TypeScript types, or the equivalent on
function signatures and public interfaces.

**Blocking:** public functions with no parameter or return types, in
languages and projects that use them.
**Suggestion:** missing types on private helpers or local variables.

### 9. Match the project's existing style

**Check:** whether the file follows the conventions already in the
project, such as its formatter, import ordering, file layout, and error
patterns.

**Why:** a file that is correct but looks foreign to the codebase creates
friction for every later change.

**Suggestion only:** if the project has a formatter or linter configured,
recommend running it rather than flagging individual style issues by hand.