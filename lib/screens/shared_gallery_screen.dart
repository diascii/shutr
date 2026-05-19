import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:image_picker/image_picker.dart';

class SharedGalleryScreen extends StatefulWidget {
  final String hostIp;
  final int port;
  final String code;
  final String nickname;

  const SharedGalleryScreen({
    super.key,
    required this.hostIp,
    required this.port,
    required this.code,
    required this.nickname,
  });

  @override
  State<SharedGalleryScreen> createState() => _SharedGalleryScreenState();
}

class _SharedGalleryScreenState extends State<SharedGalleryScreen> {
  List<dynamic> _assets = [];
  bool _loading = true;
  WebSocketChannel? _socket;
  String? _albumName;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _waitingForApproval = true;
  bool _isExited = false;

  String _currentRole = 'viewer';
  int _uploadLimit = 20;
  int _uploadCount = 0;

  bool _disconnected = false;

  String get _baseUrl => 'http://${widget.hostIp}:${widget.port}';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _exitWithError(String message) {
    if (_isExited || !mounted) {
      return;
    }
    _isExited = true;
    Navigator.of(context).popUntil((route) => route.isFirst);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _connect() async {
    try {
      setState(() {
        _loading = true;
        _disconnected = false;
      });

      final infoRes = await http
          .get(Uri.parse('$_baseUrl/info'))
          .timeout(const Duration(seconds: 5));
      if (!mounted) {
        return;
      }

      if (infoRes.statusCode != 200) {
        throw 'Failed to get album info';
      }
      final info = jsonDecode(infoRes.body);

      final assetsRes = await http
          .get(Uri.parse('$_baseUrl/assets'))
          .timeout(const Duration(seconds: 5));
      if (!mounted) {
        return;
      }

      if (assetsRes.statusCode != 200) {
        throw 'Failed to fetch photos';
      }

      _socket = WebSocketChannel.connect(
          Uri.parse('ws://${widget.hostIp}:${widget.port}/ws'));
      _socket!.sink.add(jsonEncode({
        'type': 'join',
        'name': widget.nickname,
        'id': const Uuid().v4(),
      }));

      _socket!.stream.listen((msg) {
        final data = jsonDecode(msg as String);
        debugPrint('Guest Received: $data');

        if (data['type'] == 'kicked') {
          _exitWithError('You have been removed by the host');
        }

        if (data['type'] == 'decision') {
          if (data['status'] == 'accepted') {
            setState(() {
              _waitingForApproval = false;
              _currentRole = data['role'] ?? 'viewer';
              _uploadLimit = data['limit'] ?? 20;
            });
          } else {
            _exitWithError('Join request denied');
          }
        }

        if (data['type'] == 'role_update') {
          setState(() => _currentRole = data['role']);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('You are now a ${_currentRole.toUpperCase()}'),
              backgroundColor: _currentRole == 'contributor'
                  ? const Color(0xFF6B8AFF)
                  : Colors.blueGrey,
            ));
          }
        }

        if (data['type'] == 'limit_update') {
          setState(() => _uploadLimit = data['limit']);
        }

        if (data['type'] == 'sync') {
          _refresh();
        }
      }, onDone: () {
        if (!_isExited) {
          setState(() => _disconnected = true);
        }
      }, onError: (e) {
        if (!_isExited) {
          setState(() => _disconnected = true);
        }
      });

