# Security Standards

This file is the rulebook for the security reviewer. The goal is code that
an outsider can't tamper with, eavesdrop on, or trick into leaking data.
Each rule says what to check, why it matters, and where the line is.

If a project has its own `.pipeline/security.md`, that file takes
precedence over this one wherever they conflict.

## Severity

Security uses the same two severities as `standards.md`:

- **blocking**: a real or likely vulnerability. The file does not pass
  until it is fixed.
- **suggestion**: hardening that would help but isn't required.

**Uncertainty works differently here than in standards.** A missed
vulnerability costs far more than an extra fix cycle. When you can't tell
whether something is exploitable:

- If the fix is small and safe (switching to a parameterized query, turning
  certificate verification back on), mark it **blocking**.
- If the fix would be a larger change, mark it **suggestion** and ask for
  escalation (see the end of this file).

## Scope

Review the file in front of you. You may read other files to understand
how this one is used (where its inputs come from, where its outputs go),
but report only issues in this file. If the file depends on something
unsafe elsewhere, mention it in the summary so the manager can follow up.

---

## Core rules

### 1. No secrets in code

**Check:** API keys, tokens, passwords, private keys, connection strings
with credentials, or signing secrets written into the source. That
includes test files, example configs, default arguments, and comments.

**Why:** anything in source control should be treated as public. Once a
key is committed, it lives in git history even after the line is deleted,
and leaked keys are found and abused quickly.

**Where the line is:**
- Blocking: any real-looking secret value in the code. Treat long random
  strings and values with known prefixes (`sk-`, `ghp_`, `AKIA`,
  `-----BEGIN PRIVATE KEY-----`) as real unless the code makes clear they
  are placeholders.
- Not a violation: obvious placeholders (`"your-api-key-here"`,
  `"<TOKEN>"`), and reading secrets from environment variables or a
  secrets manager.

**Fix direction:** load the secret from an environment variable or the
project's secrets mechanism, and fail with a clear error if it's missing.
If a real key was committed, say in the summary that **the key must be
rotated**. Removing it from the code is not enough.

### 2. No secrets leaking at runtime

**Check:** secrets or sensitive data reaching places outsiders can see:
logs, error messages, exception text, URLs and query strings, API
responses, or files written to disk.

**Why:** a key that never appears in source can still leak through a
debug log line or a stack trace returned to a user.

**Where the line is:**
- Blocking: logging or printing a secret, a full auth header, or a
  request/response object that contains one; putting a key in a URL query
  string; returning internal error details (stack traces, file paths,
  queries) to an external caller.
- Suggestion: logging more user data than the task needs.

**Fix direction:** log that a credential was used, never its value. If
an identifier is needed for debugging, mask it (`sk-...a4f2`). Return
generic errors to callers and keep the details in server-side logs.

### 3. Encrypted, verified connections (MITM prevention)

**Check:** network traffic that can be read or changed in transit.

- Plain `http://` or `ws://` for anything other than localhost.
- Certificate verification turned off: `verify=False` (Python requests),
  `rejectUnauthorized: false` (Node), `InsecureSkipVerify: true` (Go),
  `ssl._create_unverified_context`, custom trust-all certificate
  handlers, or turning off hostname checking.
- Outdated TLS versions forced explicitly (SSL, TLS 1.0, TLS 1.1).
- Downloading code, scripts, or update files without checking a checksum
  or signature.

**Why:** an attacker on the same network (public Wi-Fi, a compromised
router) can read or rewrite unencrypted traffic. With verification off,
encryption doesn't help, because the attacker can present their own
certificate and the code will accept it.

**Where the line is:**
- Blocking: any of the above in code that runs outside a local
  development setup. Turned-off verification is blocking even when a
  comment says it's temporary.
- Suggestion: `http://localhost` and other local-only endpoints, as long
  as they can't be pointed at a remote host by configuration.

