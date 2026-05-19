import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'photo_viewer.dart';
import '../utils/gallery_utils.dart';
import '../services/peer_service.dart';

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

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  int _page = 0;
  static const int _pageSize = 80;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

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
      _loading = true;
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
      _loading = false;
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    final toDelete = _assets.where((a) => _selectedIds.contains(a.id)).toList();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteDialog(count: toDelete.length),
    );
    if (confirm != true) return;

    await PhotoManager.editor.deleteWithIds(toDelete.map((a) => a.id).toList());
    setState(() {
      _assets.removeWhere((a) => _selectedIds.contains(a.id));
      _groups = groupAssetsByDate(_assets);
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  void _openViewer(int index) async {
    if (_selectionMode) {
      _toggleSelect(_assets[index]);
      return;
    }
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
    final deletedIds = await Navigator.push<List<String>>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PhotoViewer(
          assets: _assets,
          initialIndex: index,
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
      setState(() {
        _assets.removeWhere((a) => deletedIds.contains(a.id));
        _groups = groupAssetsByDate(_assets);
      });
    }
  }

  Future<void> _setCover(AssetEntity asset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('album_cover_${widget.album.id}', asset.id);
    setState(() => _coverAsset = asset);
    if (mounted) {
      context.read<ValueNotifier<int>>().value++;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album cover updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Consumer<PeerService>(
        builder: (context, peerService, child) {
          final isLive = peerService.isLive &&
              peerService.activeAlbum?.id == widget.album.id;
          final liveIds = isLive ? peerService.liveContributionIds : <String>[];

          // Apply video filtering if live
          final List<AssetEntity> displayedAssets = isLive
              ? _assets.where((a) => a.type == AssetType.image).toList()
              : _assets;
          final displayedGroups =
              isLive ? groupAssetsByDate(displayedAssets) : _groups;

          return PopScope(
            canPop: !_selectionMode && !_liveSelectionMode,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              if (_selectionMode) _cancelSelection();
              if (_liveSelectionMode) {
                setState(() => _liveSelectionMode = false);
              }
            },
            child: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    _loading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF6B8AFF), strokeWidth: 1.5))
                        : CustomScrollView(
                            controller: _scrollCtrl,
                            physics: _liveSelectionMode
                                ? const NeverScrollableScrollPhysics()
                                : const BouncingScrollPhysics(),
                            slivers: [
                              _buildHeroHeader(liveIds.length, isLive,
                                  displayedAssets.length),
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
                                            strokeWidth: 1.5)),
                                  ),
                                ),
                              SliverToBoxAdapter(
                                child: SizedBox(
                                    height:
                                        (_selectionMode || _liveSelectionMode)
                                            ? 88
                                            : 24),
                              ),
                            ],
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
                        child: _LiveSelectionBar(
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
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text('Saved selected to library')));
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
                    builder: (_) => _LiveAlbumViewer(
                      initialIndex: capturedIndex,
                      liveIds: List<String>.from(liveIds), // snapshot of list
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
      actions: [
        if (isLive)
          IconButton(
            icon: const Icon(Icons.people_outline, color: Colors.white),
            onPressed: () => _showMembers(context),
          ),
      ],
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

  void _showMembers(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Consumer<PeerService>(
        builder: (context, peerService, _) {
          return DefaultTabController(
            length: 2,
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 8),
                  TabBar(
                    dividerColor: Colors.transparent,
                    indicatorColor: const Color(0xFF6B8AFF),
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white24,
                    labelStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    tabs: [
                      Tab(text: 'Members (${peerService.users.length})'),
                      const Tab(text: 'Activity Log'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(children: [
                      _buildMembersTab(peerService),
                      _buildActivityTab(peerService),
                    ]),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMembersTab(PeerService peerService) {
    if (peerService.users.isEmpty) {
      return const Center(
          child:
              Text('No members yet', style: TextStyle(color: Colors.white24)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: peerService.users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final user = peerService.users[i];
        final isPending = user.status == ConnectionStatus.pending;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isPending
                    ? Colors.orange.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: isPending
                    ? Colors.orange.withValues(alpha: 0.1)
                    : const Color(0xFF2A2A2A),
                child: Text(user.name[0].toUpperCase(),
                    style: TextStyle(
                        color: isPending ? Colors.orange : Colors.white,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          isPending
                              ? 'Wants to join'
                              : (user.role == UserRole.contributor
                                  ? 'Contributor'
                                  : 'Viewer'),
                          style: TextStyle(
                              color: isPending
                                  ? Colors.orange
                                  : (user.role == UserRole.contributor
                                      ? const Color(0xFF6B8AFF)
                                      : Colors.white54),
                              fontSize: 12),
                        ),
                        if (!isPending &&
                            user.role == UserRole.contributor) ...[
                          const SizedBox(width: 8),
                          Text('(${user.uploadCount}/${user.uploadLimit} pics)',
                              style: const TextStyle(
                                  color: Colors.white24, fontSize: 11)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (isPending) ...[
                IconButton(
                    icon: const Icon(Icons.check_circle_outline,
                        color: Color(0xFF6B8AFF)),
                    onPressed: () => peerService.acceptUser(user.id)),
                IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: Color(0xFFF87171)),
                    onPressed: () => peerService.rejectUser(user.id)),
              ] else ...[
                if (user.role == UserRole.contributor)
                  IconButton(
                      icon: const Icon(Icons.edit_note,
                          color: Colors.white54, size: 20),
                      onPressed: () =>
                          _showLimitDialog(context, peerService, user)),
                PopupMenuButton<UserRole>(
                  icon: const Icon(Icons.swap_horiz,
                      color: Colors.white54, size: 20),
                  onSelected: (role) =>
                      peerService.updateUserRole(user.id, role),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                        value: UserRole.viewer, child: Text('Make Viewer')),
                    const PopupMenuItem(
                        value: UserRole.contributor,
                        child: Text('Make Contributor')),
                  ],
                ),
                IconButton(
                    icon: const Icon(Icons.logout,
                        color: Color(0xFFF87171), size: 20),
                    onPressed: () => peerService.rejectUser(user.id)),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showLimitDialog(
      BuildContext context, PeerService peerService, ConnectedUser user) {
    final ctrl = TextEditingController(text: user.uploadLimit.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: Text('Limit for ${user.name}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              hintText: 'Limit (1-100)',
              hintStyle: TextStyle(color: Colors.white24)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text);
              if (val != null) peerService.updateUserLimit(user.id, val);
              Navigator.pop(ctx);
            },
            child: const Text('Update',
                style: TextStyle(color: Color(0xFF6B8AFF))),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTab(PeerService peerService) {
    final logs = peerService.activityLog.reversed.toList();
    if (logs.isEmpty) {
      return const Center(
          child:
              Text('No activity yet', style: TextStyle(color: Colors.white24)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: logs.length,
      itemBuilder: (context, i) {
        final log = logs[i];
        final isUpload = log.type == PeerEventType.upload;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isUpload
                          ? const Color(0xFF6B8AFF)
                          : const Color(0xFF2A2A2A),
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                  ),
                  if (i < logs.length - 1)
                    Expanded(child: Container(width: 1, color: Colors.white10)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(log.message,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                        ),
                        Text(
                          '${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              color: Colors.white24, fontSize: 11),
                        ),
                      ],
                    ),
                    if (isUpload && log.assetIds.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 60,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: log.assetIds.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, j) {
                            final asset =
                                peerService.getLiveAsset(log.assetIds[j]);
                            if (asset == null) return const SizedBox();
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(File(asset.path),
                                  width: 60, height: 60, fit: BoxFit.cover),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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

// ─── Live Album Viewer ────────────────────────────────────────────────────────

class _LiveAlbumViewer extends StatefulWidget {
  final int initialIndex;
  final List<String> liveIds; // snapshot passed in — never stale
  final PeerService peerService;

  const _LiveAlbumViewer({
    required this.initialIndex,
    required this.liveIds,
    required this.peerService,
  });

  @override
  State<_LiveAlbumViewer> createState() => _LiveAlbumViewerState();
}

class _LiveAlbumViewerState extends State<_LiveAlbumViewer> {
  late PageController _pageCtrl;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              // Capture everything we need at the moment of press, not inside the builder
              final index = _currentIndex;
              if (index >= widget.liveIds.length) return;
              final id = widget.liveIds[index];
              final liveAsset = widget.peerService.getLiveAsset(id);
              if (liveAsset == null) return;

              showModalBottomSheet(
                context: context,
                builder: (_) => Container(
                  color: const Color(0xFF1C1C1C),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 20),
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline,
                                color: Colors.white54, size: 18),
                            const SizedBox(width: 12),
                            Text('Added by ${liveAsset.uploaderName}',
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      ListTile(
                        leading:
                            const Icon(Icons.save_alt, color: Colors.white),
                        title: const Text('Save to Library',
                            style: TextStyle(color: Colors.white)),
                        onTap: () async {
                          Navigator.pop(context);
                          final file = File(liveAsset.path);
                          await PhotoManager.editor.saveImage(
                            await file.readAsBytes(),
                            filename: 'shutr_saved_$id.jpg',
                            title: 'shutr_saved_$id',
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('Saved to library')));
                          }
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_outline,
                            color: Color(0xFFF87171)),
                        title: const Text('Remove from Live Album',
                            style: TextStyle(color: Color(0xFFF87171))),
                        onTap: () {
                          widget.peerService.removeLiveAsset(id);
                          Navigator.pop(context);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemCount: widget.liveIds.length,
        itemBuilder: (_, i) {
          final asset = widget.peerService.getLiveAsset(widget.liveIds[i]);
          if (asset == null) return const SizedBox();
          return InteractiveViewer(
            child: Image.file(File(asset.path), fit: BoxFit.contain),
          );
        },
      ),
    );
  }
}

// ─── Live Selection Bar ───────────────────────────────────────────────────────

class _LiveSelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const _LiveSelectionBar({
    required this.count,
    required this.onDownload,
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
                  child: const Text('Cancel',
                      style: TextStyle(color: Color(0xFF8A8A8A)))),
              const Spacer(),
              TextButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.save_alt, size: 18),
                  label: const Text('Save')),
              TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFFF87171), size: 18),
                  label: const Text('Remove',
                      style: TextStyle(color: Color(0xFFF87171)))),
            ],
          ),
        ),
      ),
    );
  }
}
