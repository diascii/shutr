import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'photo_viewer.dart';

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
  List<_DateGroup> _groups = [];
  AssetPathEntity? _currentPath;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _permissionDenied = false;

  int _page = 0;
  static const int _pageSize = 80;

  int _crossAxisCount = 3;
  double _lastScale = 1.0;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  // Drag Select State
  int? _dragStartIndex;
  bool _isDragging = false;
  final Map<int, Rect> _itemRects = {};

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
      if (!_loadingMore && _hasMore) {
        _loadMore();
      }
    }
    _itemRects.clear();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      if (details.scale == 1.0) return;
      final delta = details.scale - _lastScale;
      if (delta.abs() < 0.2) return;

      setState(() {
        if (delta > 0 && _crossAxisCount > 2) {
          _crossAxisCount--;
          _lastScale = details.scale;
          HapticFeedback.lightImpact();
        } else if (delta < 0 && _crossAxisCount < 5) {
          _crossAxisCount++;
          _lastScale = details.scale;
          HapticFeedback.lightImpact();
        }
      });
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_selectionMode) {
      _isDragging = false;
      _dragStartIndex = _getIndexAtOffset(event.localPosition);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_dragStartIndex != null) {
      final currentIndex = _getIndexAtOffset(event.localPosition);
      if (currentIndex != null) {
        if (!_isDragging) {
          _isDragging = true;
          HapticFeedback.selectionClick();
        }
        _updateSelectionRange(_dragStartIndex!, currentIndex);
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _dragStartIndex = null;
    _isDragging = false;
  }

  int? _getIndexAtOffset(Offset localOffset) {
    for (final entry in _itemRects.entries) {
      if (entry.value.contains(localOffset)) {
        return entry.key;
      }
    }
    return null;
  }

  void _updateSelectionRange(int start, int end) {
    final low = start < end ? start : end;
    final high = start < end ? end : start;

    bool changed = false;
    setState(() {
      for (int i = low; i <= high; i++) {
        if (!_selectedIds.contains(_allAssets[i].id)) {
          _selectedIds.add(_allAssets[i].id);
          changed = true;
        }
      }
    });
    if (changed) HapticFeedback.lightImpact();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _allAssets = [];
      _groups = [];
      _page = 0;
      _hasMore = true;
      _itemRects.clear();
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
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(needTitle: false),
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

    setState(() {
      _allAssets = assets;
      _groups = _groupByDate(assets);
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

    if (_allAssets.length > 300) {
      PhotoManager.clearFileCache();
    }

    setState(() {
      _allAssets.addAll(assets);
      _groups = _groupByDate(_allAssets);
      _loadingMore = false;
      _hasMore = assets.length == _pageSize;
    });
  }

  List<_DateGroup> _groupByDate(List<AssetEntity> assets) {
    final map = <String, List<AssetEntity>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final asset in assets) {
      final dt = asset.createDateTime;
      final day = DateTime(dt.year, dt.month, dt.day);

      String label;
      if (day == today) {
        label = 'Today';
      } else if (day == yesterday) {
        label = 'Yesterday';
      } else {
        final sameYear = dt.year == now.year;
        label = sameYear
            ? '${_monthName(dt.month)} ${dt.day}'
            : '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
      }
      map.putIfAbsent(label, () => []).add(asset);
    }
    return map.entries
        .map((e) => _DateGroup(label: e.key, assets: e.value))
        .toList();
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return names[month - 1];
  }

  void _enterSelection(AssetEntity asset, int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectionMode = true;
      _selectedIds.add(asset.id);
      _dragStartIndex = index;
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
      _dragStartIndex = null;
    });
  }

  Future<void> _deleteSelected() async {
    final toDelete =
        _allAssets.where((a) => _selectedIds.contains(a.id)).toList();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(count: toDelete.length),
    );

    if (confirm != true) return;

    await PhotoManager.editor.deleteWithIds(toDelete.map((a) => a.id).toList());

    setState(() {
      _allAssets.removeWhere((a) => _selectedIds.contains(a.id));
      _groups = _groupByDate(_allAssets);
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  void _openViewer(List<AssetEntity> groupAssets, int groupIndex) {
    if (_selectionMode) {
      _toggleSelect(groupAssets[groupIndex]);
      return;
    }
    final asset = groupAssets[groupIndex];
    final globalIndex = _allAssets.indexOf(asset);
    if (globalIndex == -1) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PhotoViewer(
          assets: _allAssets,
          initialIndex: globalIndex,
          onLoadMore: _loadMore,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF4ADE80),
          strokeWidth: 1.5,
        ),
      );
    }

    if (_permissionDenied) {
      return _PermissionPrompt(onRetry: _load);
    }

    if (_groups.isEmpty) {
      return const Center(
        child: Text(
          'No photos yet',
          style: TextStyle(color: Color(0xFF555555), fontSize: 15),
        ),
      );
    }

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_selectionMode) {
          _cancelSelection();
        }
      },
      child: GestureDetector(
        onScaleStart: _handleScaleStart,
        onScaleUpdate: _handleScaleUpdate,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          child: Stack(
            children: [
              RefreshIndicator(
                color: const Color(0xFF4ADE80),
                backgroundColor: const Color(0xFF1C1C1C),
                onRefresh: _load,
                child: CustomScrollView(
                  controller: _scrollCtrl,
                  physics: _isDragging
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    ..._groups.map((group) => _buildGroup(group)),
                    if (_loadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF4ADE80),
                              strokeWidth: 1.5,
                            ),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: _selectionMode ? 88 : 24),
                    ),
                  ],
                ),
              ),
              _FastScrollbar(
                controller: _scrollCtrl,
                allAssets: _allAssets,
              ),
              if (_selectionMode)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _SelectionBar(
                    count: _selectedIds.length,
                    onDelete: _deleteSelected,
                    onCancel: _cancelSelection,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(_DateGroup group) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          key: ValueKey('header_${group.label}'),
          pinned: true,
          delegate: _DateHeaderDelegate(label: group.label),
        ),
        SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final asset = group.assets[i];
              final globalIndex = _allAssets.indexOf(asset);
              return _PhotoCell(
                asset: asset,
                index: globalIndex,
                selected: _selectedIds.contains(asset.id),
                selectionMode: _selectionMode,
                onTap: () => _openViewer(group.assets, i),
                onLongPress: () =>
                    _selectionMode ? null : _enterSelection(asset, globalIndex),
                onRectCalculated: (rect) => _itemRects[globalIndex] = rect,
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

class _DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  _DateHeaderDelegate({required this.label});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF0A0A0A),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF8A8A8A),
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  @override
  double get maxExtent => 40;
  @override
  double get minExtent => 40;
  @override
  bool shouldRebuild(covariant _DateHeaderDelegate oldDelegate) =>
      oldDelegate.label != label;
}

