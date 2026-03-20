---
name: architect-options
description: Rank architecture options for a coding task with clear trade-offs and a recommendation.
---

# Architect Options

For each request:
- produce 2-4 viable options
- compare simplicity, migration cost, regression risk, and testability
- reject options that duplicate routes, shells, or hidden state
- recommend the smallest change that preserves current UX

Always end with:
- chosen option
- why it wins
- what was rejected and why

