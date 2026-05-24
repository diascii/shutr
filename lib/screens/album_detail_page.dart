import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'photo_viewer.dart';
import '../utils/gallery_utils.dart';
import '../utils/snackbar_helper.dart';
import '../services/peer_service.dart';
import '../widgets/live_album_widgets.dart';

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
  List<DateGroup> _groups = [];
  AssetEntity? _coverAsset;

  bool _loadingMore = false;
  bool _hasMore = true;

  int _page = 0;
  static const int _pageSize = 80;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  final Set<String> _pendingDeletions = {};
  Timer? _deleteTimer;

  final Set<String> _selectedLiveIds = {};
  bool _liveSelectionMode = false;

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
    setState(() {
      _assets = [];
      _groups = [];
      _page = 0;
      _hasMore = true;
    });

    final assets =
        await widget.album.getAssetListPaged(page: _page, size: _pageSize);
    setState(() {
      _assets = assets;
      _coverAsset = assets.isNotEmpty ? assets.first : null;
      _groups = groupAssetsByDate(assets);
      _hasMore = assets.length == _pageSize;
    });
    _loadCover();
  }

  Future<void> _loadCover() async {
    final prefs = await SharedPreferences.getInstance();
    final coverId = prefs.getString('album_cover_${widget.album.id}');
    if (coverId == null) return;
    if (_coverAsset?.id == coverId) return;
    final coverAsset = await AssetEntity.fromId(coverId);
    if (coverAsset != null && mounted) {
      setState(() => _coverAsset = coverAsset);
    }
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

    if (_assets.length > 300) PhotoManager.clearFileCache();

    setState(() {
      _assets.addAll(assets);
      _groups = groupAssetsByDate(_assets);
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
      _selectedIds.addAll(_assets.map((a) => a.id));
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

    final toMove = _assets.where((a) => _selectedIds.contains(a.id)).toList();

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
        SnackBarHelper.show(context, message: 'Error: $e', type: SnackBarType.error);
      }
    }
  }

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _snackBarCtrl;

  void _handleDeletion(List<String> ids) {
    if (ids.isEmpty) return;

    _deleteTimer?.cancel();
    _snackBarCtrl?.close();

    setState(() {
      _pendingDeletions.addAll(ids);
    });

    _snackBarCtrl = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${ids.length == 1 ? 'Photo' : '${ids.length} photos'} deleted',
            style: const TextStyle(color: Colors.white)),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: const Color(0xFF6B8AFF),
          onPressed: () {
            _deleteTimer?.cancel();
            _snackBarCtrl?.close();
            setState(() {
              _pendingDeletions.removeAll(ids);
            });
          },
        ),
        backgroundColor: const Color(0xFF1C1C1C),
        duration: const Duration(seconds: 5),
      ),
    );

    _deleteTimer = Timer(const Duration(seconds: 5), () async {
      _snackBarCtrl?.close();
      if (_pendingDeletions.isEmpty) return;
      final toDelete = List<String>.from(_pendingDeletions);
      await PhotoManager.editor.deleteWithIds(toDelete);
      if (mounted) {
        setState(() {
          _assets.removeWhere((a) => toDelete.contains(a.id));
          _pendingDeletions.clear();
        });
      }
    });
  }

  Future<void> _deleteSelected() async {
    final toDelete = _assets.where((a) => _selectedIds.contains(a.id)).toList();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteDialog(count: toDelete.length),
    );
    if (confirm != true) return;

    final ids = toDelete.map((a) => a.id).toList();
    _handleDeletion(ids);
    _cancelSelection();
  }

  void _openViewer(int index) async {
    if (_selectionMode) {
      _toggleSelect(_assets[index]);
      return;
    }

    final filteredAssets =
        _assets.where((a) => !_pendingDeletions.contains(a.id)).toList();
    final asset = _assets[index];
    if (asset.type == AssetType.video) {
      if (!mounted) return;
      final uri = await asset.getMediaUrl();
      if (uri != null && mounted) {
        await launchUrl(Uri.parse(uri),
            mode: LaunchMode.externalApplication);
      }
      return;
    }

    final viewerIndex = filteredAssets.indexOf(asset);
    if (viewerIndex == -1) return;

    final deletedIds = await Navigator.push<List<String>>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PhotoViewer(
          assets: filteredAssets,
          initialIndex: viewerIndex,
          onLoadMore: _loadMore,
          onSetCover: (asset) => _setCover(asset),
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
      _handleDeletion(deletedIds);
    }
  }

  Future<void> _setCover(AssetEntity asset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('album_cover_${widget.album.id}', asset.id);
    setState(() => _coverAsset = asset);
    if (mounted) {
      context.read<ValueNotifier<int>>().value++;
      SnackBarHelper.show(context, message: 'Album cover updated', type: SnackBarType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Consumer<PeerService>(
        builder: (context, peerService, child) {
          final isLive = peerService.liveAlbumIds.contains(widget.album.id);
          final liveIds = isLive
              ? peerService.getLiveAssets(widget.album.id).map((a) => a.id).toList()
              : <String>[];

          // Apply filtering for pending deletions and live/video rules
          final List<AssetEntity> filteredAssets = _assets
              .where((a) => !_pendingDeletions.contains(a.id))
              .toList();

          final List<AssetEntity> displayedAssets = isLive
              ? filteredAssets.where((a) => a.type == AssetType.image).toList()
              : filteredAssets;

          final displayedGroups = isLive
              ? groupAssetsByDate(displayedAssets)
              : _groups;

          return PopScope(
            canPop: !_selectionMode && !_liveSelectionMode,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_selectionMode) _cancelSelection();
              if (_liveSelectionMode) {
                setState(() => _liveSelectionMode = false);
              }
            },
            child: Scaffold(
              backgroundColor: const Color(0xFF0A0A0A),
              body: Stack(
                children: [
                  RefreshIndicator(
                    color: const Color(0xFF6B8AFF),
                    backgroundColor: const Color(0xFF1C1C1C),
                    onRefresh: _load,
                    child: CustomScrollView(
                      controller: _scrollCtrl,
                      physics: _liveSelectionMode
                          ? const NeverScrollableScrollPhysics()
                          : const BouncingScrollPhysics(),
                      slivers: [
                        _buildHeroHeader(liveIds.length, isLive, displayedAssets.length),
                        if (liveIds.isNotEmpty)
                          _buildLiveGrid(liveIds, peerService),
                        ...displayedGroups.map(_buildGroup),
                        if (_loadingMore)
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF6B8AFF),
                                  strokeWidth: 1.5,
                                ),
                              ),
                            ),
                          ),
                        SliverToBoxAdapter(
                          child: SizedBox(
                              height: (_selectionMode || _liveSelectionMode)
                                  ? 88
                                  : 24),
                        ),
                      ],
                    ),
                  ),
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
                    if (_liveSelectionMode)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LiveSelectionBar(
                          count: _selectedLiveIds.length,
                          onDownload: () async {
                            for (final id in _selectedLiveIds) {
                              final liveAsset = peerService.getLiveAsset(id);
                              if (liveAsset != null) {
                                final file = File(liveAsset.path);
                                await PhotoManager.editor.saveImage(
                                  await file.readAsBytes(),
                                  filename: 'shutr_saved_$id.jpg',
                                  title: 'shutr_saved_$id',
                                );
                              }
                            }
                            setState(() => _liveSelectionMode = false);
                            _selectedLiveIds.clear();
                            if (context.mounted) {
                              SnackBarHelper.show(context, message: 'Saved selected to library', type: SnackBarType.success);
                            }
                          },
                          onDelete: () {
                            for (final id in _selectedLiveIds) {
                              peerService.removeLiveAsset(id);
                            }
                            setState(() => _liveSelectionMode = false);
                            _selectedLiveIds.clear();
                          },
                          onCancel: () {
                            setState(() => _liveSelectionMode = false);
                            _selectedLiveIds.clear();
                          },
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

  Widget _buildLiveGrid(List<String> liveIds, PeerService peerService) {
    return SliverGrid(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final id = liveIds[i];
          final liveAsset = peerService.getLiveAsset(id)!;
          final selected = _selectedLiveIds.contains(id);

          return GestureDetector(
            onLongPress: () => setState(() {
              _liveSelectionMode = true;
              _selectedLiveIds.add(id);
            }),
            onTap: () {
              if (_liveSelectionMode) {
                setState(() => selected
                    ? _selectedLiveIds.remove(id)
                    : _selectedLiveIds.add(id));
                if (_selectedLiveIds.isEmpty) _liveSelectionMode = false;
              } else {
                // Capture id and index now so they can't be stale inside the route
                final capturedIndex = i;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveAlbumViewer(
                      initialIndex: capturedIndex,
                      liveIds: List<String>.from(liveIds),
                      peerService: peerService,
                    ),
                  ),
                );
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(liveAsset.path), fit: BoxFit.cover),
                if (_liveSelectionMode && selected)
                  Container(color: Colors.green.withValues(alpha: 0.3)),
                if (_liveSelectionMode)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? const Color(0xFF6B8AFF)
                            : Colors.transparent,
                        border: Border.all(
                            color: selected
                                ? const Color(0xFF6B8AFF)
                                : Colors.white,
                            width: 1.5),
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              size: 13, color: Colors.black)
                          : null,
                    ),
                  ),
              ],
            ),
          );
        },
        childCount: liveIds.length,
      ),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
    );
  }

  Widget _buildHeroHeader(int liveCount, bool isLive, int assetsCount) {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      expandedHeight: 200,
      automaticallyImplyLeading: false,
      actions: const [],
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
                  thumbnailSize: const ThumbnailSize.square(1000),
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
              left: 12,
              top: 12,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 22),
                  onPressed: (_selectionMode || _liveSelectionMode)
                      ? _cancelSelection
                      : () => Navigator.pop(context),
                ),
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
                        letterSpacing: -0.5),
                  ),
                  Text(
                    (_selectionMode || _liveSelectionMode)
                        ? '${_selectionMode ? _selectedIds.length : _selectedLiveIds.length} selected'
                        : '${assetsCount + liveCount} items',
                    style: const TextStyle(
                        color: Color(0xFFCCCCCC),
                        fontSize: 14,
                        fontWeight: FontWeight.w300),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroup(DateGroup group) {
    return SliverMainAxisGroup(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: DateHeaderDelegate(label: group.label, uppercase: true),
        ),
        SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final asset = group.assets[i];
              final globalIndex = _assets.indexOf(asset);
              return PhotoCell(
                key: ValueKey(asset.id),
                asset: asset,
                index: globalIndex,
                selected: _selectedIds.contains(asset.id),
                selectionMode: _selectionMode,
                onTap: () => _openViewer(globalIndex),
                onLongPress: () =>
                    _selectionMode ? null : _enterSelection(asset, globalIndex),
              );
            },
            childCount: group.assets.length,
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
        ),
      ],
    );
  }
}
