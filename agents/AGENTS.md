# Global Rules

Global rules for agents, applied across all sessions.

## NO TESTS BY DEFAULT: Tests Are a Separate Task

**Do NOT write tests as part of regular implementation work. No TDD. By default, code ships without tests.**

- Implementation, refactoring, and bug fixes are done WITHOUT writing tests. Do not add, extend, or update test files during normal tasks.
- TDD (write the failing test first) is NOT used. Write the code directly.
- Tests are only written as a **separate, explicitly requested task** (e.g. "write tests for X", "coverage task"). When such a task is requested, it is its own dedicated effort with its own commit.
- Existing tests: do not touch them and do not run them without an explicit request. Keep them compiling and passing only when a change forces it. If existing tests become outdated/invalid and there is no explicit request to maintain them, comment out the whole test file instead of updating or deleting it piecemeal.
- Rationale: the current ~100+ tests are largely useless busywork. Effort goes into features and correctness, not into maintaining low-value tests.
- Exception: if a change would BREAK existing tests, update those tests so the suite stays green — but do not add new ones.

## Thinking & Coding Guidelines

THINK IN ENGLISH

### 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

These guidelines are working if: fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.



## Workflow Rules

- **Task briefing**: Before you start a task, make sure that all four elements are known: goal and definition of done; files/modules in scope (and out of scope); constraints; acceptance criteria. If an element is missing, infer it from context, show your summary, and wait for confirmation before you write code. Exception: trivial one-line fixes.
- **Delegate exploration**: When search would touch more than ~3 locations, dispatch the `scout` subagent and use its summary. Keep the main session context focused on the task, not on raw file listings.
- **Record verification commands**: On the first substantial task in a repository, make sure that its AGENTS.md has a Commands section (build/lint/test). If absent, find the commands once, write them there, then continue.
- **Repeat → Skill**: If the user repeats the same request pattern twice, propose capturing it as a skill under `C:\Users\koposov\.config\opencode\skills\`.

## Commit Messages

All Pallas repos (`pallas-web`, `ks-sechero-app`) use **Conventional Commits**: `<type>(<scope>): <subject>` per Conventional Commits 1.0.0.

- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Scope is the touched area: module or layer name (e.g. `catalog`, `actions`, `identity`, `gitlab`, `ingestion`, `api`, `web`, `infra`).
- Subject: English, imperative mood, starts lowercase, no trailing period — "feat(catalog): add team sync command".
- Breaking changes: `!` after the scope (`feat(api)!: ...`) or a `BREAKING CHANGE: <description>` footer.

## Git Push/Merge

The user always pushes and merges (and creates PRs) themselves — never push, merge, rebase against remote, or open PRs on their behalf. Commit locally and hand off.

## Documentation Locations

Global rule about where documentation for tools and libraries used during development is stored.

- All documentation about third-party tools and libraries is stored in `/mnt/d/data/agent/DOCS`, if it's not there, ask user new location and edit this line.
- All repository codebases of third-party tools and libraries in `/mnt/d/data/agent`, if it's not there, ask user new location and edit this line.
- Inside `DOCS`, each folder is named after the tool/library (e.g. `DOCS/Quartz`, `DOCS/TickerQ`).
- When documentation about a specific tool/library is needed, look in the corresponding folder in `DOCS` first, before searching the internet or asking the user.
- If the documentation for the needed tool is not in `DOCS`, you may tell the user that the folder is missing.

Examples:

- Question about a library API → look for ready examples/notes in its folder inside `DOCS`, rather than re-asking the user.
