import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import '../utils/snackbar_helper.dart';

class RemotePhotoViewer extends StatefulWidget {
  final List<dynamic> assets;
  final int initialIndex;
  final String baseUrl;

  const RemotePhotoViewer({
    super.key,
    required this.assets,
    required this.initialIndex,
    required this.baseUrl,
  });

  @override
  State<RemotePhotoViewer> createState() => _RemotePhotoViewerState();
}

class _RemotePhotoViewerState extends State<RemotePhotoViewer> {
  late PageController _pageCtrl;
  int _currentIndex = 0;
  bool _uiVisible = true;
  double _dragOffset = 0;
  double _dragOpacity = 1.0;
  bool _zoomedIn = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheAdjacent());
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _precacheAdjacent() {
    for (final offset in [-1, 1, -2, 2]) {
      final idx = _currentIndex + offset;
      if (idx < 0 || idx >= widget.assets.length) continue;
      final id = widget.assets[idx]['id'] as String;
      unawaited(precacheImage(
        NetworkImage('${widget.baseUrl}/photo/$id'),
        context,
        onError: (_, __) {},
      ));
    }
  }

  void _pop() => Navigator.pop(context);

  void _toggleUI() => setState(() {
        _uiVisible = !_uiVisible;
        if (!_uiVisible) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
      });

  Future<void> _download(String id) async {
    try {
      final response = await http.get(Uri.parse('${widget.baseUrl}/photo/$id'));
      if (response.statusCode == 200) {
        await PhotoManager.editor.saveImage(
          response.bodyBytes,
          filename: 'shutr_$id.jpg',
          title: 'shutr_$id',
        );
        if (mounted) {
          SnackBarHelper.show(context, message: 'Saved to gallery', type: SnackBarType.success);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.show(context, message: 'Download failed: $e', type: SnackBarType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: _dragOpacity),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              WidgetsBinding.instance.addPostFrameCallback((_) => _precacheAdjacent());
            },
            itemCount: widget.assets.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: _toggleUI,
              onVerticalDragUpdate: _zoomedIn
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
              onVerticalDragEnd: _zoomedIn
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
                child: ZoomableRemoteImage(
                  asset: widget.assets[i],
                  baseUrl: widget.baseUrl,
                  onScaleChanged: (zoomed) =>
                      setState(() => _zoomedIn = zoomed),
                ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            top: _uiVisible && _dragOffset == 0 ? 0 : -120,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
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
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                      onPressed: _pop,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.white, size: 24),
                      onPressed: () {
                        final asset = widget.assets[_currentIndex];
                        showModalBottomSheet(
                          context: context,
                          backgroundColor: theme.colorScheme.surfaceContainerHigh,
                          shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                          builder: (_) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.download_rounded),
                                  title: const Text('Download to device'),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _download(asset['id']);
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ZoomableRemoteImage extends StatefulWidget {
  final Map<String, dynamic> asset;
  final String baseUrl;
  final ValueChanged<bool>? onScaleChanged;
  const ZoomableRemoteImage({super.key, required this.asset, required this.baseUrl, this.onScaleChanged});
  @override
  State<ZoomableRemoteImage> createState() => _ZoomableRemoteImageState();
}

class _ZoomableRemoteImageState extends State<ZoomableRemoteImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _ctrl = TransformationController();
  late AnimationController _animCtrl;
  Animation<Matrix4>? _anim;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))
      ..addListener(() { if (_anim != null) _ctrl.value = _anim!.value; });
    _ctrl.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final zoomed = _ctrl.value.getMaxScaleOnAxis() > 1.05;
    widget.onScaleChanged?.call(zoomed);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    final scale = _ctrl.value.getMaxScaleOnAxis();
    final endMatrix = scale > 1.1 ? Matrix4.identity() : (Matrix4.identity()
      ..translateByDouble(-details.localPosition.dx * 2, -details.localPosition.dy * 2, 0, 1)
      ..scaleByDouble(3.0, 3.0, 1.0, 1));
    _anim = Matrix4Tween(begin: _ctrl.value, end: endMatrix).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward(from: 0);
  }

  @override
  void dispose() { _ctrl.removeListener(_onTransformChanged); _ctrl.dispose(); _animCtrl.dispose(); super.dispose(); }

  ImageProvider _imageProvider() {
    return NetworkImage('${widget.baseUrl}/photo/${widget.asset['id']}');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: () {},
      child: InteractiveViewer(
        minScale: 1.0,
        maxScale: 4.0,
        transformationController: _ctrl,
        child: Image(
          image: _imageProvider(),
          fit: BoxFit.contain,
          frameBuilder: (_, child, frame, __) {
            if (frame != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_loaded) setState(() => _loaded = true);
              });
              return child;
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: 0.3,
                  child: Image.network(
                    '${widget.baseUrl}/thumb/${widget.asset['id']}',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
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
            );
          },
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image, color: Colors.white24, size: 48),
          ),
        ),
      ),
    );
  }
}
