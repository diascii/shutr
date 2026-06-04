import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/snackbar_helper.dart';
import '../utils/gallery_utils.dart';
import 'remote_photo_viewer.dart';

class AlbumThumbnail extends StatefulWidget {
  final String albumId;
  final String baseUrl;

  const AlbumThumbnail({
    super.key,
    required this.albumId,
    required this.baseUrl,
  });

  @override
  State<AlbumThumbnail> createState() => _AlbumThumbnailState();
}

class _AlbumThumbnailState extends State<AlbumThumbnail> {
  String? _thumbUrl;

  @override
  void initState() {
    super.initState();
    _loadThumb();
  }

  Future<void> _loadThumb() async {
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/assets/${widget.albumId}'));
      if (res.statusCode == 200) {
        final assets = jsonDecode(res.body) as List;
        if (assets.isNotEmpty) {
          setState(() {
            _thumbUrl = '${widget.baseUrl}/thumb/${assets[0]['id']}';
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_thumbUrl == null) {
      return const ColoredBox(color: Color(0xFF1C1C1C));
    }
    return Image.network(
      _thumbUrl!,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          Container(color: theme.colorScheme.surfaceContainer),
    );
  }
}

class GuestAlbumView extends StatefulWidget {
  final Map<String, dynamic> album;
  final String baseUrl;
  final ValueNotifier<String> roleNotifier;
  final int uploadLimit;
  final int uploadCount;
  final WebSocketChannel? socket;
  final ValueChanged<int> onCountChange;
  final String nickname;

  const GuestAlbumView({
    super.key,
    required this.album,
    required this.baseUrl,
    required this.roleNotifier,
    required this.uploadLimit,
    required this.uploadCount,
    required this.socket,
    required this.onCountChange,
    required this.nickname,
  });

  @override
  State<GuestAlbumView> createState() => _GuestAlbumViewState();
}

class _GuestAlbumViewState extends State<GuestAlbumView> {
  List<dynamic> _assets = [];
  bool _loading = true;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  Set<String> _downloadedIds = {};

  String get _albumId => widget.album['id'] as String;

  @override
  void initState() {
    super.initState();
    _refresh();
    _loadDownloaded();
  }

  Future<void> _loadDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    _downloadedIds = (prefs.getStringList('downloaded_photos') ?? []).toSet();
  }

  Future<void> _markDownloaded(String id) async {
    _downloadedIds.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('downloaded_photos', _downloadedIds.toList());
  }

  Future<void> _refresh() async {
    try {
      final res = await http.get(Uri.parse('${widget.baseUrl}/assets/$_albumId'));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          _assets = jsonDecode(res.body);
          _loading = false;
        });
        widget.onCountChange(_assets.length);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _uploadPhoto() async {
    if (widget.roleNotifier.value != 'contributor') {
      SnackBarHelper.show(context, message: 'Only contributors can upload.', type: SnackBarType.warning);
      return;
    }

    final picker = ImagePicker();
    final List<XFile> files = await picker.pickMultiImage();
    if (files.isEmpty) return;
    if (!mounted) return;

    final currentCount = _assets.where((a) => a['isLive'] == true && a['uploader'] == widget.album['name']).length;
    if (currentCount + files.length > widget.uploadLimit) {
      SnackBarHelper.show(context, message: 'Upload limit reached. You can only add ${widget.uploadLimit - currentCount} more.', type: SnackBarType.warning);
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Uploading...')));

    for (var file in files) {
      final size = await file.length();
      if (size > 10 * 1024 * 1024) {
        if (mounted) SnackBarHelper.show(context, message: 'Skipped ${file.name} (over 10MB)', type: SnackBarType.warning);
        continue;
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final encodedName = Uri.encodeComponent(widget.nickname);
      final response = await http
          .post(Uri.parse('${widget.baseUrl}/upload/$encodedName/$_albumId'), body: bytes);

      if (!mounted) return;
      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: ${response.body}')));
        return;
      }
    }

    if (mounted) {
      SnackBarHelper.show(context, message: 'All photos uploaded!', type: SnackBarType.success);
      _refresh();
    }
  }

  void _cancelSelection() => setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });

  void _selectAll() => setState(() {
        _selectedIds.addAll(_assets.map((a) => a['id'] as String));
        _selectionMode = true;
      });

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteDialog(count: _selectedIds.length, single: _selectedIds.length == 1),
    );
    if (confirm != true) return;
    for (final id in _selectedIds) {
      final asset = _assets.firstWhere((a) => a['id'] == id, orElse: () => null);
      if (asset != null && asset['isLive'] == true) {
        await http.delete(Uri.parse('${widget.baseUrl}/photo/$id/${widget.nickname}'));
      }
    }
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
    _refresh();
  }

  // ─── Thumbnail Cache ──────────────────────────────────────────────────────────

  String? _thumbsCacheDir;

  Future<String> _getThumbsCacheDir() async {
    if (_thumbsCacheDir != null) return _thumbsCacheDir!;
    final temp = await getTemporaryDirectory();
    _thumbsCacheDir = '${temp.path}/shutr_live/thumbs';
    await Directory(_thumbsCacheDir!).create(recursive: true);
    return _thumbsCacheDir!;
  }

  Future<File?> _cachedThumbFile(String id) async {
    final dir = await _getThumbsCacheDir();
    final file = File('$dir/$id.jpg');
    if (await file.exists()) return file;
    return null;
  }

  Future<void> _cacheThumb(String id, List<int> bytes) async {
    final dir = await _getThumbsCacheDir();
    await File('$dir/$id.jpg').writeAsBytes(bytes);
  }

  Widget _buildThumb(dynamic asset, ThemeData theme) {
    final id = asset['id'] as String;
    return FutureBuilder<File?>(
      future: _cachedThumbFile(id),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data != null) {
          return Image.file(
            snapshot.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: theme.colorScheme.surfaceContainer),
          );
        }
        return Image.network(
          '${widget.baseUrl}/thumb/$id',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: theme.colorScheme.surfaceContainer),
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              _loadAndCacheThumb(id);
              return child;
            }
            return Container(color: theme.colorScheme.surfaceContainer);
          },
        );
      },
    );
  }

  void _loadAndCacheThumb(String id) async {
    try {
      final response = await http.get(Uri.parse('${widget.baseUrl}/thumb/$id'));
      if (response.statusCode == 200) {
        _cacheThumb(id, response.bodyBytes);
      }
    } catch (_) {}
  }

  // ─── Downloads ────────────────────────────────────────────────────────────────

  Future<void> _downloadSelected() async {
    final toDownload =
        _assets.where((a) => _selectedIds.contains(a['id'])).toList();

    int saved = 0;
    for (var assetData in toDownload) {
      final response =
          await http.get(Uri.parse('${widget.baseUrl}/photo/${assetData['id']}'));
      if (!mounted) return;
      if (response.statusCode == 200) {
        await PhotoManager.editor.saveImage(
          response.bodyBytes,
          filename: 'shutr_${DateTime.now().millisecondsSinceEpoch}.jpg',
          title: 'shutr_${DateTime.now().millisecondsSinceEpoch}',
        );
        await _markDownloaded(assetData['id']);
        saved++;
      }
    }

    if (!mounted) return;
    SnackBarHelper.show(context, message: 'Downloaded $saved ${saved == 1 ? 'photo' : 'photos'}', type: SnackBarType.success);

    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<String>(
      valueListenable: widget.roleNotifier,
      builder: (context, role, _) {
        final isContributor = role == 'contributor';
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.album['name'] ?? 'Shared Album',
                    style: theme.textTheme.titleMedium),
                Text(
                  isContributor
                      ? 'Contributor'
                      : 'Viewer',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isContributor
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              if (!_selectionMode && isContributor)
                IconButton(
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    onPressed: _uploadPhoto),
              if (_selectionMode)
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _selectionMode = false))
            ],
          ),
          body: _loading
              ? Center(
                  child: CircularProgressIndicator(color: theme.colorScheme.primary))
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.05))),
                      ),
                      child: Row(
                        children: [
                          Text('${_assets.length} photos',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                          const Spacer(),
                          if (isContributor)
                            Text('Your contribution: ${widget.uploadCount}/${widget.uploadLimit}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                    Expanded(child: _buildGrid(theme)),
                  ],
                ),
          bottomNavigationBar: _selectionMode ? _buildSelectionBar(theme, isContributor) : null,
        );
      },
    );
  }

  Widget _buildSelectionBar(ThemeData theme, bool isContributor) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          border: Border(
              top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
                  width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _selectAll,
                      child: Text('Select All',
                          style: TextStyle(color: theme.colorScheme.primary)),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _cancelSelection,
                      child: Text('Cancel',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0x12FFFFFF)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _selectedIds.isNotEmpty ? _downloadSelected : null,
                      icon: Icon(Icons.download_outlined,
                          color: _selectedIds.isNotEmpty
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                          size: 18),
                      label: Text('Download',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _selectedIds.isNotEmpty
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.3),
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    if (isContributor) ...[
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _selectedIds.isNotEmpty ? _deleteSelected : null,
                        icon: Icon(Icons.delete_outline,
                            color: theme.colorScheme.error, size: 18),
                        label: Text('Delete ${_selectedIds.length}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildGrid(ThemeData theme) {
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
      itemCount: _assets.length,
      itemBuilder: (context, i) {
        final asset = _assets[i];
        final selected = _selectedIds.contains(asset['id']);
        return GestureDetector(
          onLongPress: () {
            HapticFeedback.mediumImpact();
            setState(() {
              _selectionMode = true;
              _selectedIds.add(asset['id']);
            });
          },
          onTap: () {
            if (_selectionMode) {
              setState(() {
                if (selected) {
                  _selectedIds.remove(asset['id']);
                  if (_selectedIds.isEmpty) _selectionMode = false;
                } else {
                  _selectedIds.add(asset['id']);
                }
              });
              HapticFeedback.selectionClick();
            } else {
              _openViewer(i);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildThumb(asset, theme),
              if (_selectionMode && !selected)
                const DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black54)),
              if (selected)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
              if (_selectionMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      border: Border.all(
                        color:
                            selected ? theme.colorScheme.primary : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Icon(Icons.check,
                            size: 14, color: theme.colorScheme.onPrimary)
                        : null,
                  ),
                ),
              if (!_selectionMode && _downloadedIds.contains(asset['id']))
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(Icons.check,
                        size: 10, color: const Color(0xFF6B8AFF)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openViewer(int index) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => RemotePhotoViewer(
          assets: _assets,
          initialIndex: index,
          baseUrl: widget.baseUrl,
          onDownloaded: (id) {
            _markDownloaded(id);
            if (mounted) setState(() {});
          },
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
}
