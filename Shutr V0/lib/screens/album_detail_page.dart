import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'photo_viewer.dart';

class AlbumDetailPage extends StatefulWidget {
  final AssetPathEntity album;
  final int totalCount;

  const AlbumDetailPage({
    super.key,
    required this.album,
    required this.totalCount,
  });

  @override
  State<AlbumDetailPage> createState() => _AlbumDetailPageState();
}

class _AlbumDetailPageState extends State<AlbumDetailPage> {
  final ScrollController _scrollCtrl = ScrollController();
  List<AssetEntity> _assets = [];
  List<_DateGroup> _groups = [];
  AssetEntity? _coverAsset;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  int _page = 0;
  static const int _pageSize = 80;

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
        if (!_selectedIds.contains(_assets[i].id)) {
          _selectedIds.add(_assets[i].id);
          changed = true;
        }
      }
    });
    if (changed) HapticFeedback.lightImpact();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _assets = [];
      _groups = [];
      _page = 0;
      _hasMore = true;
      _itemRects.clear();
    });

    final assets =
        await widget.album.getAssetListPaged(page: _page, size: _pageSize);

    AssetEntity? cover;
    if (assets.isNotEmpty) {
      cover = assets.first;
    }

    setState(() {
      _assets = assets;
      _coverAsset = cover;
      _groups = _groupByDate(assets);
      _loading = false;
      _hasMore = assets.length == _pageSize;
    });
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    _page++;

    final assets =
        await widget.album.getAssetListPaged(page: _page, size: _pageSize);

    if (assets.isEmpty) {
      setState(() {
        _hasMore = false;
        _loadingMore = false;
      });
      return;
    }

    if (_assets.length > 300) {
      PhotoManager.clearFileCache();
    }

    setState(() {
      _assets.addAll(assets);
      _groups = _groupByDate(_assets);
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
    final toDelete = _assets.where((a) => _selectedIds.contains(a.id)).toList();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(count: toDelete.length),
    );

    if (confirm != true) return;

    await PhotoManager.editor.deleteWithIds(
      toDelete.map((a) => a.id).toList(),
    );

    setState(() {
      _assets.removeWhere((a) => _selectedIds.contains(a.id));
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  void _openViewer(int index) {
    if (_selectionMode) {
      _toggleSelect(_assets[index]);
      return;
    }
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PhotoViewer(
          assets: _assets,
          initialIndex: index,
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
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: PopScope(
        canPop: !_selectionMode,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_selectionMode) {
            _cancelSelection();
          }
        },
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          child: SafeArea(
            bottom: false,
            child: Stack(
              children: [
                _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF4ADE80),
                          strokeWidth: 1.5,
                        ),
                      )
                    : CustomScrollView(
                        controller: _scrollCtrl,
                        physics: _isDragging
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        slivers: [
                          _buildHeroHeader(),
                          ..._groups.map((g) => _buildGroup(g)),
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
                            child: SizedBox(
                              height: _selectionMode ? 88 : 24,
                            ),
                          ),
                        ],
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
      ),
    );
  }

  Widget _buildHeroHeader() {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      expandedHeight: 200,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (_coverAsset != null)
              Hero(
                tag: 'album_${widget.album.id}',
                child: AssetEntityImage(
                  _coverAsset!,
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(600),
                  fit: BoxFit.cover,
                ),
              ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black54, Colors.transparent, Colors.black87],
                ),
              ),
            ),
            Positioned(
              left: 4,
              top: 4,
              child: IconButton(
                icon:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                onPressed: _selectionMode
                    ? _cancelSelection
                    : () => Navigator.pop(context),
              ),
            ),
            Positioned(
              left: 20,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.album.name.isEmpty ? 'Unnamed' : widget.album.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    _selectionMode
                        ? '${_selectedIds.length} selected'
                        : '${_assets.isEmpty ? widget.totalCount : _assets.length} photos',
                    style: const TextStyle(
                      color: Color(0xFFCCCCCC),
                      fontSize: 14,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
              final globalIndex = _assets.indexOf(asset);
              return _PhotoCell(
                asset: asset,
                index: globalIndex,
                selected: _selectedIds.contains(asset.id),
                selectionMode: _selectionMode,
                onTap: () => _openViewer(globalIndex),
                onLongPress: () =>
                    _selectionMode ? null : _enterSelection(asset, globalIndex),
                onRectCalculated: (rect) => _itemRects[globalIndex] = rect,
              );
            },
            childCount: group.assets.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
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
              decoration: BoxDecoration(color: Color(0x55000000)),
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
        border: Border(
          top: BorderSide(color: Color(0x12FFFFFF), width: 0.5),
        ),
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

class _DateGroup {
  final String label;
  final List<AssetEntity> assets;
  _DateGroup({required this.label, required this.assets});
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
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      content: Text(
        'Delete $count ${count == 1 ? 'photo' : 'photos'} permanently from your device?',
        style: const TextStyle(
          color: Color(0xFF8A8A8A),
          fontSize: 14,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 14),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Delete',
            style: TextStyle(color: Color(0xFFF87171), fontSize: 14),
          ),
        ),
      ],
    );
  }
}