      setState(() {
        _albumName = info['name'];
        _assets = jsonDecode(assetsRes.body);
        _loading = false;
      });
    } catch (e) {
      if (_waitingForApproval) {
        _exitWithError('Error: $e');
      } else {
        setState(() {
          _loading = false;
          _disconnected = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _socket?.sink.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    final res = await http.get(Uri.parse('$_baseUrl/assets'));
    if (!mounted) {
      return;
    }
    if (res.statusCode == 200) {
      setState(() => _assets = jsonDecode(res.body));
    }
  }

  Future<void> _downloadSelected() async {
    final toDownload =
        _assets.where((a) => _selectedIds.contains(a['id'])).toList();

    final album = await _promptAlbumSelection();
    if (album == null) {
      return;
    }

    for (var assetData in toDownload) {
      final response =
          await http.get(Uri.parse('$_baseUrl/photo/${assetData['id']}'));
      if (!mounted) {
        return;
      }
      if (response.statusCode == 200) {
        await PhotoManager.editor.saveImage(
          response.bodyBytes,
          filename: 'shutr_${DateTime.now().millisecondsSinceEpoch}.jpg',
          title: 'shutr_${DateTime.now().millisecondsSinceEpoch}',
        );
        if (!mounted) {
          return;
        }
      }
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded ${toDownload.length} photos')));

    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<AssetPathEntity?> _promptAlbumSelection() async {
    final albums = await PhotoManager.getAssetPathList(type: RequestType.common);
    if (!mounted) {
      return null;
    }
    final theme = Theme.of(context);
    return showDialog<AssetPathEntity>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Save to...', style: theme.textTheme.titleLarge),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: albums.length,
              itemBuilder: (ctx, i) => ListTile(
                title: Text(albums[i].name, style: theme.textTheme.bodyLarge),
                onTap: () => Navigator.pop(ctx, albums[i]),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _uploadPhoto() async {
    if (_currentRole != 'contributor') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only contributors can upload.')));
      return;
    }

    final picker = ImagePicker();
    final List<XFile> files = await picker.pickMultiImage();
    if (files.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    if (_uploadCount + files.length > _uploadLimit) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Upload limit reached. You can only add ${_uploadLimit - _uploadCount} more.')));
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Uploading...')));

    for (var file in files) {
      final bytes = await file.readAsBytes();
      if (!mounted) {
        return;
      }
      final encodedName = Uri.encodeComponent(widget.nickname);
      final response = await http
          .post(Uri.parse('$_baseUrl/upload/$encodedName'), body: bytes);

      if (!mounted) {
        return;
      }
      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed: ${response.body}')));
        return;
      }
      _uploadCount++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('All photos uploaded!')));
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_disconnected) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                    size: 64),
                const SizedBox(height: 24),
                Text(
                  'Connection Lost',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Trying to reach the host... Make sure you are on the same WiFi.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _connect,
                  child: const Text('Retry Connection'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Leave Album',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.4))),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_waitingForApproval) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text('Waiting for host to accept...',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    final isContributor = _currentRole == 'contributor';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_albumName ?? 'Shared Album',
                style: theme.textTheme.titleMedium),
            Text(
              isContributor
                  ? 'Contributor ($_uploadCount/$_uploadLimit)'
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
          : _buildGrid(theme),
      bottomNavigationBar: _selectionMode ? _buildSelectionBar(theme) : null,
    );
  }

  Widget _buildSelectionBar(ThemeData theme) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          border: Border(
              top: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.1),
                  width: 0.5)),
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                  child: Text('${_selectedIds.length} selected',
                      style: theme.textTheme.bodyMedium)),
              ElevatedButton(
                onPressed: _downloadSelected,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(120, 44),
                ),
                child: const Text('Download'),
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
              Image.network(
                '$_baseUrl/thumb/${asset['id']}',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: theme.colorScheme.surfaceContainer),
              ),
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
        pageBuilder: (_, __, ___) => _RemotePhotoViewer(
          assets: _assets,
          initialIndex: index,
          baseUrl: _baseUrl,
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

class _RemotePhotoViewer extends StatefulWidget {
  final List<dynamic> assets;
  final int initialIndex;
  final String baseUrl;

  const _RemotePhotoViewer(
      {required this.assets,
      required this.initialIndex,
      required this.baseUrl});

  @override
  State<_RemotePhotoViewer> createState() => _RemotePhotoViewerState();
}

class _RemotePhotoViewerState extends State<_RemotePhotoViewer> {
  late PageController _pageCtrl;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

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
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Saved to gallery')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              final asset = widget.assets[_currentIndex];
              showModalBottomSheet(
                context: context,
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24))),
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
          )
        ],
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemCount: widget.assets.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Image.network(
            '${widget.baseUrl}/photo/${widget.assets[i]['id']}',
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Center(
                  child: CircularProgressIndicator(
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded /
                        progress.expectedTotalBytes!
                    : null,
                color: theme.colorScheme.primary,
              ));
            },
          ),
        ),
      ),
    );
  }
}
