import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class PhotoViewer extends StatefulWidget {
  final List<AssetEntity> assets;
  final int initialIndex;
  final VoidCallback? onLoadMore;

  const PhotoViewer({
    super.key,
    required this.assets,
    required this.initialIndex,
    this.onLoadMore,
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

  // Track rotations per asset ID (0, 1, 2, 3 for 0, 90, 180, 270 degrees)
  final Map<String, int> _rotations = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleUI() => setState(() => _uiVisible = !_uiVisible);

  void _rotate() {
    final asset = widget.assets[_currentIndex];
    setState(() {
      final current = _rotations[asset.id] ?? 0;
      _rotations[asset.id] = (current + 1) % 4;
      HapticFeedback.lightImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            // Background that fades
            Positioned.fill(
              child: Opacity(
                opacity: _dragOpacity,
                child: Container(color: Colors.black),
              ),
            ),

            // Photo pages
            PageView.builder(
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
                            _dragOpacity =
                                (1 - (_dragOffset.abs() / 500)).clamp(0.0, 1.0);
                            _uiVisible = false;
                          });
                        },
                  onVerticalDragEnd: _currentScale > 1.0
                      ? null
                      : (details) {
                          if (_dragOffset.abs() > 150 ||
                              details.primaryVelocity!.abs() > 800) {
                            Navigator.pop(context);
                          } else {
                            setState(() {
                              _dragOffset = 0;
                              _dragOpacity = 1.0;
                              _uiVisible = true;
                            });
                          }
                        },
                  child: Transform.translate(
                    offset: Offset(0, _dragOffset),
                    child: _ZoomablePhoto(
                      asset: asset,
                      isCurrent: i == _currentIndex,
                      turns: (_rotations[asset.id] ?? 0) * 0.25,
                      onScaleChanged: (scale) =>
                          setState(() => _currentScale = scale),
                    ),
                  ),
                );
              },
            ),

            // Top bar
            AnimatedOpacity(
              opacity: _uiVisible && _dragOffset == 0 ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB3000000), Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white, size: 22),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.rotate_right,
                              color: Colors.white, size: 22),
                          onPressed: _rotate,
                        ),
                        IconButton(
                          icon: const Icon(Icons.share_outlined,
                              color: Colors.white, size: 22),
                          onPressed: () => _share(widget.assets[_currentIndex]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.more_vert,
                              color: Colors.white, size: 22),
                          onPressed: () =>
                              _showInfo(widget.assets[_currentIndex]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _uiVisible && _dragOffset == 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Colors.transparent],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                  child: _BottomMeta(asset: widget.assets[_currentIndex]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(AssetEntity asset) async {
    final file = await asset.file;
    if (file == null) return;
    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _showInfo(AssetEntity asset) async {
    final file = await asset.file;
    final fileStat = file != null ? await file.stat() : null;
    final dt = asset.createDateTime;
    final months = [
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
    final dateStr =
        '${months[dt.month - 1]} ${dt.day}, ${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final sizeBytes = fileStat?.size ?? 0;
    final sizeMB = (sizeBytes / (1024 * 1024)).toStringAsFixed(2);
    final latLng = await asset.latlngAsync();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
                          borderRadius: BorderRadius.circular(2))),
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
                    '${asset.width} × ${asset.height}'),
                _infoRow(Icons.sd_card_outlined, 'File size', '$sizeMB MB'),
                if (file != null)
                  _infoRow(Icons.insert_drive_file_outlined, 'Filename',
                      file.path.split('/').last),
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
                  style:
                      const TextStyle(color: Color(0xFF8A8A8A), fontSize: 11)),
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

  const _ZoomablePhoto({
    required this.asset,
    required this.isCurrent,
    required this.turns,
    required this.onScaleChanged,
  });

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final TransformationController _ctrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final scale = _ctrl.value.getMaxScaleOnAxis();
      widget.onScaleChanged(scale);
    });
  }

  @override
  void didUpdateWidget(_ZoomablePhoto old) {
    super.didUpdateWidget(old);
    // Reset zoom when rotating
    if (old.turns != widget.turns) {
      _ctrl.value = Matrix4.identity();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: widget.isCurrent ? widget.asset.id : 'disabled_${widget.asset.id}',
      child: InteractiveViewer(
        transformationController: _ctrl,
        minScale: 1.0,
        maxScale: 4.0,
        child: Center(
          child: AnimatedRotation(
            turns: widget.turns,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: AssetEntityImage(
              widget.asset,
              isOriginal: true,
              fit: BoxFit.contain,
              frameBuilder: (_, child, frame, __) {
                if (frame == null) {
                  return AssetEntityImage(
                    widget.asset,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(600),
                    fit: BoxFit.contain,
                  );
                }
                return child;
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomMeta extends StatefulWidget {
  final AssetEntity asset;
  const _BottomMeta({required this.asset});

  @override
  State<_BottomMeta> createState() => _BottomMetaState();
}

class _BottomMetaState extends State<_BottomMeta> {
  String _date = '';
  String _size = '';

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  @override
  void didUpdateWidget(_BottomMeta old) {
    super.didUpdateWidget(old);
    if (old.asset.id != widget.asset.id) _loadMeta();
  }

  Future<void> _loadMeta() async {
    final asset = widget.asset;
    final dt = asset.createDateTime;

    final months = [
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

    setState(() {
      _date = '${months[dt.month - 1]} ${dt.day}, ${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      _size = '${asset.width} × ${asset.height}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _date,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _size,
          style: const TextStyle(
            color: Color(0xB3FFFFFF),
            fontSize: 13,
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }
}
