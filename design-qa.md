# Workbench Issue #213 Design QA

- Source visual truth: `/var/folders/13/xrzs9z_n5ygb1nhxytxsf4480000gn/T/codex-clipboard-9d9a8f32-1dcb-484f-91e5-e9306ec2ee7e.png`
- Rendered implementation: `build/design-qa/golden-snapshot.png`
- Side-by-side evidence: `build/design-qa/workbench-comparison.png`
- Source pixels: `1638 × 960`
- Implementation pixels: `1640 × 960`
- Comparison viewport: `1640 × 960`, desktop light theme, device pixel ratio `1`
- Density normalization: the source was normalized by two horizontal pixels to `1640 × 960`; the implementation was captured at the target CSS and pixel size.
- State: Workbench overview with four TaskThreads, two real workspace groups, one Artifact, one input attachment, mixed running/syncing/ready/blocked lifecycle states.

## Findings

- No actionable P0, P1, or P2 mismatch remains.
- The top-level hierarchy matches the selected target: Workbench above New conversation, header and quick record, four tabs, needs-attention task list, active-project progress, and a fixed insight rail.
- The insight rail now preserves the target proportions and contains a seven-day trend chart, weekly rhythm card, and AI organization suggestions.
- Task rows preserve the target density while using real lifecycle, last-run, preview, workspace, and Artifact metadata.
- Project rows group TaskThreads by real workspace and show derived completion progress and Artifact counts.
- The Flutter deterministic test renderer uses its test glyph font in the screenshot, so Chinese glyph shapes are represented by deterministic blocks. Copy presence and tab labels were verified by widget assertions; the production macOS build continues to use the app's existing system typography.

## Required Fidelity Surfaces

- Fonts and typography: existing app theme hierarchy and weights are preserved; title, section, metadata, badge, and action levels match the source hierarchy. Production font rendering is unchanged.
- Spacing and layout rhythm: the desktop rail, 12 px inter-panel gaps, 16–18 px card padding, compact rows, rounded cards, and section rhythm align with the reference. A separate compact layout prevents mobile overflow.
- Colors and visual tokens: all surfaces, borders, accent, success, warning, danger, text, and muted states use `AppPalette`; no new hard-coded product palette was introduced.
- Image quality and assets: the target contains no raster product imagery. Material icons are used consistently for task state, Artifact type, project, inbox, and actions.
- Copy and content: the reviewed Chinese labels are present, including 总览、我的待办、项目 / 专项、收件箱、需要你处理、正在推进的专项、工作洞察、本周节奏、AI 整理建议.

## Interaction Verification

- Quick record returns to the existing assistant surface.
- Task, project, and inbox rows open their source TaskThread.
- All four Workbench tabs switch to distinct content.
- “查看全部专项” opens the project tab.
- Existing assistant and settings navigation remain available.

## Comparison History

1. Initial comparison found a P2 proportion drift: the right rail was too narrow and the trend and rhythm cards were shorter than the reference.
2. The right rail was increased to 380 px at the target breakpoint, the hero received a stable minimum height, and the chart and rhythm spacing were expanded.
3. Responsive tests found a P2 mobile overflow in task and project rows. Compact row variants were added and the regression suite passed without overflow.
4. The final full-view comparison shows the target information hierarchy, panel proportions, row density, progress treatment, and right-rail composition without remaining P0/P1/P2 issues.

## Follow-up Polish

- Native-window typography can be re-captured after the macOS session is unlocked, without requiring code changes.
- A future WorkItem time-tracking field can replace activity-derived workload counts with explicit planned and actual hours.

final result: passed