class _PhotoCell extends StatefulWidget {
  final AssetEntity asset;
  final int index;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<Rect> onRectCalculated;

  const _PhotoCell({
    required this.asset,
    required this.index,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.onRectCalculated,
  });

  @override
  State<_PhotoCell> createState() => _PhotoCellState();
}

class _PhotoCellState extends State<_PhotoCell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportRect());
  }

  void _reportRect() {
    if (!mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      // Use global coordinates as the Listener is likely covering the same area
      final offset = box.localToGlobal(Offset.zero);
      widget.onRectCalculated(offset & box.size);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: widget.asset.id,
            child: AssetEntityImage(
              widget.asset,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(200),
              fit: BoxFit.cover,
              frameBuilder: (_, child, frame, __) {
                if (frame == null) {
                  return const ColoredBox(color: Color(0xFF151515));
                }
                return child;
              },
            ),
          ),
          if (widget.selectionMode && !widget.selected)
            const DecoratedBox(
              decoration: BoxDecoration(color: Color(0x54000000)),
            ),
          if (widget.selected)
            const DecoratedBox(
              decoration: BoxDecoration(color: Color(0x334ADE80)),
            ),
          if (widget.selectionMode)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.selected
                      ? const Color(0xFF4ADE80)
                      : Colors.transparent,
                  border: Border.all(
                    color: widget.selected
                        ? const Color(0xFF4ADE80)
                        : Colors.white,
                    width: 1.5,
                  ),
                ),
                child: widget.selected
                    ? const Icon(Icons.check, size: 13, color: Colors.black)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _SelectionBar({
    required this.count,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1C),
        border: Border(top: BorderSide(color: Color(0x12FFFFFF), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              TextButton(
                onPressed: onCancel,
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: Color(0xFF8A8A8A),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: count > 0 ? onDelete : null,
                icon: const Icon(Icons.delete_outline,
                    color: Color(0xFFF87171), size: 18),
                label: Text(
                  'Delete $count',
                  style: const TextStyle(
                    color: Color(0xFFF87171),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteDialog extends StatelessWidget {
  final int count;
  const _DeleteDialog({required this.count});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Delete photos',
        style: TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
      ),
      content: Text(
        'Delete $count ${count == 1 ? 'photo' : 'photos'} permanently from your device?',
        style: const TextStyle(
            color: Color(0xFF8A8A8A), fontSize: 14, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel',
              style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 14)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete',
              style: TextStyle(color: Color(0xFFF87171), fontSize: 14)),
        ),
      ],
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  final VoidCallback onRetry;
  const _PermissionPrompt({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Photo access needed',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 8),
            const Text(
              'Allow Shutr to access your photos to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Color(0xFF8A8A8A), fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () async {
                await PhotoManager.openSetting();
                onRetry();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF222222),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Open Settings',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FastScrollbar extends StatefulWidget {
  final ScrollController controller;
  final List<AssetEntity> allAssets;

  const _FastScrollbar({required this.controller, required this.allAssets});

  @override
  State<_FastScrollbar> createState() => _FastScrollbarState();
}

class _FastScrollbarState extends State<_FastScrollbar> {
  bool _dragging = false;
  double _thumbY = 0;
  String _dateLabel = '';

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!widget.controller.hasClients) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final totalHeight = screenHeight - 300; // top/bottom padding
    final dy = (details.localPosition.dy).clamp(0.0, totalHeight);

    setState(() {
      _dragging = true;
      _thumbY = dy;

      final percent = dy / totalHeight;
      final targetScroll = percent * widget.controller.position.maxScrollExtent;
      widget.controller.jumpTo(targetScroll);

      final index = (percent * (widget.allAssets.length - 1))
          .floor()
          .clamp(0, widget.allAssets.length - 1);
      final date = widget.allAssets[index].createDateTime;
      _dateLabel = '${_monthName(date.month)} ${date.year}';
    });
  }

  String _monthName(int month) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return names[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.allAssets.length < 50) return const SizedBox.shrink();

    return Positioned(
      right: 4,
      top: 150,
      bottom: 150,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: (_) => setState(() => _dragging = false),
        onVerticalDragCancel: () => setState(() => _dragging = false),
        child: Container(
          width: 40,
          color: Colors.transparent,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              if (_dragging)
                Positioned(
                  right: 50,
                  top: _thumbY - 15,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white10, width: 0.5),
                    ),
                    child: Text(
                      _dateLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              Positioned(
                right: 2,
                top: _thumbY,
                child: Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _dragging ? const Color(0xFF4ADE80) : Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateGroup {
  final String label;
  final List<AssetEntity> assets;
  _DateGroup({required this.label, required this.assets});
}
