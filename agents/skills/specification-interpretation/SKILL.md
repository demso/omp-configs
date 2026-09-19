---
name: specification-interpretation
description: "Use when a task request is vague, ambiguous, or internally contradictory - surface implicit assumptions, gaps, and contradictions, and ask batched clarifying questions BEFORE acting. Not for new-feature design (use brainstorming for that)."
---

# Specification Interpretation

Tactical clarification for in-session tasks. For new features, new subsystems, or
architectural design, use `brainstorming` instead - this skill is for ambiguous
execution requests inside an already-defined project.

## When to trigger

Run this checklist on each new task request. Trigger if ANY holds:

- Vague qualitative terms with no metric: "сделай быстрее", "улучши", "оптимизируй", "рефактори", "почини".
- Scope missing: no file/module/component/function named, and repo search does not make it obvious.
- Multiple defensible interpretations exist (the AGENTS.md rule: several solutions possible → stop and ask).
- Implicit contradiction: stated goals are in tension ("simple UI" + 20 features; "fast" + heavy real-time animation).
- Missing unhappy path: the request describes only the happy path and error behavior is not inferable from the codebase.

Do NOT trigger for: precise single-file edits, mechanical renames, commands with exact parameters, follow-up messages in an already-clarified thread.

## Procedure

1. **Scan the codebase first.** Existing conventions answer most "unspecified"
   details: naming, error handling, validation patterns, similar features. Only ask
   what the codebase cannot answer.
2. **Classify stakes.**
   - **Low-stakes** (cosmetic, single-file, reversible): state your assumption,
     propose a default, and proceed unless the user objects. One inline question maximum.
   - **High-stakes** (data loss risk, API contract change, shared module, migration):
     hard gate - ask before touching code.
3. **Detect contradictions.** If requirements conflict, surface the conflict explicitly
   and ask the user to choose. NEVER silently resolve a contradiction by your own judgment.
4. **Batch questions.** Up to 3, one message. Each question names a concrete scenario
   and offers options or a default:
   - Bad: "уточните требования?"
   - Good: "При истёкшей сессии сохранить введённые данные и редиректнуть на логин,
     или показать ошибку? По умолчанию сделаю первое."
5. **Ask in the user's language** (Russian for this user).

## Output contract

When triggered, reply in exactly this shape (omit empty sections):

```
**Понимание задачи:** <restatement in 1-2 sentences>
**Предположения:** <bullet list, each with planned default>
**Противоречия:** <conflicting requirements, if any>
**Вопросы:** <≤3 batched, with defaults>
```

For low-stakes tasks the contract shrinks to one line:
`Делаю X (предполагаю Y; скажите, если иначе).` - then act.

## Anti-patterns

- **Assumption avalanche**: building the whole solution on unvalidated guesses.
- **Question avoidance**: guessing to appear capable; a wrong guess costs more than a question.
- **Interrogation**: asking what the codebase already answers; asking about cosmetics
  before architecture.
- **Scope inflation**: "добавь фильтр по дате" is not a request for a full filtering system.
- **Re-asking**: after the user answers, record the answers and act - do not re-litigate
  settled decisions later in the session.

## After clarification

Merge answers into the working context and proceed immediately (update todos/plan if one
exists). This skill ends where execution begins.
