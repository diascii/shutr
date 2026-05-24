import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_sheet.dart';
import '../services/peer_service.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/album_card.dart';
import '../widgets/session_manager.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<AlbumData> _albums = [];
  Set<String> _hiddenIds = {};
  List<AlbumData> _hiddenAlbums = [];
  bool _loading = true;
  int _lastRefresh = 0;
  bool _showHidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _maybeRefresh(ValueNotifier<int> refresh) {
    if (refresh.value > _lastRefresh) {
      _lastRefresh = refresh.value;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  Future<void> _load() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (permission != PermissionState.authorized &&
        permission != PermissionState.limited) {
      setState(() => _loading = false);
      return;
    }

    final paths = await PhotoManager.getAssetPathList(
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

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('hidden_albums') ?? [];
    _hiddenIds = raw.toSet();
    final albums = <AlbumData>[];
    final hidden = <AlbumData>[];
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count == 0) continue;

      final coverId = prefs.getString('album_cover_${path.id}');
      AssetEntity thumbnail;
      if (coverId != null) {
        final cover = await AssetEntity.fromId(coverId);
        thumbnail = cover ?? (await path.getAssetListRange(start: 0, end: 1)).first;
      } else {
        final firstAsset = await path.getAssetListRange(start: 0, end: 1);
        if (firstAsset.isEmpty) continue;
        thumbnail = firstAsset.first;
      }

      final data = AlbumData(
        path: path,
        count: count,
        thumbnail: thumbnail,
      );
      if (_hiddenIds.contains(path.id)) {
        hidden.add(data);
      } else {
        albums.add(data);
      }
    }

    albums.sort((a, b) {
      if (a.path.isAll) return -1;
      if (b.path.isAll) return 1;
      return b.count.compareTo(a.count);
    });

    setState(() {
      _albums = albums;
      _hiddenAlbums = hidden;
      _loading = false;
    });
  }

  void _showSessionManager(BuildContext context, PeerService peerService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141414),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ChangeNotifierProvider.value(
        value: peerService,
        child: const SessionManagerSheet(),
      ),
    );
  }

  Future<void> _goOfflineAll(BuildContext context, PeerService peerService) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End all live sessions',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
        content: const Text('This will disconnect all viewers from every live album.',
            style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 14, height: 1.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8A8A8A)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('End All', style: TextStyle(color: Color(0xFFF87171)))),
        ],
      ),
    );
    if (confirm != true) return;

    final albumIds = List<String>.from(peerService.liveAlbumIds);
    for (final id in albumIds) {
      await peerService.goOffline(id);
    }
    if (context.mounted) {
      SnackBarHelper.show(context, message: 'All live sessions ended', type: SnackBarType.info);
    }
  }

  void _showContextMenu(BuildContext context, AlbumData album, bool isLive, {bool isHidden = false}) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => AlbumContextMenu(
        album: album,
        isLive: isLive,
        isHidden: isHidden,
        onDeleted: () {
          _load();
          if (context.mounted) {
            context.read<ValueNotifier<int>>().value++;
          }
        },
        onHidden: () async {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getStringList('hidden_albums') ?? [];
          if (isHidden) {
            raw.remove(album.path.id);
          } else {
            raw.add(album.path.id);
          }
          await prefs.setStringList('hidden_albums', raw);
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _maybeRefresh(context.watch<ValueNotifier<int>>());

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
          strokeWidth: 1.5,
        ),
      );
    }

    if (_albums.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_album_outlined,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.15),
                  size: 72),
              const SizedBox(height: 20),
              Text('No albums yet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      )),
              const SizedBox(height: 8),
              Text('Photos are grouped into albums automatically. Take some photos first.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        height: 1.5,
                      )),
            ],
          ),
        ),
      );
    }

    return Consumer<PeerService>(
      builder: (context, peerService, child) {
        final liveAlbumIds = peerService.liveAlbumIds.toSet();
        final liveAlbums = _albums.where((a) => liveAlbumIds.contains(a.path.id)).toList();
        final nonLive = _albums.where((a) => !liveAlbumIds.contains(a.path.id)).toList();

        return RefreshIndicator(
          color: Theme.of(context).colorScheme.primary,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          onRefresh: _load,
          child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              title: Text(
                'Albums',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
              ),
              centerTitle: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 22),
                  onPressed: () => SettingsSheet.show(context),
                ),
                const SizedBox(width: 8),
              ],
            ),
            if (peerService.isLive)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(
                    children: [
                      Text(
                        'Live',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              fontSize: 11,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${liveAlbums.length}/3',
                          style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: peerService.sessionCode ?? ''));
                          SnackBarHelper.show(context, message: 'Code copied', type: SnackBarType.info);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF4CAF50).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Text(
                                peerService.sessionCode ?? '',
                                style: const TextStyle(
                                  color: Color(0xFF4CAF50),
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.copy_rounded,
                                  color: const Color(0xFF4CAF50).withValues(alpha: 0.5),
                                  size: 14),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FutureBuilder<String?>(
                        future: peerService.serverUrl,
                        builder: (context, snapshot) {
                          final url = snapshot.data;
                          if (url == null) return const SizedBox.shrink();
                          return GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: url));
                              SnackBarHelper.show(context, message: 'URL copied', type: SnackBarType.info);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6B8AFF).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFF6B8AFF).withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.link,
                                      color: const Color(0xFF6B8AFF).withValues(alpha: 0.7),
                                      size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    'URL',
                                    style: const TextStyle(
                                      color: Color(0xFF6B8AFF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.sensors_off,
                            color: Color(0xFFF87171), size: 20),
                        onPressed: () => _goOfflineAll(context, peerService),
                      ),
                      const SizedBox(width: 8),
                      Badge(
                        isLabelVisible: peerService.pendingUsers.isNotEmpty,
                        smallSize: 8,
                        backgroundColor: const Color(0xFFF87171),
                        child: IconButton(
                          icon: const Icon(Icons.people_outline,
                              color: Color(0xFF4CAF50), size: 20),
                          onPressed: () => _showSessionManager(context, peerService),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (peerService.isLive)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => AlbumCell(
                      data: liveAlbums[i],
                      isLive: true,
                      onLongPress: () => _showContextMenu(context, liveAlbums[i], true),
                    ),
                    childCount: liveAlbums.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                    childAspectRatio: 0.85,
                  ),
                ),
              ),
            if (peerService.isLive)
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  'Albums',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        fontSize: 11,
                      ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              sliver: SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => AlbumCell(
                    data: nonLive[i],
                    isLive: false,
                    onLongPress: () => _showContextMenu(context, nonLive[i], false),
                  ),
                  childCount: nonLive.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                  childAspectRatio: 0.85,
                ),
              ),
            ),
            if (_showHidden && _hiddenAlbums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: GestureDetector(
                  onTap: () => setState(() => _showHidden = false),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
                    child: Row(
                      children: [
                        Icon(Icons.visibility_off,
                            color: Theme.of(context).colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.4),
                            size: 14),
                        const SizedBox(width: 8),
                        Text(
                          'Hidden',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                fontSize: 11,
                              ),
                        ),
                        const Spacer(),
                        Icon(Icons.chevron_left,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.2),
                            size: 16),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => AlbumCell(
                      data: _hiddenAlbums[i],
                      isLive: false,
                      onLongPress: () => _showContextMenu(context, _hiddenAlbums[i], false, isHidden: true),
                    ),
                    childCount: _hiddenAlbums.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                    childAspectRatio: 0.85,
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: _AlbumRevealZone(
                showHidden: _showHidden,
                onReveal: () => setState(() => _showHidden = true),
              ),
            ),
          ],
        ),
        );
      },
    );
    }
}

