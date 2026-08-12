part of 'workbench_analytics.dart';

class WorkbenchNavigation extends StatelessWidget {
  const WorkbenchNavigation({
    super.key,
    required this.index,
    required this.activityWindow,
    required this.onChanged,
    required this.onActivityWindowChanged,
    required this.onQuickRecord,
  });

  final int index;
  final int activityWindow;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onActivityWindowChanged;
  final VoidCallback onQuickRecord;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tabs = <String>[
      appText('数据总览', 'Overview'),
      appText('模型分析', 'Models'),
      appText('我的待办', 'My todo'),
      appText('项目 / 专项', 'Projects / topics'),
      appText('收件箱', 'Inbox'),
    ];
    return Container(
      height: 52,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.strokeSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              itemBuilder: (context, tabIndex) {
                final selected = index == tabIndex;
                return InkWell(
                  key: Key('workbench-tab-$tabIndex'),
                  onTap: () => onChanged(tabIndex),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: selected ? palette.accent : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Text(
                      tabs[tabIndex],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? palette.accent
                            : palette.textSecondary,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _ActivityWindowPicker(
            value: activityWindow,
            onChanged: onActivityWindowChanged,
          ),
          const SizedBox(width: 12),
          Tooltip(
            message: appText('快速记录', 'Quick record'),
            child: IconButton(
              key: const Key('workbench-quick-record-button'),
              onPressed: onQuickRecord,
              icon: const Icon(Icons.add_rounded, size: 24),
              style: IconButton.styleFrom(
                backgroundColor: palette.textPrimary,
                foregroundColor: palette.surfacePrimary,
                minimumSize: const Size(42, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityWindowPicker extends StatelessWidget {
  const _ActivityWindowPicker({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final labels = <String>[
      appText('全部', 'All'),
      appText('30日', '30d'),
      appText('7日', '7d'),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.surfaceSecondary,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (index) {
          final selected = value == index;
          return InkWell(
            key: Key('workbench-activity-window-$index'),
            onTap: () => onChanged(index),
            borderRadius: BorderRadius.circular(9),
            child: AnimatedContainer(
              key: selected
                  ? Key('workbench-activity-window-$index-selected')
                  : null,
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? palette.surfacePrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                labels[index],
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? palette.accent : palette.textSecondary,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
