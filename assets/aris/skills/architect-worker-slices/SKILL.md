---
name: architect-worker-slices
description: Split implementation into main-engineer and worker slices for multi-agent coding.
---

# Architect Worker Slices

When dispatching implementation:
- assign the main engineer the critical path and final integration
- assign workers bounded, parallelizable slices
- keep write scopes disjoint
- define the deliverable for each slice

Good worker slices:
- narrow feature implementation
- focused refactor in one module family
- targeted test additions
- independent review notes

Bad worker slices:
- vague "help with refactor"
- overlapping file ownership
- tasks blocked on unresolved architecture