class _AlbumRevealZone extends StatefulWidget {
  final bool showHidden;
  final VoidCallback onReveal;

  const _AlbumRevealZone({
    required this.showHidden,
    required this.onReveal,
  });

  @override
  State<_AlbumRevealZone> createState() => _AlbumRevealZoneState();
}

class _AlbumRevealZoneState extends State<_AlbumRevealZone> {
  Timer? _timer;
  double _progress = 0;
  bool _holding = false;

  void _startHold() {
    if (widget.showHidden) return;
    _holding = true;
    _progress = 0;
    if (mounted) setState(() {});
    _timer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      _progress += 1 / 100;
      if (mounted) setState(() {});
      if (_progress >= 1) {
        t.cancel();
        if (mounted) {
          HapticFeedback.heavyImpact();
          widget.onReveal();
        }
      }
    });
  }

  void _cancelHold() {
    _timer?.cancel();
    if (_holding && mounted) {
      setState(() {});
    }
    _holding = false;
    _progress = 0;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.showHidden) {
      return const SizedBox(height: 32);
    }
    return GestureDetector(
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _cancelHold(),
      onLongPressCancel: _cancelHold,
      child: Container(
        height: 80,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: _progress > 0
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 3,
                        backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                        valueColor: AlwaysStoppedAnimation(
                          theme.colorScheme.onSurface.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Hold to reveal hidden albums',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                          fontSize: 10,
                        )),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
