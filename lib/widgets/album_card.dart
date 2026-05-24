import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import '../utils/snackbar_helper.dart';
import '../screens/album_detail_page.dart';
import '../services/peer_service.dart';

class AlbumData {
  final AssetPathEntity path;
  final int count;
  final AssetEntity thumbnail;

  AlbumData({
    required this.path,
    required this.count,
    required this.thumbnail,
  });
}

class AlbumCell extends StatelessWidget {
  final AlbumData data;
  final bool isLive;
  final VoidCallback onLongPress;

  const AlbumCell({
    super.key,
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
                        const PulsingDot(),
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

class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
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

class AlbumContextMenu extends StatelessWidget {
  final AlbumData album;
  final bool isLive;
  final bool isHidden;
  final VoidCallback onDeleted;
  final VoidCallback? onHidden;

  const AlbumContextMenu({
    super.key,
    required this.album,
    required this.isLive,
    this.isHidden = false,
    required this.onDeleted,
    this.onHidden,
  });

  Future<void> _goLive(BuildContext context) async {
    final count = await album.path.assetCountAsync;
    if (count >= 500) {
      if (context.mounted) {
        Navigator.pop(context);
        SnackBarHelper.show(context, message: 'Album exceeds 500 photos and cannot go live', type: SnackBarType.error);
      }
      return;
    }
    final peerService = Provider.of<PeerService>(context, listen: false);
    final success = await peerService.goLive(album.path);
    if (context.mounted) {
      Navigator.pop(context);
      if (success) {
        SnackBarHelper.show(context, message: 'Album is live!', type: SnackBarType.success);
      } else {
        SnackBarHelper.show(context, message: 'Max 3 live albums. Go offline on one first.', type: SnackBarType.error);
      }
    }
  }

  Future<void> _goOffline(BuildContext context) async {
    final peerService = Provider.of<PeerService>(context, listen: false);
    await peerService.goOffline(album.path.id);
    if (context.mounted) {
      Navigator.pop(context);
      SnackBarHelper.show(context, message: 'Album is now offline', type: SnackBarType.info);
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
          MenuItem(
            icon: Icon(isLive ? Icons.sensors_off : Icons.sensors,
                color: isLive ? const Color(0xFFF87171) : const Color(0xFF6B8AFF),
                size: 20),
            label: isLive ? 'Go Offline' : 'Go Live',
            labelColor: isLive ? const Color(0xFFF87171) : Colors.white,
            onTap: () => isLive ? _goOffline(context) : _goLive(context),
          ),
          if (!isLive)
            MenuItem(
              icon: Icon(isHidden ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white54, size: 20),
              label: isHidden ? 'Unhide Album' : 'Hide Album',
              labelColor: Colors.white54,
              onTap: () {
                Navigator.pop(context);
                onHidden?.call();
              },
            ),
          if (!isLive)
            const Divider(color: Color(0x12FFFFFF), height: 1),
          MenuItem(
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
              if (context.mounted) {
                SnackBarHelper.show(context, message: 'Album "${album.path.name}" deleted', type: SnackBarType.success);
              }
              onDeleted();
            },
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

class MenuItem extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const MenuItem({
    super.key,
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
