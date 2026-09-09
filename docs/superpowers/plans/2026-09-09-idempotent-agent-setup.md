# Idempotent Agent Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the agent setup scripts safe to repeat, with explicit mutation, non-destructive checks, and no accidental deletion or privilege escalation.

**Architecture:** `first.sh` becomes the root-owned system reconciler. It supports a read-only check mode and an explicit apply mode. `second.sh` becomes the user-facing orchestrator: it validates mounts and permissions, then invokes `setup.sh` only when explicitly requested. `setup.sh` remains user-scoped and reconciles user tools/configuration without sudo or root-owned writes.

**Tech Stack:** Bash, systemd, DrvFs, APT, Git, ACL, npm, Bun, UV, .NET CLI.

**Spec:** No separate design document; this plan records the approved design from the session.

## Global Constraints

- `/etc/agent-setup.conf` is the single shared non-secret configuration file.
- `agent` MUST NOT receive sudo, wheel, docker, lxd, libvirt, disk, shadow, adm, or kvm membership.
- `setup.sh` MUST run as `SECOND_USERNAME` and MUST NOT invoke `sudo`.
- `first.sh` MUST be the only script that changes system packages, system time-zone files, systemd units, ACLs, ownership, or mount targets.
- `second.sh` MUST NOT delete a pre-existing user file on `/mnt/d`.
- Existing tests are not added or modified; verification uses `bash -n`, shell smoke checks, diff checks, and isolated temporary fixtures.
- The existing modified submodule `omp/extensions/superpowers` MUST remain outside commits.

---

### Task 1: Define explicit script modes

**Files:**
- Modify: `agent-user-setup/first.sh`
- Modify: `agent-user-setup/second.sh`
- Modify: `agent-user-setup/setup.sh`

**Interfaces:**
- `first.sh check` performs read-only validation.
- `first.sh apply` performs system changes.
- `second.sh check` performs read-only user checks and does not invoke `setup.sh`.
- `second.sh apply` performs checks and invokes `setup.sh apply`.
- `setup.sh check` validates user tools and config files without network or writes.
- `setup.sh apply` installs/reconciles user tools and writes user config.
- No argument defaults to `check` in all three scripts. This makes accidental reruns non-destructive.

- [ ] **Step 1: Add strict argument parsing**

Accept exactly `check` or `apply`; reject every other value with exit status 2 and a short usage message. Do not use a silent default to `apply`.

```bash
MODE="${1:-check}"
case "${MODE}" in
  check|apply) ;;
  *) printf 'Usage: %s [check|apply]\n' "$0" >&2; exit 2 ;;
esac
```

- [ ] **Step 2: Separate mutation from validation**

Keep validation functions callable from both modes. Guard every mutating function with `[[ ${MODE} == apply ]]`; in `check` mode print the required state and return without changing it.

- [ ] **Step 3: Verify mode behavior**

Run:

```bash
bash -n agent-user-setup/first.sh agent-user-setup/second.sh agent-user-setup/setup.sh
agent-user-setup/first.sh invalid >/tmp/agent-setup-invalid.out 2>&1; test $? -eq 2
```

Expected: all scripts parse; invalid mode is rejected; no system command runs in the argument-error path.

---

### Task 2: Make `first.sh` a safe system reconciler

**Files:**
- Modify: `agent-user-setup/first.sh`
- Modify: `agent-setup.conf.example` only if a new mode-related variable is required; prefer no new variable.

**Interfaces:**
- `check` reports missing users, groups, packages, mount options, source directories, target directories, service files, ACL state, and sudo state.
- `apply` performs the current system setup.
- Re-running `apply` must not prompt for a password when `SECOND_USERNAME` already exists.

- [ ] **Step 1: Make user creation non-interactive on repeat**

Keep `useradd` only in the missing-user branch. Do not call `passwd` for an existing user. If a new user is required, preserve the current explicit password step and print that it is the only interactive operation.

- [ ] **Step 2: Make the APT mirror rewrite converge**

Before rewriting sources, recognize both official URLs and the configured mirror. Keep `.orig` creation guarded by `[[ -e "${f}.orig" ]]`. A second `apply` must not rewrite the configured mirror into a different value or create `.orig.orig`.

- [ ] **Step 3: Move system checks behind mode guards**

`check` may run `apt-cache`, `command -v`, `findmnt`, `systemctl is-enabled`, and `stat`. It MUST NOT run `apt-get update`, `apt-get install`, `apt-get clean`, `chown`, `chmod`, `setfacl`, `umount`, `mount`, `systemctl enable`, or `systemctl start`.

- [ ] **Step 4: Make ACL application conditional**

Add a read-only comparison for each allowed source directory. In `check`, report drift. In `apply`, retain the existing ACL/ownership operations. Do not recursively change unrelated files outside the configured allowlist.

- [ ] **Step 5: Make mount handling non-destructive by default**

In `check`, report mounted/unmounted targets. In `apply`, unmount only a target that is one of the configured mount targets and only when it is mounted at that exact target. Do not unmount arbitrary mounts. The generated mount service must retain the existing `mountpoint` guard, so a repeated service start is a no-op.

- [ ] **Step 6: Make generated files converge**

Use a temporary file plus `install`/`mv` only when content differs for `/usr/local/sbin/agent-wsl-mounts` and `/etc/systemd/system/agent-wsl-mounts.service`. Preserve owner and modes. Avoid changing timestamps on every run when content is unchanged.

