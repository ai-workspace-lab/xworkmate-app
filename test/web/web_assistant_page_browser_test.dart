@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xworkmate/runtime/assistant_artifacts.dart';
import 'package:xworkmate/runtime/runtime_models.dart';
import 'package:xworkmate/theme/app_theme.dart';
import 'package:xworkmate/widgets/assistant_artifact_sidebar.dart';
import 'package:xworkmate/widgets/pane_resize_handle.dart';

void main() {
  testWidgets('artifact sidebar opens, resizes, and collapses in browser', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: _BrowserArtifactSidebarHarness()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('assistant-artifact-pane')), findsNothing);
    expect(
      find.byKey(const Key('assistant-artifact-pane-toggle')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('assistant-artifact-pane-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const Key('assistant-artifact-pane')), findsOneWidget);

    final beforeWidth = tester
        .getSize(find.byKey(const Key('assistant-artifact-pane')))
        .width;
    await tester.drag(
      find.byKey(const Key('assistant-artifact-pane-resize-handle')),
      const Offset(-80, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final afterWidth = tester
        .getSize(find.byKey(const Key('assistant-artifact-pane')))
        .width;
    expect(afterWidth, greaterThan(beforeWidth));

    await tester.tap(find.byKey(const Key('assistant-artifact-pane-collapse')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const Key('assistant-artifact-pane')), findsNothing);
  });
}

class _BrowserArtifactSidebarHarness extends StatefulWidget {
  const _BrowserArtifactSidebarHarness();

  @override
  State<_BrowserArtifactSidebarHarness> createState() =>
      _BrowserArtifactSidebarHarnessState();
}

class _BrowserArtifactSidebarHarnessState
    extends State<_BrowserArtifactSidebarHarness> {
  bool _collapsed = true;
  double _width = 360;

  late final AssistantArtifactSnapshot _snapshot = AssistantArtifactSnapshot(
    workspaceRef: '/owners/remote/user/browser-device/threads/browser-thread',
    workspaceRefKind: WorkspaceRefKind.remotePath,
    resultEntries: <AssistantArtifactEntry>[
      const AssistantArtifactEntry(
        id: 'readme',
        label: 'README.md',
        relativePath: 'README.md',
        kind: AssistantArtifactEntryKind.object,
        mimeType: 'text/markdown',
        previewable: true,
        workspaceRef: '/owners/remote/user/browser-device/threads/browser-thread',
      ),
    ],
    fileEntries: <AssistantArtifactEntry>[
      const AssistantArtifactEntry(
        id: 'readme',
        label: 'README.md',
        relativePath: 'README.md',
        kind: AssistantArtifactEntryKind.object,
        mimeType: 'text/markdown',
        previewable: true,
        workspaceRef: '/owners/remote/user/browser-device/threads/browser-thread',
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth * 0.48;
          final paneWidth = _width.clamp(280.0, maxWidth).toDouble();
          return Stack(
            children: [
              Positioned.fill(
                child: Row(
                  children: [
                    const Expanded(child: SizedBox.expand()),
                    if (!_collapsed) ...[
                      SizedBox(
                        key: const Key('assistant-artifact-pane-resize-handle'),
                        width: 8,
                        child: PaneResizeHandle(
                          axis: Axis.horizontal,
                          onDelta: (delta) {
                            setState(() {
                              _width = (_width - delta).clamp(280.0, maxWidth);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: paneWidth,
                        child: AssistantArtifactSidebar(
                          sessionKey: 'browser-thread',
                          threadTitle: 'Browser thread',
                          workspaceRef: _snapshot.workspaceRef,
                          workspaceRefKind: _snapshot.workspaceRefKind,
                          onCollapse: () {
                            setState(() {
                              _collapsed = true;
                            });
                          },
                          loadSnapshot: () async => _snapshot,
                          loadPreview: (entry) async =>
                              const AssistantArtifactPreview(
                                kind: AssistantArtifactPreviewKind.markdown,
                                content: '# Browser artifact',
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_collapsed)
                Positioned(
                  right: 8,
                  top: 120,
                  child: AssistantArtifactSidebarRevealButton(
                    onTap: () {
                      setState(() {
                        _collapsed = false;
                      });
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
