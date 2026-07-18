# Design QA — Mobile built-in plugin shortcuts

- Source visual truth:
  - `/var/folders/13/xrzs9z_n5ygb1nhxytxsf4480000gn/T/codex-clipboard-12a15989-af92-4a10-b2c7-3f13e694a29d.jpg`
  - `/var/folders/13/xrzs9z_n5ygb1nhxytxsf4480000gn/T/codex-clipboard-e6934733-c045-4a01-bda3-2ae7a98a32b9.jpg`
- Implementation screenshots:
  - `test/features/mobile/goldens/mobile_assistant_home.png`
  - `test/features/mobile/goldens/mobile_assistant_home_plugin_selected.png`
- Viewport: 390 × 844, device pixel ratio 1, iOS light theme
- State: empty assistant home; unselected and document-plugin-selected states
- Full-view comparison evidence: `/tmp/xworkmate-mobile-plugin-comparison.png`
- Focused comparison evidence: `/tmp/xworkmate-mobile-plugin-focused-comparison.png`

## Findings

- No actionable P0, P1, or P2 differences remain.
- Typography: the app continues to use its existing theme and hierarchy. The reference only defines the pill labels, and the implementation preserves comparable weight, scale, and single-line behavior.
- Spacing and layout: the shortcut row stays close to the composer, scrolls horizontally, uses stadium radii, and keeps the reference's compact gap rhythm without clipping the composer.
- Colors and tokens: the unselected surface uses the existing light-gray secondary surface token. The selected state uses the app accent token and remains legible.
- Image and icon fidelity: the pills intentionally use each built-in plugin's existing brand icon tile instead of the reference's generic gray scene icons, because these controls are plugin shortcuts and must match the canonical plugin picker.
- Copy and content: labels come directly from `BuiltinPluginCatalog.firstBatch`, so the home shortcuts and built-in plugin picker cannot drift.

## Comparison History

- Initial implementation used a separate scene model, generic gray icons, scene-specific labels, and prompt-prefill behavior.
- Fix: removed the duplicate scene model, bound both surfaces to the built-in plugin catalog, reused one choice-chip component, and routed taps through the existing session plugin toggle.
- Post-fix evidence: the focused comparison shows the requested light-gray capsule form, canonical plugin logos, and a clear accent-outline selected state; widget coverage confirms horizontal dragging and select/deselect behavior.

## Implementation Checklist

- [x] Five catalog-backed plugin shortcuts
- [x] Manual horizontal scrolling
- [x] Canonical plugin logo and label
- [x] Shared select/deselect behavior with the built-in plugin picker
- [x] Selected-state visual regression coverage
- [x] Composer and send behavior unchanged

## Follow-up Polish

- None required for this pass.

final result: passed