- [ ] **Step 7: Verify `first.sh` without applying it**

Run:

```bash
bash -n agent-user-setup/first.sh
sudo agent-user-setup/first.sh check
```

Expected: validation output only; no APT transaction, no ACL mutation, no unmount, no systemd start.

---

### Task 3: Make `second.sh` non-destructive and explicit

**Files:**
- Modify: `agent-user-setup/second.sh`

**Interfaces:**
- `second.sh check` validates current user, shared config, DrvFs visibility, `/mnt/d` write access, and configured bind targets.
- `second.sh apply` runs the same checks, then invokes `setup.sh apply` from `SECOND_USERNAME`.

- [ ] **Step 1: Remove destructive `/mnt/d/test` behavior**

Replace the fixed path with a unique temporary file and an exit trap, or use a dedicated test directory configured for this purpose. The preferred implementation is:

```bash
test_file="$(mktemp /mnt/d/.agent-write-test.XXXXXX)"
trap 'rm -f -- "${test_file}"' EXIT
printf 'ok\n' >"${test_file}"
printf 'Write access confirmed\n'
```

The script MUST never remove a path chosen before the script starts.

- [ ] **Step 2: Separate validation from setup invocation**

Keep mount and permission checks in a function. Call `bash setup.sh check` for `second.sh check`; call `bash setup.sh apply` only for `second.sh apply`.

- [ ] **Step 3: Avoid forced shell replacement**

Remove `exec bash` from the default flow. It hides the exit status and makes automation difficult. Print the command to refresh the environment instead:

```bash
printf 'Run: source ~/.bashrc\n'
```

- [ ] **Step 4: Verify safe checks**

Run as `agent`:

```bash
bash agent-user-setup/second.sh check
```

Expected: no package installation, no user config writes, no deletion of an existing `/mnt/d` path, and a non-zero result only when the environment is actually invalid.

---

### Task 4: Make `setup.sh` converge user state

**Files:**
- Modify: `agent-user-setup/setup.sh`

**Interfaces:**
- `check` performs no network access and no writes.
- `apply` installs or updates user tools and writes only inside the current user's home directory.
- The script remains unusable by root and by users other than `SECOND_USERNAME`.

- [ ] **Step 1: Add read-only checks**

For `check`, verify command availability and expected config contents with `command -v`, `test`, and `grep`. Do not run Bun, UV, .NET, npm, or Git installers.

- [ ] **Step 2: Make user config writes content-aware**

Write `pip.conf`, `uv.toml`, and the managed `.bashrc` block to temporary files, compare with existing content, and replace only when different. Keep the block delimited by the existing `DEV ENV BLOCK` markers.

- [ ] **Step 3: Make tool installation explicit**

For `apply`, keep the existing update-or-install behavior for dotnet tools. Run npm and Bun installs only in `apply`. Do not add `sudo`, `sudo -H`, or writes to `/usr/local`.

- [ ] **Step 4: Verify repeat behavior**

Run as `agent` in a disposable HOME fixture where network tools are mocked or unavailable:

```bash
HOME="$(mktemp -d)" bash agent-user-setup/setup.sh check
```

Expected: check exits with a clear missing-tools report and leaves the fixture unchanged. Run `stat`/`sha256sum` before and after to verify no writes.

---

### Task 5: Add an idempotency smoke harness

**Files:**
- Create: `agent-user-setup/check-idempotency.sh`
- Modify: `agent-user-setup/README` only if an existing README is present; do not create documentation outside the requested plan unless execution approves it.

**Interfaces:**
- The harness runs static and dry-run checks only; it never applies system changes.
- It accepts the repository path as an optional argument and exits non-zero on syntax, forbidden sudo, fixed destructive path, or dirty dry-run behavior.

- [ ] **Step 1: Check shell syntax and forbidden operations**

Validate all scripts with `bash -n`. Reject `sudo` in `second.sh` and `setup.sh`. Reject fixed writes/removals such as `/mnt/d/test`, `rm -rf`, and unconditional `exec bash`.

- [ ] **Step 2: Check shared configuration references**

Verify that all three scripts source `/etc/agent-setup.conf` and that the example defines `APT_MIRROR`, `PYPI_MIRROR`, `NPM_REGISTRY`, and `TZ_VALUE`.

- [ ] **Step 3: Run the harness**

```bash
bash agent-user-setup/check-idempotency.sh
```

Expected: exit 0 with a concise report of each check.

---

### Task 6: Review, commit, and hand off

**Files:**
- Modify only files listed in Tasks 1–5.

- [ ] **Step 1: Run final verification**

```bash
bash agent-user-setup/check-idempotency.sh
git diff --check
git status --short --branch
```

Expected: all checks pass; the existing `omp/extensions/superpowers` submodule change remains unstaged.

- [ ] **Step 2: Review the diff**

Confirm that:

- no script grants sudo to `agent`;
- no user script calls sudo;
- no fixed `/mnt/d/test` path is deleted;
- check modes do not mutate the system;
- apply modes are the only mutation path;
- `/etc/agent-setup.conf` remains non-secret.

- [ ] **Step 3: Create one local commit**

```bash
git add agent-user-setup
git commit -m "refactor(agent-setup): make setup scripts idempotent"
```

Do not push, merge, rebase, or stage the unrelated submodule change.
