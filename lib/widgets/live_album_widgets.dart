import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../utils/snackbar_helper.dart';
import '../services/peer_service.dart';

class LiveAlbumViewer extends StatefulWidget {
  final int initialIndex;
  final List<String> liveIds;
  final PeerService peerService;

  const LiveAlbumViewer({
    super.key,
    required this.initialIndex,
    required this.liveIds,
    required this.peerService,
  });

  @override
  State<LiveAlbumViewer> createState() => _LiveAlbumViewerState();
}

class _LiveAlbumViewerState extends State<LiveAlbumViewer> {
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
                        leading: const Icon(Icons.save_alt, color: Colors.white),
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
                            SnackBarHelper.show(context, message: 'Saved to library', type: SnackBarType.success);
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

class LiveSelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  const LiveSelectionBar({
    super.key,
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
