# XWorkmate iOS v1.1 mobile redesign

Baseline: `release/v1.1`

## Selected references

- Conversation home: `docs/design/plan/mobile-conversation-home.png`
- Navigation drawer: `docs/design/plan/mobile-navigation-drawer.png`
- Execution thread: `docs/design/plan/mobile-execution-thread.png`

## Direction

The mobile UI keeps the current feature set and reshapes it into a ChatGPT-like iOS interaction model:

- A calm conversation-first landing screen with Bridge status, five built-in plugin scenes, and a persistent composer.
- A full-height mobile navigation surface that exposes the same core work areas as desktop: conversation, workspace, archived tasks, AI workspace, plugins, run logs, and settings.
- An execution-focused chat state that turns running work into a visible timeline, while preserving the existing send, Bridge, Provider, permission, thinking, abort, and settings flows.

## Interaction rules

- Primary task creation remains one tap from the mobile navigation home.
- The bottom composer stays visible above the keyboard and keeps the existing configuration sheet entry points, while the always-visible task configuration strip is collapsed into the left-side settings surface.
- Desktop core functions are mapped to existing mobile settings tabs instead of creating new backend behavior.
- Running tasks show progress in-thread using current message and run state; no new execution protocol is introduced.

## Implementation map

- `lib/features/mobile/mobile_assistant_list_page.dart`: mobile navigation home and recent sessions.
- `lib/features/mobile/mobile_assistant_page_core.dart`: iOS-style top bar and conversation/workspace switching.
- `lib/features/mobile/mobile_assistant_page_conversation.dart`: empty state and execution thread presentation.
- `lib/features/mobile/mobile_assistant_page_composer.dart`: task configuration row and floating capsule composer.
