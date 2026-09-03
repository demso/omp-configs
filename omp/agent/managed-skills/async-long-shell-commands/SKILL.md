---
name: async-long-shell-commands
description: "Run long shell commands (typecheck, build, test suites) async via bash async:true and collect with hub wait, so incoming messages never background the turn"
---

# Long shell commands: run async, never foreground

## Symptom
A foreground `bash` call longer than ~30–60 s (typechecks, production builds, test suites) gets **auto-backgrounded the moment any incoming message arrives**, and the turn appears to "hang" from the user's view. Users notice and interrupt ("чего завис").

## Procedure
1. **Predict** long commands: `svelte-check`, `vite build`, full test suites, installs. This repo: `pnpm check` ≈ 1.5–2.5 min, `pnpm build` ≈ variable but > 15 s.
2. **Run them deliberately async** from the start: `bash` with `async: true`.
3. **Collect** the result with `hub` `op: "wait"`, `ids: ["bg_<n>"]`, generous `timeoutMs` (e.g. 300000). Output arrives in the snapshot; no polling loops.
4. While waiting, do independent parallel work (reads, docs edits) — never idle.
5. If a command did get auto-backgrounded anyway, do NOT re-run it foreground: wait on the job or cancel it (`hub` `op: "cancel"`) and relaunch async.

## Notes
- `hub` wait errors if `op` is missing — always pass `op: "wait"` explicitly.
- Verifying a build/deploy artifact: prefer filesystem evidence (fresh mtimes in the output dir) over parsing truncated `tail` output.
