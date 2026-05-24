import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/guest_album_view.dart';

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
  bool _loading = true;
  WebSocketChannel? _socket;
  bool _waitingForApproval = true;
  bool _isExited = false;
  bool _disconnected = false;

  List<Map<String, dynamic>> _albums = [];
  Map<String, String> _roles = {};
  Map<String, int> _limits = {};
  Map<String, int> _counts = {};
  final Map<String, ValueNotifier<String>> _roleNotifiers = {};

  String get _baseUrl => 'http://${widget.hostIp}:${widget.port}';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _exitWithError(String message) {
    if (_isExited || !mounted) return;
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
              _roles = Map<String, String>.from(data['roles'] ?? {});
              _limits = (data['limits'] as Map<dynamic, dynamic>?)
                      ?.map((k, v) => MapEntry(k.toString(), v as int)) ??
                  {};
              _counts = {};
              for (final albumId in _roles.keys) {
                _counts[albumId] = 0;
                _roleNotifiers[albumId] = ValueNotifier(_roles[albumId] ?? 'viewer');
              }
            });
            _fetchAlbums();
          } else {
            _exitWithError('Join request denied');
          }
        }

        if (data['type'] == 'role_update') {
          setState(() => _roles[data['albumId']] = data['role']);
          _roleNotifiers[data['albumId']]?.value = data['role'];
          if (mounted) {
            SnackBarHelper.show(context, message: 'You are now a ${data['role'].toUpperCase()} in ${_getAlbumName(data['albumId'])}', type: SnackBarType.info);
          }
        }

        if (data['type'] == 'limit_update') {
          setState(() => _limits[data['albumId']] = data['limit']);
        }

        if (data['type'] == 'sync') {
          _fetchAlbums();
        }

        if (data['type'] == 'album_added' || data['type'] == 'album_removed') {
          _fetchAlbums();
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
    } catch (e) {
      _exitWithError('Error: $e');
    }
  }

  String _getAlbumName(String? albumId) {
    if (albumId == null) return 'an album';
    final album = _albums.firstWhere(
      (a) => a['id'] == albumId,
      orElse: () => {'name': 'Unknown'},
    );
    return album['name'] ?? 'Unknown';
  }

  Future<void> _fetchAlbums() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/session'))
          .timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _albums = List<Map<String, dynamic>>.from(data['albums'] ?? []);
          _loading = false;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _socket?.sink.close();
    super.dispose();
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
                  child: Text('Leave',
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

    return Scaffold(
      appBar: AppBar(
        title: Text('Live Albums',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            )),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: theme.colorScheme.primary))
          : _buildAlbumGrid(theme),
    );
  }

  Widget _buildAlbumGrid(ThemeData theme) {
    if (_albums.isEmpty) {
      return Center(
        child: Text('No live albums',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 2, crossAxisSpacing: 2, childAspectRatio: 0.85),
      itemCount: _albums.length,
      itemBuilder: (context, i) {
        final album = _albums[i];
        final albumId = album['id'] as String;
        final role = _roles[albumId] ?? 'viewer';
        final isContributor = role == 'contributor';
        final count = album['count'] ?? 0;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GuestAlbumView(
                  album: album,
                  baseUrl: _baseUrl,
                  roleNotifier: _roleNotifiers[albumId] ?? ValueNotifier('viewer'),
                  uploadLimit: _limits[albumId] ?? 20,
                  uploadCount: _counts[albumId] ?? 0,
                  socket: _socket,
                  onCountChange: (c) => setState(() => _counts[albumId] = c),
                  nickname: widget.nickname,
                ),
              ),
            );
          },
          child: Container(
            color: const Color(0xFF0A0A0A),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AlbumThumbnail(
                      albumId: albumId,
                      baseUrl: _baseUrl,
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
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4CAF50),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              album['name'] ?? 'Unnamed',
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
                        '$count photos · ${isContributor ? 'Contributor' : 'Viewer'}',
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
      },
    );
  }
}


