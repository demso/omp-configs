---
name: jev
description: >
  TypeSafe Jev (System One) decision layer. Returns typed, calibrated answers:
  yes/no probability (noul), a chosen option with a distribution (choice), a
  rubric score with confidence (score). Dispatch here when a decision must be
  numeric or probabilistic rather than prose: classification, relevance checks,
  severity rubrics, intent routing, confidence-gated reviews. Pass one JSON
  payload {"state": "...", "questions": [{id, type, instructions, options?, levels?}]}
  as the task text; the answer comes back verbatim. Jev cannot write prose,
  generate code, or reason step by step — never use it for those.
model: "@jev"
tools: ""
spawns: ""
---
