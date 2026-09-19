---
name: finishing-a-development-branch
description: Use when implementation is complete and the work must be handed off for integration - report verification state, commit, present handoff options, clean up on request. The user performs all merges, pushes, and PRs.
---

# Finishing a Development Branch

## Overview

**Core principle:** Report verification state → Detect environment → Hand off to the user → Clean up on request.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

**Local policy overrides (this user's environment):**
- The user performs ALL merges, pushes, rebases, and PR creation. This skill never
  executes them — it hands off with exact commands for the user.
- No test-suite runs unless the user explicitly requested tests in this session.

## Step 1: Report Verification State

Run the project's full test suite (`npm test` / `cargo test` / `pytest` / `go test ./...`) **only if the user explicitly requested tests in this session.**

- **If tests were requested and fail**, report the failures and stop — the menu comes after a green suite.
- **If tests were requested and pass:** continue to Step 2.
- **If tests were NOT requested:** do not run them. State exactly what verification
  WAS done this session (build, typecheck, lint, smoke-run, reproduction check) and
  that the suite was not run, then continue to Step 2:

```
Verification done: <build/lint/smoke evidence>
Test suite: not run (not requested this session)
```

## Step 2: Detect Environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
# Capture now, while still inside the workspace — Step 5 changes directory
# before cleanup (Step 6) needs this value
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

This determines which menu to show and how cleanup works:

| State | Menu | Cleanup |
|-------|------|---------|
| `GIT_DIR == GIT_COMMON` (normal repo) | Standard 3 options | No worktree to clean up |
| `GIT_DIR != GIT_COMMON`, named branch | Standard 3 options | Provenance-based (see Step 6) |
| `GIT_DIR != GIT_COMMON`, detached HEAD | Reduced 2 options (no merge) | Externally managed — leave in place |

## Step 3: Determine Base Branch

The base branch is whatever this work forked from — usually named in the
plan, the conversation, or the branch's upstream. If it is not already
known, ask: "This branch split from <your best guess> - is that correct?"
Confirm before merging: merging into the wrong base is expensive to undo.

## Step 4: Present Options

Integration is the user's job — never merge, push, or open a PR yourself.
Present exactly these options:

```
Implementation complete. What would you like to do?

1. Hand off — I commit anything pending and give you the exact merge/push commands to run yourself
2. Keep the branch as-is, no handoff yet
3. Clean up the workspace (only after you confirm the work is integrated)

Which option?
```

Present the menu exactly as written — concise. Discarding the work happens
only in response to your human partner explicitly asking for it (see "If
your human partner asks to discard the work" below). Wait for their answer.

## Step 5: Execute Choice

### Option 1: Hand Off

Commit any pending changes (the user may ask you to generate the message).
Then report the handoff block:

```
Branch:        <feature-branch>
Base branch:   <base-branch>
Commits ahead: <git log <base>..HEAD --oneline>
Worktree:      <WORKTREE_PATH>
Verification:  <what was actually run and its result>

To integrate, run yourself:
  git checkout <base-branch>
  git merge <feature-branch>
  git push            # if you want it on the remote
```

From a detached HEAD, instead suggest:
`git push origin HEAD:refs/heads/<new-branch>` — executed by the user.

### Option 2: Keep As-Is

Report: "Keeping branch <name>. Worktree preserved at <path>."

### Option 3: Clean Up After Confirmed Integration

Prerequisite: the user confirmed the work landed (merged/pushed by them).
Ask for that confirmation if it has not been given. Then run Step 6 and,
if the branch is fully merged, delete it:

```bash
git branch -d <feature-branch>
```

### If your human partner asks to discard the work

This path exists only as a response to an explicit request to throw the
work away. Confirm first:

```
This will permanently delete:
- Branch <name>
- All commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for that exact confirmation. When it arrives:

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
```

Then clean up the worktree (Step 6) and force-delete the branch:

```bash
git branch -D <feature-branch>
```

## Step 6: Cleanup Workspace

**Runs for Option 3 (integration confirmed by the user) and confirmed
discards.** Options 1 and 2 always preserve the worktree. Callers have
already changed directory to the main repo root — worktree removal must
run from outside the worktree — and use the
`GIT_DIR`/`GIT_COMMON`/`WORKTREE_PATH` values captured in Step 2, from
before that directory change.

**If `GIT_DIR == GIT_COMMON`:** Normal repo, no worktree to clean up. Done.

**If `WORKTREE_PATH` is under `.worktrees/` or `worktrees/`:** Superpowers
created this worktree — we own cleanup:

```bash
git worktree remove "$WORKTREE_PATH"
git worktree prune  # Self-healing: clean up any stale registrations
```

**If removal is refused** (`contains modified or untracked files`): the
worktree holds files that exist nowhere else — uncommitted plans, notes,
or scratch work. Never `--force` on your own initiative. Show your human
partner what is at stake and ask:

```bash
git -C "$WORKTREE_PATH" status --porcelain -uall
```

```
Worktree removal refused — these files were never committed:

<file list>

1. Commit them to <branch> before cleanup
2. Move them into <main repo root>
3. Delete them (unrecoverable)

Which?
```

Carry out the choice, then remove the worktree.

**Otherwise:** The host environment owns this workspace — leave it in
place. If your platform provides a workspace-exit tool, use it.

## Quick Reference

| Option | Commit | Handoff Commands | Keep Worktree | Cleanup |
|--------|--------|------------------|---------------|---------|
| 1. Hand off | yes | printed for user | yes | - |
| 2. Keep as-is | - | - | yes | - |
| 3. Cleanup after confirmed integration | - | - | - | yes |
| Discard (explicit request only) | - | - | - | yes (force) |

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Tests passed earlier this session" | If the user requested tests, run the suite on the tree you are handing off. A green run only proves the tree it ran on. |
| "The suite was never run — I'll say 'tested'" | State exactly what verification ran. An unrun suite is reported as not run, never implied. |
| "They obviously want it merged" | Integration is your human partner's job AND decision. Print the commands; they run them. |
| "A quick local merge is harmless" | The user performs all merges and pushes. Hand off instead. |
| "They seem done with this feature — I'll offer to discard it" | The menu is complete as written. Discard happens only when your human partner asks for it in so many words. |
| "'Yeah, get rid of it' counts as confirmation" | Only the typed word `discard` authorizes deletion. |
| "The user merged it, so the worktree is clutter now" | Cleanup runs only via Option 3 after explicit confirmation. |
| "This other worktree looks stale — I'll clean it too" | Clean up only worktrees under `.worktrees/` or `worktrees/`. Everything else belongs to the host. |
| "Removal refused — `--force` is just finishing the cleanup" | The refusal means files exist only in that worktree. `--force` destroys them permanently. Show your human partner and ask. |
| "The base branch is obviously main" | Confirm the fork point or ask. A handoff naming the wrong base sends the user to merge into the wrong place. |
