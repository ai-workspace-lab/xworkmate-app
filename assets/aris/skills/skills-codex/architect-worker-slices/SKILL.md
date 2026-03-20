---
name: "architect-worker-slices"
description: "Codex-native work slicing for main engineer and worker lanes."
---

# Architect Worker Slices

Dispatch rules:
- keep the critical path local
- give each worker one bounded slice
- avoid overlapping files
- require a concrete deliverable per lane

Default slice types:
- focused implementation
- focused refactor
- targeted tests
- independent review notes

