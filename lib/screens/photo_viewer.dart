import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:exif/exif.dart';
import '../utils/snackbar_helper.dart';
import '../services/peer_service.dart';

class PhotoViewer extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;
  final VoidCallback? onLoadMore;
  final ValueChanged<AssetEntity>? onSetCover;

  const PhotoViewer({
    super.key,
    required this.assets,
    required this.initialIndex,
    this.onLoadMore,
    this.onSetCover,
  });

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late final PageController _pageCtrl;
  late int _currentIndex;
  bool _uiVisible = true;
  double _dragOffset = 0;
  double _dragOpacity = 1.0;
  double _currentScale = 1.0;
  double _topPadding = 0;
  Size _screenSize = Size.zero;

  final Map<String, int> _rotations = {};
  final Set<String> _deletedIds = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final view = View.of(context);
        final physicalSize = view.physicalSize;
        final dpr = view.devicePixelRatio;
        final logicalSize = Size(physicalSize.width / dpr, physicalSize.height / dpr);
        final viewPadding = MediaQuery.of(context).viewPadding;
        setState(() {
          _topPadding = viewPadding.top > 0 ? viewPadding.top : MediaQuery.of(context).padding.top;
          _screenSize = logicalSize;
        });
      }
    });
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _pageCtrl.dispose();
    super.dispose();
  }

  void _pop() {
    Navigator.pop(context, _deletedIds.toList());
  }

  void _toggleUI() {
    final nextVisible = !_uiVisible;
    setState(() => _uiVisible = nextVisible);

    if (nextVisible) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _rotate() {
    final asset = widget.assets[_currentIndex];
    setState(() {
      final current = _rotations[asset.id] ?? 0;
      _rotations[asset.id] = (current + 1) % 4;
      HapticFeedback.lightImpact();
    });
  }

  void _showMenu(AssetEntity asset) {
    final peerService = Provider.of<PeerService>(context, listen: false);
    final isLiveAsset = peerService.isLive &&
        peerService.allLiveContributionIds().contains(asset.id);

    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        color: const Color(0xFF1C1C1C),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLiveAsset) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, color: Colors.white54, size: 18),
                    const SizedBox(width: 12),
                    Text(
                      'Added by ${peerService.getLiveAsset(asset.id)?.uploaderName ?? "Unknown"}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
            ],
            if (isLiveAsset)
              ListTile(
                leading: const Icon(Icons.save_alt, color: Colors.white),
                title: const Text('Save to Library', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final liveAsset = peerService.getLiveAsset(asset.id);
                  if (liveAsset != null) {
                    final file = File(liveAsset.path);
                    await PhotoManager.editor.saveImage(
                      await file.readAsBytes(),
                      filename: 'shutr_saved_${asset.id}.jpg',
                      title: 'shutr_saved_${asset.id}',
                    );
                    if (mounted) {
                      SnackBarHelper.show(context, message: 'Saved to library', type: SnackBarType.success);
                    }
                  }
                },
              ),
            if (isLiveAsset)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFF87171)),
                title: const Text('Remove from Live Album', style: TextStyle(color: Color(0xFFF87171))),
                onTap: () {
                  Navigator.pop(context);
                  peerService.removeLiveAsset(asset.id);
                  _deletedIds.add(asset.id);
                  _pop();
                },
              ),
            if (!isLiveAsset && widget.onSetCover != null)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: Colors.white),
                title: const Text('Set as Album Cover', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onSetCover?.call(asset);
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white),
              title: const Text('Details', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showInfo(asset);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Color(0xFFF87171)),
              title: const Text('Delete', style: TextStyle(color: Color(0xFFF87171))),
              onTap: () async {
                Navigator.pop(context);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => const _DeleteDialog(count: 1),
                );
                if (confirm == true) {
                  _deletedIds.add(asset.id);
                  _pop();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined, color: Colors.white),
              title: const Text('Share', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                if (asset.type == AssetType.video) {
                  final uri = await asset.getMediaUrl();
                  if (uri != null) {
                    await Share.shareXFiles([XFile(uri)]);
                  }
                } else {
                  final file = await asset.file;
                  if (file != null) {
                    await Share.shareXFiles([XFile(file.path)]);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVideo(AssetEntity asset) async {
    final uri = await asset.getMediaUrl();
    if (uri != null && mounted) {
      await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && result == null && _deletedIds.isNotEmpty) {}
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          children: [
            if (_dragOffset != 0)
              Positioned.fill(
                child: Opacity(
                  opacity: _dragOpacity,
                  child: Container(color: Colors.black),
                ),
              ),
            RepaintBoundary(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: widget.assets.length,
                physics: (_dragOffset != 0 || _currentScale > 1.0)
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(),
                onPageChanged: (i) {
                  setState(() {
                    _currentIndex = i;
                    _currentScale = 1.0;
                  });
                  if (i >= widget.assets.length - 5) {
                    widget.onLoadMore?.call();
                  }
                },
                itemBuilder: (_, i) {
                  final asset = widget.assets[i];
                  return GestureDetector(
                    onTap: _toggleUI,
                    onVerticalDragUpdate: _currentScale > 1.0
                        ? null
                        : (details) {
                            setState(() {
                              _dragOffset += details.delta.dy;
                              _dragOpacity = (1 - (_dragOffset.abs() / 500))
                                  .clamp(0.0, 1.0);
                              if (_uiVisible) {
                                _uiVisible = false;
                                SystemChrome.setEnabledSystemUIMode(
                                    SystemUiMode.immersiveSticky);
                              }
                            });
                          },
                    onVerticalDragEnd: _currentScale > 1.0
                        ? null
                        : (details) {
                            if (_dragOffset.abs() > 150 ||
                                details.primaryVelocity!.abs() > 800) {
                              _pop();
                            } else {
                              setState(() {
                                _dragOffset = 0;
                                _dragOpacity = 1.0;
                                if (!_uiVisible) {
                                  _uiVisible = true;
                                  SystemChrome.setEnabledSystemUIMode(
                                      SystemUiMode.edgeToEdge);
                                }
                              });
                            }
                          },
                    child: Transform.translate(
                      offset: Offset(0, _dragOffset),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _ZoomablePhoto(
                            asset: asset,
                            isCurrent: i == _currentIndex,
                            turns: (_rotations[asset.id] ?? 0) * 0.25,
                            onScaleChanged: (scale) =>
                                setState(() => _currentScale = scale),
                            screenSize: _screenSize,
                          ),
                          if (asset.type == AssetType.video)
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: () => _openVideo(asset),
                                child: Center(
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.play_arrow,
                                        color: Colors.white, size: 40),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Top Bar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              top: _uiVisible && _dragOffset == 0 ? 0 : -120,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(top: _topPadding),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Colors.transparent],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back,
                            color: Colors.white, size: 24),
                        onPressed: _pop,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.rotate_right,
                            color: Colors.white, size: 24),
                        onPressed: _rotate,
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert,
                            color: Colors.white, size: 24),
                        onPressed: () => _showMenu(widget.assets[_currentIndex]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInfo(AssetEntity asset) async {
    File? file;
    if (asset.type != AssetType.video) {
      file = await asset.file;
    }
    final fileStat = file != null ? await file.stat() : null;
    final dt = asset.createDateTime;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateStr =
        '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final sizeBytes = fileStat?.size ?? 0;
    final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(2);
    final latLng = await asset.latlngAsync();

    Map<String, IfdTag>? exifData;
    if (file != null) {
      try {
        final bytes = await file.readAsBytes();
        exifData = await readExifFromBytes(bytes);
      } catch (_) {}
    }

    String? cameraMake, cameraModel, iso, aperture, focalLength;
    if (exifData != null) {
      cameraMake = exifData['Image Make']?.printable;
      cameraModel = exifData['Image Model']?.printable;
      iso = exifData['EXIF ISOSpeedRatings']?.printable;
      aperture = exifData['EXIF FNumber']?.printable;
      if (aperture != null && aperture.contains('/')) {
        final parts = aperture.split('/');
        final numVal = double.tryParse(parts[0]) ?? 0;
        final denVal = double.tryParse(parts[1]) ?? 1;
        if (denVal > 0) {
          aperture = 'f/${(numVal / denVal).toStringAsFixed(1)}';
        }
      }
      final fl = exifData['EXIF FocalLength']?.printable;
      if (fl != null && fl.contains('/')) {
        final parts = fl.split('/');
        final numVal = double.tryParse(parts[0]) ?? 0;
        final denVal = double.tryParse(parts[1]) ?? 1;
        if (denVal > 0) {
          focalLength = '${(numVal / denVal).toStringAsFixed(0)}mm';
        }
      } else if (fl != null) {
        focalLength = '${double.tryParse(fl)?.toStringAsFixed(0) ?? fl}mm';
      }
    }

    if (!mounted) return;
    // ignore: use_build_context_synchronously
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1C1C1C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF444444),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Info',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 16),
                _infoRow(Icons.calendar_today_outlined, 'Date', dateStr),
                _infoRow(Icons.photo_size_select_actual_outlined, 'Resolution',
                    '${asset.width} x ${asset.height}'),
                if (asset.type == AssetType.video)
                  _infoRow(Icons.timer_outlined, 'Duration',
                      '${Duration(seconds: asset.duration).inMinutes}:${(Duration(seconds: asset.duration).inSeconds % 60).toString().padLeft(2, '0')}'),
                _infoRow(Icons.sd_card_outlined, 'File size', '$sizeMB MB'),
                if (file != null)
                  _infoRow(Icons.insert_drive_file_outlined, 'Filename',
                      file.path.split('/').last),
                if (cameraMake != null || cameraModel != null)
                  _infoRow(Icons.camera_alt_outlined, 'Camera',
                      '${cameraMake ?? ''} ${cameraModel ?? ''}'.trim()),
                if (iso != null)
                  _infoRow(Icons.iso_outlined, 'ISO', 'ISO $iso'),
                if (aperture != null)
                  _infoRow(Icons.lens_blur, 'Aperture', aperture),
                if (focalLength != null)
                  _infoRow(Icons.center_focus_strong_outlined, 'Focal length', focalLength),
                if (latLng != null && latLng.latitude != 0)
                  _infoRow(Icons.location_on_outlined, 'Location',
                      '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF8A8A8A), size: 18),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 11)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  final AssetEntity asset;
  final bool isCurrent;
  final double turns;
  final ValueChanged<double> onScaleChanged;
  final Size screenSize;

  const _ZoomablePhoto({
    required this.asset,
    required this.isCurrent,
    required this.turns,
    required this.onScaleChanged,
    required this.screenSize,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto>
    with SingleTickerProviderStateMixin {
  final TransformationController _ctrl = TransformationController();
  late AnimationController _animCtrl;
  Animation<Matrix4>? _anim;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_anim != null) {
          _ctrl.value = _anim!.value;
        }
      });

    _ctrl.addListener(() {
      final scale = _ctrl.value.getMaxScaleOnAxis();
      widget.onScaleChanged(scale);
    });
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    final currentScale = _ctrl.value.getMaxScaleOnAxis();
    final targetScale = currentScale > 1.1 ? 1.0 : 3.0;

    final Matrix4 endMatrix;
    if (targetScale == 1.0) {
      endMatrix = Matrix4.identity();
    } else {
      final x = details.localPosition.dx;
      final y = details.localPosition.dy;
      endMatrix = Matrix4.identity()
        ..translateByDouble(x, y, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0)
        ..translateByDouble(-x, -y, 0.0, 1.0);
    }

    _anim = Matrix4Tween(
      begin: _ctrl.value,
      end: endMatrix,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward(from: 0);
  }

  @override
  void didUpdateWidget(_ZoomablePhoto old) {
    super.didUpdateWidget(old);
    if (old.asset.id != widget.asset.id) {
      _loaded = false;
    }
    if (old.turns != widget.turns) {
      _ctrl.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: widget.isCurrent ? widget.asset.id : 'disabled_${widget.asset.id}',
      child: SizedBox(
        width: widget.screenSize.width,
        height: widget.screenSize.height,
        child: GestureDetector(
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: () {},
          child: InteractiveViewer(
            transformationController: _ctrl,
            minScale: 1.0,
            maxScale: 4.0,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: AnimatedRotation(
                    turns: widget.turns,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: AssetEntityImage(
                      widget.asset,
                      isOriginal: false,
                      thumbnailSize: ThumbnailSize(
                        (widget.screenSize.width * 2).clamp(1080, 4000).toInt(),
                        (widget.screenSize.height * 2).clamp(1920, 4000).toInt(),
                      ),
                      fit: BoxFit.contain,
                      frameBuilder: (_, child, frame, __) {
                        if (frame != null && !_loaded) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) setState(() => _loaded = true);
                          });
                          return child;
                        }
                        if (frame == null && !_loaded) {
                          return AssetEntityImage(
                            widget.asset,
                            isOriginal: false,
                            thumbnailSize: const ThumbnailSize.square(200),
                            fit: BoxFit.contain,
                          );
                        }
                        return child;
                      },
                    ),
                  ),
                ),
                if (!_loaded)
                  const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    ),
                  ),
              ],
            ),
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
        'Delete photo',
        style: TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
      ),
      content: const Text(
        'Permanently delete this photo from your device?',
        style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 14, height: 1.5),
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