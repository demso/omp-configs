---
name: jev
description: Use TypeSafe Jev (System One) via the 'jev' subagent for fast, typed, calibrated decisions (yes/no probabilities, option choices, rubric scores) without prose or slow LLM reasoning.
---

# TypeSafe Jev (System One) Decision Layer

Jev evaluates typed questions against a state and returns structured, calibrated results directly (probabilities, option distributions, rubric scores). It does not generate text, explanations, or code.

When you need a model to make a judgment that code will branch on, sort by, or route with, dispatch the **`jev` subagent**.

---

## When to Use `jev`

- **Binary verification (Noul)**: "Is this test output relevant to the defect?", "Does this commit touch shared infrastructure?"
- **Categorization / Routing (Choice)**: "Which subsystem owns this bug?", "What kind of failure is this log reporting?"
- **Severity / Quality Rubrics (Score)**: "Rate the blast radius of this change (None / Low / Medium / High)", "Rate test coverage thoroughness"
- **Confidence-gated decisions**: Act automatically when `confidence >= 0.85`, route to human or deeper LLM analysis when confidence is lower.
- **Do NOT use for**: Text generation, code writing, step-by-step reasoning, or summarizing.

---

## How to Dispatch `jev`

Call the `task` tool with `agent: "jev"`. Pass a JSON payload as the `task` text containing `state` and an array of `questions`:

```json
{
  "tasks": [
    {
      "agent": "jev",
      "task": "{\"state\": \"<text, code, diff, or log to evaluate>\", \"questions\": [{\"id\": \"is_bug\", \"type\": \"noul\", \"instructions\": \"Does this log indicate a software bug?\"}]}"
    }
  ]
}
```

### The Three Question Primitives

#### 1. Noul (Yes/No Probability)
Returns the calibrated probability `noul` (0.0 to 1.0) that the statement is true.

```json
{
  "id": "is_urgent",
  "type": "noul",
  "instructions": "Does this message express urgent time sensitivity?"
}
```

#### 2. Choice (Select One Option)
Picks one option from a defined set. Returns `choice`, `confidence`, and `probabilities` across all options.

```json
{
  "id": "failure_class",
  "type": "choice",
  "instructions": "What kind of failure is being reported?",
  "options": [
    { "name": "transient", "description": "Network or temporary service hiccup" },
    { "name": "environment", "description": "Missing dependency, tool, or port" },
    { "name": "code_bug", "description": "Syntax, type, or logic error" },
    { "name": "permission", "description": "Access or permission denied" }
  ]
}
```

#### 3. Score (Ordered Rubric)
Rates the state against ordered descriptive levels (lowest first, at least 2 levels). Returns `score` (level index or weighted value), `confidence`, and `probabilities`.

```json
{
  "id": "impact",
  "type": "score",
  "instructions": "How much damage would this operation cause if unintended?",
  "levels": [
    "None, read-only operation",
    "Small, single file or reversible local change",
    "Large, touches multiple shared files or database",
    "Severe, permanent data loss or forced history overwrite"
  ]
}
```

---

## Expected Output Format

The `jev` subagent returns a JSON object:

```json
{
  "model": "jev-1.13",
  "answers": {
    "is_urgent": {
      "type": "noul",
      "noul": 0.95
    },
    "failure_class": {
      "type": "choice",
      "choice": "code_bug",
      "confidence": 0.89,
      "probabilities": {
        "code_bug": 0.89,
        "environment": 0.08,
        "transient": 0.03,
        "permission": 0.00
      }
    },
    "impact": {
      "type": "score",
      "score": 1.0,
      "confidence": 0.92,
      "legend": {
        "0": "None, read-only operation",
        "1": "Small, single file or reversible local change",
        "2": "Large, touches multiple shared files or database",
        "3": "Severe, permanent data loss or forced history overwrite"
      },
      "probabilities": {
        "0": 0.05,
        "1": 0.92,
        "2": 0.03,
        "3": 0.00
      }
    }
  }
}
```

---

## Best Practices

1. **Keep questions atomic**: Each question should be a single, well-scoped gut-check. Do not ask multi-factor questions; split them into independent questions and combine the scores in your logic.
2. **Parallel evaluation**: All questions in a single request are evaluated in parallel against the state. Adding multiple questions has negligible latency impact.
3. **Branch on confidence**: For `choice` and `score`, inspect `confidence` before taking irreversible actions.
