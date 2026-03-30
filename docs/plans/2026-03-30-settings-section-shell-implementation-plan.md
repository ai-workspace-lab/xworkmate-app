# Settings Section Shell Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract a shared Settings page shell so Desktop and Web reuse the same top-level layout, ordered section composition, and global apply bar behavior without changing the three-column workspace skeleton.

**Architecture:** Introduce a small shared shell widget layer under `lib/widgets/` that owns the common settings-page frame and ordered section assembly. Keep Desktop and Web-specific controllers, gateway sub-tabs, and section content builders in their existing feature modules.

**Tech Stack:** Flutter, Dart, existing `TopBar`/`SurfaceCard` widgets, Desktop/Web app controllers.

---

### Task 1: Add a shared settings page shell module

**Files:**
- Create: `lib/widgets/settings_page_shell.dart`

**Step 1: Add a shared apply-bar widget**

- Implement a widget that renders:
  - title `设置提交流程 / Settings Submission`
  - resolved draft/apply status copy
  - `settings-global-apply-button`
- Pass behavior through parameters instead of depending on a specific controller type.

**Step 2: Add a shared page body shell**

- Implement a widget that renders:
  - `TopBar`
  - optional shared apply bar
  - page body children
- Keep paddings configurable so Desktop and Web can preserve their current spacing.

**Step 3: Add a shared ordered-section helper**

- Implement a helper that:
  - takes `availableTabs`, `currentTab`
  - asks a callback for each tab’s content
  - interleaves `SizedBox(height: 24)` between non-empty sections

### Task 2: Move Desktop Settings page onto the shared shell

**Files:**
- Modify: `lib/features/settings/settings_page_core.dart`
- Modify: `lib/features/settings/settings_page_sections.dart`

**Step 1: Replace duplicated page frame markup**

- Swap the current top-level `SingleChildScrollView -> Column -> TopBar -> apply bar -> body` block to the shared shell widget.

**Step 2: Replace duplicated ordered overview assembly**

- Route overview ordering through the shared helper instead of local inline assembly.

**Step 3: Keep detail-mode behavior unchanged**

- Ensure the existing desktop-only detail flow still owns:
  - breadcrumbs
  - back button
  - detail intro cards
  - gateway navigation hints

### Task 3: Move Web Settings page onto the shared shell

**Files:**
- Modify: `lib/web/web_settings_page_core.dart`
- Modify: `lib/web/web_settings_page_sections.dart`

**Step 1: Reuse the shared page frame**

- Keep `DesktopWorkspaceScaffold` in Web.
- Replace the inner duplicated page body with the shared shell widget.

**Step 2: Reuse the ordered-section helper where still needed**

- Keep Web tab availability constraints intact.
- Use the same helper for any ordered overview logic that remains.

**Step 3: Preserve Web-specific gateway behavior**

- Keep:
  - web search field key
  - browser persistence copy
  - ACP-specific apply-bar gating

### Task 4: Verify the refactor

**Files:**
- Modify as needed: `test/features/settings_page_suite.dart`
- Modify as needed: `test/web/web_ui_browser_test.dart`

**Step 1: Run static analysis**

Run:

```bash
flutter analyze lib/widgets/settings_page_shell.dart lib/features/settings/settings_page_core.dart lib/features/settings/settings_page_sections.dart lib/web/web_settings_page_core.dart lib/web/web_settings_page_sections.dart test/features/settings_page_suite.dart test/web/web_ui_browser_test.dart
```

**Step 2: Run targeted Desktop settings tests**

Run:

```bash
flutter test test/features/settings_page_suite.dart
```

**Step 3: Run targeted Web browser regression**

Run:

```bash
flutter test --platform chrome test/web/web_ui_browser_test.dart
```

**Step 4: Record residual risk**

- Note whether any remaining Desktop/Web duplication still lives in:
  - gateway sub-tab section builders
  - detail-only desktop flows
  - web-only persistence cards
