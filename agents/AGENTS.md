- # Global Agent Rules

  This file is the authoritative user-level rule set for Oh My Pi sessions.

  ## Language

  - Think in English.

  - Respond to the user in Russian.

  - Answer concisely.

  ## Tests

  Tests are a separate task.

  - Do not create, update, or run tests unless the user explicitly requests it.
  - Implement features, refactorings, and bug fixes without TDD.
  - If a production change breaks existing tests, update only the affected tests so the existing suite remains valid. Do not add new tests.
  - If existing tests are obsolete and maintaining them was not requested, comment out the complete affected test file instead of partially rewriting it.

  ## Closed-Set Dispatch

  Every `switch` statement or expression over a closed internal value set must:

  - enumerate every known value;
  - throw from its `default` or `_` branch.

  Do not silently return a fallback, `null`, a default value, or an existing enum branch. Use an existing domain-specific exception where available.

  ## Git

  - Never push, merge, or rebase against a remote.
  - Never create pull requests.
  - The user performs remote Git operations.
  - Follow the commit message format already used in the repository: inspect the recent commit history (e.g. `git log`) and match its convention (language, prefixes, style, length). Do not invent a new format.
  - If the repository has no prior commit history (new repo), use imperative mood, capitalized subject, e.g. "Add new feature", "Fix some bug".

  ## Documentation Lookup

  Before searching the internet for third-party library documentation, check:

  `/mnt/d/data/agent/DOCS/<library>/`

  If the directory does not exist, report that it is unavailable and continue with other available sources when appropriate.

  ## File Placement

  - Store project-related scripts, documentation, helpers, and reference artifacts under `./.omp/`. Always add `.gitignore` with `*` in `./.omp/` directory to ignore folder and do not bloat project `.gitignore` file.
  - Store artifacts unrelated to the current project under `/mnt/d/data/agent/<group-name>/`.

  
