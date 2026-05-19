import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'album_detail_page.dart';
import '../services/peer_service.dart';

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});

  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<_AlbumData> _albums = [];
  bool _loading = true;
  int _lastRefresh = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
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
    final peerService = Provider.of<PeerService>(context, listen: false);
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

    final albums = <_AlbumData>[];
    final prefs = await SharedPreferences.getInstance();
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count == 0) continue;

      final firstAsset = await path.getAssetListRange(start: 0, end: 1);
      if (firstAsset.isEmpty) continue;

      AssetEntity thumbnail = firstAsset.first;
      final coverId = prefs.getString('album_cover_${path.id}');
      if (coverId != null && coverId != firstAsset.first.id) {
        final coverAsset = await AssetEntity.fromId(coverId);
        if (coverAsset != null) thumbnail = coverAsset;
      }

      albums.add(_AlbumData(
        path: path,
        count: count,
        thumbnail: thumbnail,
        isLive: peerService.isLive && peerService.activeAlbum?.id == path.id,
      ));
    }

    albums.sort((a, b) {
      if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
      if (a.path.isAll) return -1;
      if (b.path.isAll) return 1;
      return b.count.compareTo(a.count);
    });

    setState(() {
      _albums = albums;
      _loading = false;
    });
  }

  void _showContextMenu(BuildContext context, _AlbumData album, bool isLive) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AlbumContextMenu(album: album, isLive: isLive, onDeleted: () {
            _load();
            if (context.mounted) {
              context.read<ValueNotifier<int>>().value++;
            }
          }),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _maybeRefresh(context.watch<ValueNotifier<int>>());

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF6B8AFF),
          strokeWidth: 1.5,
        ),
      );
    }

    return Consumer<PeerService>(
      builder: (context, peerService, child) {
        final sortedAlbums = List<_AlbumData>.from(_albums);
        for (var album in sortedAlbums) {
          album.isLive = peerService.isLive &&
              peerService.activeAlbum?.id == album.path.id;
        }
        sortedAlbums.sort((a, b) {
          if (a.isLive != b.isLive) return a.isLive ? -1 : 1;
          if (a.path.isAll) return -1;
          if (b.path.isAll) return 1;
          return b.count.compareTo(a.count);
        });

        return Column(
          children: [
            if (peerService.isLive)
              GestureDetector(
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: peerService.sessionCode ?? ''));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Code copied to clipboard'),
                      duration: Duration(seconds: 2),
                      backgroundColor: Color(0xFF1C1C1C),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding:
                      const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Live Code',
                        style: TextStyle(
                          color: Color(0xFF8A8A8A),
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        peerService.sessionCode ?? '',
                        style: const TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        Icons.copy_rounded,
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.5),
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF6B8AFF),
                backgroundColor: const Color(0xFF1C1C1C),
                onRefresh: _load,
                child: GridView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 2,
                    mainAxisSpacing: 2,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: sortedAlbums.length,
                  itemBuilder: (context, i) {
                    final data = sortedAlbums[i];
                    return _AlbumCell(
                      data: data,
                      isLive: data.isLive,
                      onLongPress: () =>
                          _showContextMenu(context, data, data.isLive),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AlbumCell extends StatelessWidget {
  final _AlbumData data;
  final bool isLive;
  final VoidCallback onLongPress;

  const _AlbumCell({
    required this.data,
    required this.isLive,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AlbumDetailPage(
              album: data.path,
              totalCount: data.count,
            ),
          ),
        );
      },
      onLongPress: onLongPress,
      child: Container(
        color: const Color(0xFF0A0A0A),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Hero(
                  tag: 'album_${data.path.id}',
                  child: AssetEntityImage(
                    data.thumbnail,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(400),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    frameBuilder: (_, child, frame, __) {
                      if (frame == null) {
                        return const ColoredBox(color: Color(0xFF1C1C1C));
                      }
                      return child;
                    },
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isLive) ...[
                        _PulsingDot(),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          data.path.name.isEmpty ? 'Unnamed' : data.path.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${data.count} photos',
                    style: const TextStyle(
                      color: Color(0xFF8A8A8A),
                      fontSize: 12,
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
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF4CAF50),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _AlbumContextMenu extends StatelessWidget {
  final _AlbumData album;
  final bool isLive;
  final VoidCallback onDeleted;
  const _AlbumContextMenu(
      {required this.album, required this.isLive, required this.onDeleted});

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = DateTime.now().microsecondsSinceEpoch;
    return List.generate(6, (i) => chars[(rnd + i) % chars.length]).join();
  }

  Future<void> _goLive(BuildContext context) async {
    final code = _generateCode();
    final peerService = Provider.of<PeerService>(context, listen: false);
    try {
      await peerService.goLive(album.path, code);
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF6B8AFF),
            content:
                Text('Album is live!', style: TextStyle(color: Colors.black)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _goOffline(BuildContext context) async {
    final peerService = Provider.of<PeerService>(context, listen: false);
    await peerService.stopLive();
    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Album is now offline')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF444444),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AssetEntityImage(
                    album.thumbnail,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(100),
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.path.name.isEmpty ? 'Unnamed' : album.path.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text('${album.count} photos',
                        style: const TextStyle(
                            color: Color(0xFF8A8A8A), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Color(0x12FFFFFF), height: 1),
          _MenuItem(
            icon: Icon(isLive ? Icons.sensors_off : Icons.sensors,
                color:
                    isLive ? const Color(0xFFF87171) : const Color(0xFF6B8AFF),
                size: 20),
            label: isLive ? 'Go Offline' : 'Go Live',
            labelColor: isLive ? const Color(0xFFF87171) : Colors.white,
            onTap: () => isLive ? _goOffline(context) : _goLive(context),
          ),
          const Divider(color: Color(0x12FFFFFF), height: 1),
          _MenuItem(
            icon: const Icon(Icons.drive_file_rename_outline,
                color: Colors.white, size: 20),
            label: 'Rename',
            onTap: () => Navigator.pop(context),
          ),
          _MenuItem(
            icon: const Icon(Icons.delete_outline,
                color: Color(0xFFF87171), size: 20),
            label: 'Delete',
            labelColor: const Color(0xFFF87171),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1C1C1C),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: const Text('Delete album',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500)),
                  content: Text(
                    'Delete all ${album.count} photos in "${album.path.name}" permanently?',
                    style: const TextStyle(
                        color: Color(0xFF8A8A8A), fontSize: 14, height: 1.5),
                  ),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel',
                            style: TextStyle(color: Color(0xFF8A8A8A)))),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete',
                            style: TextStyle(color: Color(0xFFF87171)))),
                  ],
                ),
              );
              if (confirm != true) return;
              if (context.mounted) Navigator.pop(context);
              final assets = await album.path
                  .getAssetListRange(start: 0, end: album.count);
              await PhotoManager.editor
                  .deleteWithIds(assets.map((a) => a.id).toList());
              onDeleted();
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.labelColor = Colors.white,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            SizedBox(width: 22, child: Center(child: icon)),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                  color: labelColor, fontSize: 15, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumData {
  final AssetPathEntity path;
  final int count;
  final AssetEntity thumbnail;
  bool isLive;

  _AlbumData({
    required this.path,
    required this.count,
    required this.thumbnail,
    this.isLive = false,
  });
}
