# 2026-03-30 Installed-Skill E2E Harness

## Change Summary

Added a reusable installed-skill E2E harness for the assistant flow that exercises the common document skill paths for `pptx`, `docx`, `xlsx`, and `pdf`.

The harness is controller-driven and deterministic. It verifies:

- skill discoverability from installed shared roots
- skill binding through session selection
- prompt handoff into `sendChatMessage`
- output capture through the assistant artifact snapshot

The UI shell was left unchanged.

## Test Coverage

- `pptx`
- `docx`
- `xlsx`
- `pdf`

Deferred or skipped coverage is recorded explicitly for the media skill set:

- `image-cog`
- `wan-image-video-generation-editting`
- `video-translator`
- `image-resizer`

## Test Commands And Results

| Command | Result | Notes |
| --- | --- | --- |
| `flutter test test/features/assistant_page_installed_skill_e2e_test.dart` | Passed | 4 passing cases, 1 skipped deferred-media case |

## Verified Behaviors

- Installed skills are discovered from a reusable shared-root seed.
- Each case binds one installed skill into the current assistant session.
- The selected prompt is handed off to the controller path that would normally submit the message.
- A deterministic artifact is written and then surfaced through the assistant artifact snapshot.

## Residual Gaps

- The media skill packs are not installed in this test environment, so their end-to-end flow remains deferred.
- This harness is controller-level, so it does not revalidate visual shell details beyond the existing assistant test surface.
- The artifact check uses the local thread workspace path and does not cover remote-workspace artifact browsing.

## Files

- `test/features/assistant_page_suite_support.dart`
- `test/features/assistant_page_installed_skill_e2e_suite.dart`
- `test/features/assistant_page_installed_skill_e2e_test.dart`
