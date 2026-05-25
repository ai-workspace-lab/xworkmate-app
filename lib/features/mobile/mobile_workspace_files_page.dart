import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../i18n/app_language.dart';
import '../../theme/app_palette.dart';

class MobileWorkspaceFilesPage extends StatefulWidget {
  const MobileWorkspaceFilesPage({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  State<MobileWorkspaceFilesPage> createState() => _MobileWorkspaceFilesPageState();
}

class _MobileWorkspaceFilesPageState extends State<MobileWorkspaceFilesPage> {
  List<FileSystemEntity> _files = [];
  bool _loading = false;
  
  @override
  void initState() {
    super.initState();
    _loadFiles();
  }
  
  Future<void> _loadFiles() async {
    setState(() { _loading = true; });
    try {
      final thread = widget.controller.taskThreadForSessionInternal(widget.controller.currentSessionKey);
      final cwd = thread?.workspacePath.trim() ?? '';
      if (cwd.isNotEmpty) {
        final dir = Directory(cwd);
        if (await dir.exists()) {
          final list = await dir.list().toList();
          setState(() {
            _files = list;
          });
        }
      }
    } catch (e) {
      // Ignore
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final palette = context.palette;
        final thread = widget.controller.taskThreadForSessionInternal(widget.controller.currentSessionKey);
        final cwd = thread?.workspacePath.trim() ?? '';
        
        if (cwd.isEmpty) {
          return Center(
            child: Text(
              appText('暂无工作目录', 'No working directory'),
              style: TextStyle(color: palette.textSecondary),
            ),
          );
        }

        if (_loading) {
          return const Center(child: CupertinoActivityIndicator());
        }

        if (_files.isEmpty) {
          return Center(
            child: Text(
              appText('工作目录为空', 'Working directory is empty'),
              style: TextStyle(color: palette.textSecondary),
            ),
          );
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: _loadFiles,
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final file = _files[index];
                  final isDir = file is Directory;
                  final name = file.path.split(Platform.pathSeparator).last;
                  
                  return InkWell(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(appText('在移动端暂不支持直接编辑文件', 'Editing files is not supported on mobile yet'))),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                      child: Row(
                        children: [
                          Icon(
                            isDir ? CupertinoIcons.folder_fill : CupertinoIcons.doc_text_fill,
                            color: isDir ? palette.accent : palette.textSecondary,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              name,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: palette.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(CupertinoIcons.chevron_right, size: 16, color: palette.textSecondary.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  );
                },
                childCount: _files.length,
              ),
            ),
          ],
        );
      },
    );
  }
}
