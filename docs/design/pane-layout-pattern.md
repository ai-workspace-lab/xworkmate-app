# Pane layout pattern

Authoritative rules for how XWorkmate's desktop surfaces are divided. Every new
pane, rail or divider follows this; if a screen cannot, the grammar grows here
first.

Related: `docs/plans/2026-08-07-ui-interaction-polish-plan.md` (why these rules
exist), `lib/widgets/app_pane_shell.dart`, `lib/widgets/pane_resize_handle.dart`.

---

## 1. A pane is not a card

| | Pane | Content card (`SurfaceCard`) |
|---|---|---|
| Radius | none | `AppRadius.card` |
| Border | none | `strokeSoft` |
| Elevation | none | on hover / tap |
| Outer margin | none | per layout |
| Background | one flat colour | `surfacePrimary` |

A pane fills its slot edge to edge. **Radius, stroke and elevation belong to the
cards inside a pane, never to the pane itself.** Putting them on the pane is what
produced the "floating blocks with gaps" look this pattern replaced.

Panes are told apart by a **background step**, not by whitespace:

| Slot | Colour |
|---|---|
| Left rail / sidebar | `palette.sidebar` |
| Work surface | `palette.surfacePrimary` |
| Right rail | `palette.chromeBackground` |

Use `AppPaneShell` for the container and `AppSpacing.paneContent` for the inset
between a pane's edge and its content. Every page reads that one token — the
assistant surface and the settings surface must not drift apart again.

## 2. A boundary is overlaid, never laid out

**Rule: a pane boundary is a `Positioned` overlay inside the `Stack` that holds
the panes. It is never a child of the pane `Row`/`Column`.**

A child occupies layout space, and that space *is* the gutter the pattern exists
to remove. This applies to all four boundaries alike:

| Boundary | Overlay anchor |
|---|---|
| sidebar ↔ work surface | `left: sidebarWidth - hit/2` |
| task rail ↔ work surface | `left: railWidth - hit/2` |
| work surface ↔ artifact rail | `right: paneWidth - hit/2` |
| transcript ↔ composer | `bottom: composerHeight - hit/2` |

`PaneResizeHandle` renders a **1px line** (2px while hovered or dragged) centred
in a **`defaultHitExtent`-wide grab area**. Give the `Positioned` that same
extent so the line lands exactly on the seam. With no `onDelta` it degrades to a
static, pointer-transparent divider.

Do not try to widen the hit area with `OverflowBox` while keeping a 1px layout
box: Flutter's `RenderBox.hitTest` rejects positions outside the parent's own
size, so the overflowing region never receives pointer events. The overlay is
what makes "zero gap, still draggable" possible.

## 3. A resizable pane has exactly one height control

**Rule: the boundary owns the size. A pane must not carry a second resize
affordance of its own.**

The composer previously had two — the pane divider, and a handle inside the card
that only moved the text area. They shared no state, so dragging one did nothing
to the other and the card stranded itself at the bottom of an enlarged pane.

A resizable pane therefore:

- receives a **tight** height/width constraint, and fills it;
- puts the flexible part in an `Expanded` so it absorbs the slack;
- keeps its fixed rows (toolbars, action rows) at intrinsic size.

### 3.1 Never feed the rendered size back into the size that sets it

The composer used to measure its own rendered height and feed it into the value
that sizes its pane. That is harmless while the content is min-sized and a
**per-frame growth loop** the moment the content fills. Compute a pane's minimum
from its content model; do not measure it back.

### 3.2 Degrade from the far edge, not from the action row

When a pane is smaller than its own minimum, keep rendering at the minimum and
align it so the **primary action stays visible** — clip the far edge instead.
For the composer that means bottom-aligning and trimming the toolbar off the
top; the submit row is the last thing to go, never the first.

Give the child `max(paneExtent, minExtent)` as a tight constraint: it fills when
there is room and degrades predictably when there is not.

---

## Checklist for a new pane or divider

- [ ] Pane has no radius, border, elevation or outer margin.
- [ ] Pane is told apart by a background step, not whitespace.
- [ ] Content inset reads `AppSpacing.paneContent`.
- [ ] Divider is a `Positioned` overlay, not a `Row`/`Column` child.
- [ ] Divider is 1px visible, `defaultHitExtent` grabbable.
- [ ] Exactly one control changes the pane's size.
- [ ] No measured size feeds back into the size that sets it.
- [ ] Under-minimum behaviour keeps the primary action visible.
