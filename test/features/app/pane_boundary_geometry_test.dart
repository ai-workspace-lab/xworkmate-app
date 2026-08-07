import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xworkmate/theme/app_palette.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/desktop_workspace_scaffold.dart';
import 'package:xworkmate/widgets/pane_resize_handle.dart';

/// Locks the zero-gutter pane grammar: panes sit flush, the seam between them
/// is a 1px line, and the grab area is wider than the line without pushing the
/// panes apart. A regression here is exactly the "floating cards with gaps"
/// look this layout was changed to remove.
void main() {
  testWidgets('pane boundary draws a 1px line inside an 8px grab area', (
    tester,
  ) async {
    await _pumpBoundary(tester, onDelta: (_) {});

    final line = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(line.constraints?.maxWidth, 1);

    final grabArea = tester.getSize(
      find.descendant(
        of: find.byType(PaneResizeHandle),
        matching: find.byType(SizedBox),
      ),
    );
    expect(grabArea.width, PaneResizeHandle.defaultHitExtent);
  });

  testWidgets('dragging the boundary reports the horizontal delta', (
    tester,
  ) async {
    final deltas = <double>[];
    await _pumpBoundary(tester, onDelta: deltas.add);

    await tester.drag(find.byType(PaneResizeHandle), const Offset(40, 0));
    await tester.pump();

    expect(deltas, isNotEmpty);
    expect(deltas.reduce((a, b) => a + b), closeTo(40, 0.01));
  });

  testWidgets('a boundary without a drag callback ignores pointers', (
    tester,
  ) async {
    await _pumpBoundary(tester, onDelta: null);

    expect(
      find.descendant(
        of: find.byType(PaneResizeHandle),
        matching: find.byType(IgnorePointer),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PaneResizeHandle),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
  });

  testWidgets('the work surface fills its pane with no card treatment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(platform: TargetPlatform.macOS),
        home: const Scaffold(
          body: DesktopWorkspaceScaffold(
            child: SizedBox.expand(key: Key('work-surface')),
          ),
        ),
      ),
    );

    // No radius and no border on the pane itself — those belong to the content
    // cards inside it.
    final decorated = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(DesktopWorkspaceScaffold),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((box) => box.decoration)
        .whereType<BoxDecoration>();
    expect(decorated, isNotEmpty);
    for (final decoration in decorated) {
      expect(decoration.borderRadius, isNull);
      expect(decoration.border, isNull);
    }

    // The child reaches both horizontal edges of the pane.
    final paneWidth = tester.getSize(find.byType(DesktopWorkspaceScaffold)).width;
    expect(tester.getSize(find.byKey(const Key('work-surface'))).width, paneWidth);
  });
}

Future<void> _pumpBoundary(
  WidgetTester tester, {
  required ValueChanged<double>? onDelta,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(platform: TargetPlatform.macOS),
      home: Scaffold(
        body: Builder(
          builder: (context) => Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    const SizedBox(width: 200),
                    Expanded(
                      child: ColoredBox(color: context.palette.surfacePrimary),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 200 - PaneResizeHandle.defaultHitExtent / 2,
                top: 0,
                bottom: 0,
                width: PaneResizeHandle.defaultHitExtent,
                child: PaneResizeHandle(
                  axis: Axis.horizontal,
                  onDelta: onDelta,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
