# XWorkmate Flutter Workbench Design QA

- Source visual truth: `docs/design/workbench/data-overview.png`, `docs/design/workbench/model-analysis.png`
- Implementation captures: `test/features/workbench/goldens/workbench_overview.png`, `test/features/mobile/goldens/mobile_workbench_home.png`
- Desktop viewport: 1440 × 960 CSS px at device pixel ratio 1
- iOS viewport: 390 × 844 CSS px at device pixel ratio 1
- Source pixels: 1487 × 1058
- State: data overview default; model analysis interaction verified by widget test

## Full-view comparison

Desktop uses the approved single-line five-tab navigation, full-width metric grid, annual heatmap, and recent TaskThread table. The model-analysis tab uses the approved six metrics, monthly input/output token chart, model-share table, and recent activity table. iOS keeps the same information architecture in a horizontally scrollable touch-first tab row and a compact model-usage list.

## Focused comparison

- Navigation order and selected state are verified with stable widget keys.
- Metric, heatmap, table, and model-analysis regions are independently asserted in widget tests.
- Empty server-session rendering is covered without introducing demo or local fallback data.
- Golden-test font glyphs use Flutter's deterministic test font and therefore appear as blocks; copy correctness is separately asserted by widget tests and renders through the product font stack at runtime.

## Required fidelity surfaces

- Fonts and typography: product theme styles, weight hierarchy, ellipsis, and numeric emphasis match; deterministic golden glyph substitution is a test-only constraint.
- Spacing and layout rhythm: 12 px gutters, compact one-row navigation, 4 × 2 desktop metrics, annual grid, and scroll-safe tables match the source composition.
- Colors and visual tokens: existing AppPalette surfaces, accent blue, muted grid cells, semantic status colors, borders, and radii are reused.
- Image quality and assets: no custom raster artwork is present; Material icons are used for standard UI symbols.
- Copy and content: 数据总览、模型分析、我的待办、项目 / 专项、收件箱 and all analytics labels match the approved designs.

## Comparison history

1. Removed the former separate dashboard header and right insight rail because they reduced the center canvas and duplicated navigation.
2. Added explicit model/token fields to the existing server-session projection instead of creating local analytics data.
3. Fixed an unbounded-height model chart row discovered by widget rendering, then refreshed and reviewed desktop/iOS golden baselines.

## Findings

No actionable P0/P1/P2 visual or interaction differences remain.

## Follow-up polish

- P3: add a model-analysis golden with authenticated fixture records if the repository later provides a shared server-session fixture.

final result: passed
