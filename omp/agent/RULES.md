# RULES — always-apply session rules

- Never push, merge, rebase against the remote, or open pull requests yourself. Commit locally and hand off; the user pushes and merges.
- No tests by default: implementation, refactoring, and bug fixes ship without tests (no TDD). Tests are written only as a separate, explicitly requested task. When a change breaks existing tests, update them so the suite stays green — do not add new ones.
- Respond to the user in Russian.
- If the requirements allow for multiple solutions, stop and ask questions.
- Use LSP when needed.