**Fix direction:** use `https://` and `wss://`, and leave certificate
verification on (it's the default in almost every library). If a
private certificate authority is needed, configure it as a trusted CA
rather than turning verification off.

---

## Additional rules

These go beyond the core list. Delete any you don't want.

### 4. Injection

**Check:** untrusted input (user input, request data, file contents, data
from external APIs) assembled directly into something that gets executed
or interpreted:

- SQL built with string formatting or concatenation.
- Shell commands built from input, or `shell=True` with input involved.
- `eval`, `exec`, `Function()`, or template rendering of input.
- HTML built from input without escaping (cross-site scripting).

**Why:** injection lets an attacker run their own queries, commands, or
scripts with your program's permissions. It's one of the most common and
most damaging kinds of vulnerability.

**Blocking:** any of the above where the input could come from outside
the program. **Fix direction:** parameterized queries, passing command
arguments as a list instead of a shell string, and the framework's
built-in escaping.

### 5. Unsafe file paths

**Check:** file paths built from input without checking where they end
up, so `../../etc/passwd` or an absolute path could reach files outside
the intended folder. This also covers extracting archives without
checking entry paths.

**Blocking:** input-controlled paths with no check that the resolved path
stays inside the allowed directory.

### 6. Unsafe deserialization

**Check:** loading untrusted data with formats that can run code:
`pickle`, `yaml.load` without a safe loader, `marshal`, Java object
streams, and similar.

**Blocking:** any of these on data that could come from outside the
program. **Fix direction:** JSON, or the format's safe loader
(`yaml.safe_load`).

### 7. Authentication and authorization

**Check:** endpoints or functions that act on data or change state
without confirming who the caller is and that they're allowed to do it.
Watch especially for checks that trust client-supplied values (a
`user_id` or `is_admin` field in the request body).

**Blocking:** a missing or bypassable permission check on anything that
reads private data or makes changes.

### 8. Weak cryptography and randomness

**Check:**
- Passwords stored in plain text or with fast hashes (MD5, SHA-1, plain
  SHA-256) instead of a password hashing function (bcrypt, scrypt,
  Argon2).
- Tokens, session IDs, or reset codes generated with a non-secure random
  generator (`random`, `Math.random`).
- Hand-written encryption, or encryption keys and IVs that are hardcoded
  or reused.
- Comparing secrets with `==` instead of a constant-time comparison.

**Blocking:** any of these on passwords, tokens, or keys.

### 9. Input validation and limits

**Check:** external input used without checking its type, size, or
range: unbounded uploads or request bodies, unlimited loops or retries
driven by input, and regexes that can be made to run for a very long time
on crafted input.

**Blocking:** missing validation that could crash the program or make it
hang. **Suggestion:** other missing validation.

### 10. Server-side request forgery (SSRF)

**Check:** code that fetches a URL supplied by a user. An attacker can
point it at internal services or cloud metadata addresses
(`169.254.169.254`) that should never be reachable from outside.

**Blocking:** fetching arbitrary user-supplied URLs with no allow-list or
check for internal addresses.

### 11. Dependencies

**Check:** new dependencies added by this file or its package manifest:
unpinned versions, packages with names suspiciously close to popular ones
(typosquatting), and installs from unusual sources.

**Suggestion only:** you can't check vulnerability databases from here,
so flag what looks risky and recommend running the ecosystem's audit tool
(`npm audit`, `pip-audit`, `cargo audit`).

### 12. Web-specific settings

Only for files that serve web traffic. **Check:**
- Cookies holding sessions or tokens without `Secure`, `HttpOnly`, and a
  `SameSite` setting.
- CORS that allows any origin (`*`) together with credentials.
- State-changing requests with no CSRF protection.
- Debug mode turned on in production configuration.

**Blocking:** any of these on endpoints that handle logged-in users.

---

## Asking for escalation

Some files deserve a stronger model even when nothing looks wrong. End
your summary with a sentence starting with `Escalate:` when either of
these is true:

- The file handles authentication, cryptography, payments, permissions,
  parsing of untrusted file formats, or anything else where subtle bugs
  are dangerous.
- You found something that might be a vulnerability, but you couldn't
  confirm it.

Example: `Escalate: this file implements session token validation, which
needs a closer look than this tier can give it.`

The manager uses this sentence to decide whether to re-run the review at
a higher tier. Leave it out when neither condition applies.