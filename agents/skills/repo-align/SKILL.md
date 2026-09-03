---
name: repo-align
description: Use when the user asks to align or onboard a repository to coding-agent workflow standards ("align repo", "onboard project", "приведи репо к стандартам", "подготовь проект для агентов"), or when starting recurring agent work in a new repository
---

# Repo Align

## Overview

Five-check audit (C1–C5) that brings a repository to the opencode workflow skeleton: AGENTS.md with verified commands, `.opencode/roadmap.md`, specs/plans folders, conscious `.gitignore` state. Audit reads everything first; fixes happen only after explicit approval. No code-standard, secrets, CI, or test audits — for those, suggest the `ship-gate`, `dependency-auditor`, or `senior-secops` skills after this one finishes.

## When Not to Use

- The user asks about code quality, security, or dependencies — route to the audit skills above.
- One-off question about a single workflow file — just answer it.

## Procedure

1. Run all five checks below in read-only mode. Change nothing during the audit.
2. For C1, detect the stack in this order and stop at the first match:
   `*.sln`/`*.csproj` → `dotnet build <solution>`; `package.json` scripts (`build`, `lint`, `typecheck`, `test`) → run each existing script once; `go.mod` → `go build ./...`; `Cargo.toml` → `cargo check`; `Makefile` → named targets. Long builds are fine; let them finish within a reasonable timeout.
3. Record into Commands only commands that actually exited successfully during step 2. A command you did not run must not appear there.
4. For every ignoring question raised by C4, run `git check-ignore -v` on the candidate paths. Mark items the user has previously declared intentional as `ok (intentional)` without proposing changes. You do not know which entries are intentional, so ASK.
5. Print the report table (format below).
6. Ask one grouped confirmation for all pending fixes. Apply only approved fixes, then update the table and re-print it. Finish with the list of created/changed files.

Never edit `.gitignore`. Never stage or commit anything. Both actions are out of scope even if they look obvious.

## Checks

| # | Check | Status if met | Fix (after confirmation only) |
|---|-------|---------------|-------------------------------|
| C1 | Root `AGENTS.md` exists and its **Commands** section lists verified build/lint/test commands for this stack | Fill per steps 2–3. Create `AGENTS.md` itself only if it does not exist — ask first |
| C2 | `.opencode/roadmap.md` exists | Create it with the stub below |
| C3 | `.opencode/specs/` and `.opencode/plans/` directories exist | Create empty directories |
| C4 | Ignoring state of workflow files is conscious (`AGENTS.md`, `.opencode/*`, `.serena`, `.token-optimizer`, IDE folders) | Show `git check-ignore -v` results, ask which are intentional, change nothing on your own |
| C5 | Global workflow rules exist (task briefing, exploration delegation, repeat→skill, commands habit) | Informational only — these live in global config. State `n/a` plus a reminder line |

Statuses: `ok` · `fix` (applied after approval) · `question` (needs user decision) · `ok (intentional)` · `n/a`.

## Report Format

```
| # | Check                          | Status      | Action                        |
|---|--------------------------------|-------------|-------------------------------|
| C1| AGENTS.md Commands             | ok          | —                             |

Files created/changed: ...
Dry-run result: CLEAN if every check resolves to ok/ok(intentional)/n-a without pending questions.
```

Always end with a one-line verdict: CLEAN or the number of open items.

## Roadmap Stub (C2)

```markdown
# Roadmap

Everything deferred, postponed, or planned-but-not-started. Add items with a date and a pointer to the source file.

## Pending

## Done
```

## Common Mistakes

- Proposing to track or un-ignore files that the user ignores deliberately (for example `AGENTS.md` in `.gitignore`). Ignore-state can be intentional; ask, do not assume team sharing is the goal.
- Writing a command into Commands that you have not executed. Unverified commands break later sessions silently.
- Drifting into secrets, cache files, CI, or code-style findings mid-audit. Note the suggestion in one line, stay inside C1–C5.
- Fixing while auditing. All edits come after the confirmation step.
