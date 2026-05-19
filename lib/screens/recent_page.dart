import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_manager/photo_manager.dart';
import 'photo_viewer.dart';
import '../utils/gallery_utils.dart';

class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollCtrl = ScrollController();
  List<AssetEntity> _allAssets = [];
  List<DateGroup> _groups = [];
  AssetPathEntity? _currentPath;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _permissionDenied = false;

  int _page = 0;
  static const int _pageSize = 80;

  int _crossAxisCount = 3;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  int _lastRefresh = 0;

  void _maybeRefresh(ValueNotifier<int> refresh) {
    if (refresh.value > _lastRefresh) {
      _lastRefresh = refresh.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }



  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 600) {
      if (!_loadingMore && _hasMore) _loadMore();
    }
  }



  Future<void> _load() async {
    final oldIds = _allAssets.map((a) => a.id).toSet();

    setState(() {
      _loading = true;
      _allAssets = [];
      _groups = [];
      _page = 0;
      _hasMore = true;
    });

    final permission = await PhotoManager.requestPermissionExtend();
    if (permission != PermissionState.authorized &&
        permission != PermissionState.limited) {
      setState(() {
        _permissionDenied = true;
        _loading = false;
      });
      return;
    }

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(needTitle: false),
        videoOption: const FilterOption(
          needTitle: false,
          durationConstraint: DurationConstraint(allowNullable: true),
        ),
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false)
        ],
      ),
    );

    if (albums.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    for (final album in albums) {
      if (album.isAll) {
        _currentPath = album;
        break;
      }
    }
    _currentPath ??= albums.first;

    final assets =
        await _currentPath!.getAssetListPaged(page: _page, size: _pageSize);

    if (mounted && oldIds.isNotEmpty) {
      final newCount = assets.where((a) => !oldIds.contains(a.id)).length;
      if (newCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$newCount new ${newCount == 1 ? 'photo' : 'photos'} added'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Up to date'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }

    setState(() {
      _allAssets = assets;
      _groups = groupAssetsByDate(assets);
      _loading = false;
      _hasMore = assets.length == _pageSize;
    });
  }

  Future<void> _loadMore() async {
    if (_currentPath == null) return;
    setState(() => _loadingMore = true);
    _page++;

    final assets =
        await _currentPath!.getAssetListPaged(page: _page, size: _pageSize);
    if (assets.isEmpty) {
      setState(() {
        _hasMore = false;
        _loadingMore = false;
      });
      return;
    }

    if (_allAssets.length > 300) PhotoManager.clearFileCache();

    setState(() {
      _allAssets.addAll(assets);
      _groups = groupAssetsByDate(_allAssets);
      _loadingMore = false;
      _hasMore = assets.length == _pageSize;
    });
  }

  void _enterSelection(AssetEntity asset, int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectionMode = true;
      _selectedIds.add(asset.id);
    });
  }

  void _toggleSelect(AssetEntity asset) {
    setState(() {
      if (_selectedIds.contains(asset.id)) {
        _selectedIds.remove(asset.id);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(asset.id);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_allAssets.map((a) => a.id));
      _selectionMode = true;
    });
    HapticFeedback.lightImpact();
  }

  Future<void> _createAlbumFromSelected() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
        title: const Text('New Album'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Album name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final toMove =
        _allAssets.where((a) => _selectedIds.contains(a.id)).toList();

    try {
      AssetPathEntity? newPath;

      if (Platform.isIOS || Platform.isMacOS) {
        newPath = await PhotoManager.editor.darwin.createAlbum(name);
      } else if (Platform.isAndroid) {
        final firstFile = await toMove.first.file;
        if (firstFile == null) throw 'Could not read photo';

        await PhotoManager.editor.saveImageWithPath(
          firstFile.path,
          relativePath: 'Pictures/$name',
          title: '$name-1.jpg',
        );

        final albums = await PhotoManager.getAssetPathList(
          type: RequestType.common,
          filterOption: FilterOptionGroup(
            orders: [
              const OrderOption(type: OrderOptionType.createDate, asc: false)
            ],
          ),
        );
        newPath = albums.firstWhere(
          (a) => a.name == name,
          orElse: () => throw 'Could not find created album',
        );
      } else {
        throw 'Album creation not supported on this platform';
      }

      if (newPath == null) throw 'Could not create album';

      if (Platform.isAndroid) {
        for (int i = 1; i < toMove.length; i++) {
          final file = await toMove[i].file;
          if (file != null) {
            await PhotoManager.editor.saveImageWithPath(
              file.path,
              relativePath: 'Pictures/$name',
            );
          }
        }
      } else {
        for (final asset in toMove) {
          await PhotoManager.editor
              .copyAssetToPath(asset: asset, pathEntity: newPath);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Album "$name" created with ${toMove.length} items')),
        );
        context.read<ValueNotifier<int>>().value++;
        _cancelSelection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    final toDelete =
        _allAssets.where((a) => _selectedIds.contains(a.id)).toList();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteDialog(count: toDelete.length),
    );
    if (confirm != true) return;

    await PhotoManager.editor.deleteWithIds(toDelete.map((a) => a.id).toList());
    setState(() {
      _allAssets.removeWhere((a) => _selectedIds.contains(a.id));
      _groups = groupAssetsByDate(_allAssets);
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  void _openViewer(List<AssetEntity> groupAssets, int groupIndex) async {
    if (_selectionMode) {
      _toggleSelect(groupAssets[groupIndex]);
      return;
    }
    final asset = groupAssets[groupIndex];
    if (asset.type == AssetType.video) {
      if (!mounted) return;
      final uri = await asset.getMediaUrl();
      if (uri != null && mounted) {
        await launchUrl(Uri.parse(uri),
            mode: LaunchMode.externalApplication);
      }
      return;
    }
    final globalIndex = _allAssets.indexOf(asset);
    if (globalIndex == -1) return;

    final deletedIds = await Navigator.push<List<String>>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PhotoViewer(
          assets: _allAssets,
          initialIndex: globalIndex,
          onLoadMore: _loadMore,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );

    if (deletedIds != null && deletedIds.isNotEmpty) {
      setState(() {
        _allAssets.removeWhere((a) => deletedIds.contains(a.id));
        _groups = groupAssetsByDate(_allAssets);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _maybeRefresh(context.watch<ValueNotifier<int>>());
    final theme = Theme.of(context);

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
          strokeWidth: 2,
        ),
      );
    }
    if (_permissionDenied) return _PermissionPrompt(onRetry: _load);
    if (_groups.isEmpty) {
      return Center(
        child: Text(
          'No photos yet',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _cancelSelection();
      },
      child: Stack(
        children: [
          RefreshIndicator(
            color: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surfaceContainerHigh,
            onRefresh: _load,
            child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const BouncingScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    ..._groups.map(_buildGroup),
                    if (_loadingMore)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: theme.colorScheme.primary,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                        child: SizedBox(height: _selectionMode ? 88 : 24)),
                  ],
                ),
              ),
              _FastScrollbar(controller: _scrollCtrl, allAssets: _allAssets),
              if (_selectionMode)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: SelectionBar(
                    count: _selectedIds.length,
                    onDelete: _deleteSelected,
                    onCancel: _cancelSelection,
                    onSelectAll: _selectAll,
                    onCreateAlbum: _createAlbumFromSelected,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildGroup(DateGroup group) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          key: ValueKey('header_${group.label}'),
          pinned: true,
          delegate: DateHeaderDelegate(label: group.label),
        ),
        SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final asset = group.assets[i];
              final globalIndex = _allAssets.indexOf(asset);
              return PhotoCell(
                key: ValueKey(asset.id),
                asset: asset,
                index: globalIndex,
                selected: _selectedIds.contains(asset.id),
                selectionMode: _selectionMode,
                onTap: () => _openViewer(group.assets, i),
                onLongPress: () =>
                    _selectionMode ? null : _enterSelection(asset, globalIndex),
              );
            },
            childCount: group.assets.length,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _crossAxisCount,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// ─── Fast Scrollbar ───────────────────────────────────────────────────────────

class _FastScrollbar extends StatefulWidget {
  final ScrollController controller;
  final List<AssetEntity> allAssets;
  const _FastScrollbar({required this.controller, required this.allAssets});

  @override
  State<_FastScrollbar> createState() => _FastScrollbarState();
}

class _FastScrollbarState extends State<_FastScrollbar> {
  bool _dragging = false;
  double _thumbFraction = 0; // 0..1, derived from scroll position
  String _dateLabel = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (_dragging) return;
    if (!widget.controller.hasClients) return;
    final pos = widget.controller.position;
    if (pos.maxScrollExtent <= 0) return;
    setState(() =>
        _thumbFraction = (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0));
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double trackHeight) {
    if (!widget.controller.hasClients) return;
    final pos = widget.controller.position;
    if (pos.maxScrollExtent <= 0) return;

    final dy = (details.localPosition.dy).clamp(0.0, trackHeight);
    final fraction = dy / trackHeight;

    setState(() {
      _dragging = true;
      _thumbFraction = fraction;

      widget.controller.jumpTo(fraction * pos.maxScrollExtent);

      final index = (fraction * (widget.allAssets.length - 1))
          .floor()
          .clamp(0, widget.allAssets.length - 1);
      final date = widget.allAssets[index].createDateTime;
      _dateLabel = '${monthNameShort(date.month)} ${date.year}';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allAssets.length < 50) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Positioned(
      right: 4,
      top: 150,
      bottom: 150,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackHeight = constraints.maxHeight;
          const thumbHeight = 40.0;
          final thumbTop = (_thumbFraction * (trackHeight - thumbHeight))
              .clamp(0.0, trackHeight - thumbHeight);

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, trackHeight),
            onVerticalDragEnd: (_) => setState(() => _dragging = false),
            onVerticalDragCancel: () => setState(() => _dragging = false),
            child: SizedBox(
              width: 48,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (_dragging)
                    Positioned(
                      right: 54,
                      top: thumbTop,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: theme.dividerColor.withValues(alpha: 0.1),
                              width: 0.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Text(
                          _dateLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 4,
                    top: thumbTop,
                    child: Container(
                      width: 4,
                      height: thumbHeight,
                      decoration: BoxDecoration(
                        color: _dragging
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Permission Prompt ────────────────────────────────────────────────────────

class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionPrompt({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Photo access needed',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Allow Shutr to access your photos to get started.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                )),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () async {
                await PhotoManager.openSetting();
                onRetry();
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
              ),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
