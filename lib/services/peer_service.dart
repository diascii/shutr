import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:path_provider/path_provider.dart';

enum UserRole { master, contributor, viewer }

enum ConnectionStatus { pending, accepted, rejected }

class LiveAsset {
  final String id;
  final String path;
  final String uploaderName;
  final String albumId;
  LiveAsset({
    required this.id,
    required this.path,
    required this.uploaderName,
    required this.albumId,
  });
}

class LiveAlbum {
  final AssetPathEntity album;
  final Map<String, LiveAsset> contributions;
  final Directory dir;
  LiveAlbum({required this.album, required this.dir})
      : contributions = {};
}

class ConnectedUser {
  final String id;
  final String name;
  final String source;
  final Map<String, UserRole> albumRoles;
  ConnectionStatus status;
  final Map<String, int> uploadCounts;
  final Map<String, int> uploadLimits;
  final WebSocketChannel socket;

  ConnectedUser({
    required this.id,
    required this.name,
    this.source = 'app',
    required this.albumRoles,
    this.status = ConnectionStatus.pending,
    Map<String, int>? uploadCounts,
    Map<String, int>? uploadLimits,
    required this.socket,
  })  : uploadCounts = uploadCounts ?? {},
        uploadLimits = uploadLimits ?? {};

  UserRole getRole(String albumId) =>
      albumRoles[albumId] ?? UserRole.viewer;
  int getUploadCount(String albumId) => uploadCounts[albumId] ?? 0;
  int getUploadLimit(String albumId) => uploadLimits[albumId] ?? 20;

  void setRole(String albumId, UserRole role) {
    albumRoles[albumId] = role;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'roles': albumRoles.map((k, v) =>
            MapEntry(k, v.toString().split('.').last)),
        'limits': uploadLimits,
        'counts': uploadCounts,
      };
}

enum PeerEventType {
  joinRequest,
  joinAccept,
  joinReject,
  upload,
  delete,
  hostAction,
  roleChange,
  albumSwitch
}

class PeerEvent {
  final String message;
  final DateTime timestamp;
  final PeerEventType type;
  final List<String> assetIds;
  final String? userName;
  final String? targetUser;
  final String? albumId;
  final String? albumName;

  PeerEvent({
    required this.message,
    required this.type,
    this.assetIds = const [],
    this.userName,
    this.targetUser,
    this.albumId,
    this.albumName,
  }) : timestamp = DateTime.now();
}

class PeerService extends ChangeNotifier {
  HttpServer? _server;
  String? _sessionCode;

  final Map<String, LiveAlbum> _liveAlbums = {};
  final List<ConnectedUser> _users = [];
  final List<PeerEvent> _activityLog = [];

  static const int maxLiveAlbums = 3;

  List<ConnectedUser> get users => List.unmodifiable(_users);
  List<ConnectedUser> get pendingUsers =>
      _users.where((u) => u.status == ConnectionStatus.pending).toList();
  List<PeerEvent> get activityLog => List.unmodifiable(_activityLog);
  String? get sessionCode => _sessionCode;
  bool get isLive => _server != null;
  Future<String?> get serverUrl async {
    if (_server == null) return null;
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return 'http://${addr.address}:${_server!.port}';
          }
        }
      }
    } catch (_) {}
    return 'http://localhost:${_server!.port}';
  }
  Map<String, LiveAlbum> get liveAlbums => Map.unmodifiable(_liveAlbums);

  List<String> get liveAlbumIds => _liveAlbums.keys.toList();

  List<LiveAsset> getLiveAssets(String albumId) =>
      _liveAlbums[albumId]?.contributions.values.toList() ?? [];

  LiveAsset? getLiveAsset(String id) {
    for (final album in _liveAlbums.values) {
      if (album.contributions.containsKey(id)) {
        return album.contributions[id];
      }
    }
    return null;
  }

  List<String> allLiveContributionIds() {
    final ids = <String>[];
    for (final album in _liveAlbums.values) {
      ids.addAll(album.contributions.keys);
    }
    return ids;
  }

  void _addLog(String message, PeerEventType type,
      {List<String> assetIds = const [],
      String? userName,
      String? targetUser,
      String? albumId,
      String? albumName}) {
    if (type == PeerEventType.upload && _activityLog.isNotEmpty) {
      final last = _activityLog.last;
      final diff = DateTime.now().difference(last.timestamp).inSeconds;
      if (last.type == PeerEventType.upload &&
          last.userName == userName &&
          last.albumId == albumId &&
          diff < 10) {
        final updatedIds = List<String>.from(last.assetIds)..addAll(assetIds);
        _activityLog.removeLast();
        _activityLog.add(PeerEvent(
          message: '$userName added ${updatedIds.length} photos to $albumName',
          type: PeerEventType.upload,
          assetIds: updatedIds,
          userName: userName,
          albumId: albumId,
          albumName: albumName,
        ));
        notifyListeners();
        return;
      }
    }

    if (type == PeerEventType.delete && _activityLog.isNotEmpty) {
      final last = _activityLog.last;
      final diff = DateTime.now().difference(last.timestamp).inSeconds;
      if (last.type == PeerEventType.delete &&
          last.userName == userName &&
          last.albumId == albumId &&
          diff < 5) {
        final oldCountText = last.message
            .split(' ')
            .firstWhere((s) => int.tryParse(s) != null, orElse: () => '1');
        final oldCount = int.tryParse(oldCountText) ?? 1;
        final newCount = oldCount + 1;
        _activityLog.removeLast();
        _activityLog.add(PeerEvent(
          message: '$userName deleted $newCount photos from $albumName',
          type: PeerEventType.delete,
          assetIds: [...last.assetIds, ...assetIds],
          userName: userName,
          albumId: albumId,
          albumName: albumName,
        ));
        notifyListeners();
        return;
      }
    }

    if (type == PeerEventType.hostAction &&
        message.contains('removed') &&
        _activityLog.isNotEmpty) {
      final last = _activityLog.last;
      final diff = DateTime.now().difference(last.timestamp).inSeconds;
      if (last.type == PeerEventType.hostAction &&
          last.targetUser == targetUser &&
          last.albumId == albumId &&
          diff < 5) {
        final oldCountText = last.message
            .split(' ')
            .firstWhere((s) => int.tryParse(s) != null, orElse: () => '1');
        final oldCount = int.tryParse(oldCountText) ?? 1;
        final newCount = oldCount + 1;
        _activityLog.removeLast();
        _activityLog.add(PeerEvent(
          message: 'Host removed $newCount photos from $targetUser in $albumName',
          type: PeerEventType.hostAction,
          userName: 'Host',
          targetUser: targetUser,
          albumId: albumId,
          albumName: albumName,
        ));
        notifyListeners();
        return;
      }
    }

    _activityLog.add(PeerEvent(
        message: message,
        type: type,
        assetIds: assetIds,
        userName: userName,
        targetUser: targetUser,
        albumId: albumId,
        albumName: albumName));
    notifyListeners();
  }

  void removeLiveAsset(String id) {
    for (final entry in _liveAlbums.entries) {
      final albumId = entry.key;
      final album = entry.value;
      final asset = album.contributions[id];
      if (asset != null) {
        final uploader = asset.uploaderName;
        album.contributions.remove(id);
        final file = File(asset.path);
        if (file.existsSync()) file.deleteSync();
        _addLog('Host removed a photo from $uploader', PeerEventType.hostAction,
            targetUser: uploader, albumId: albumId, albumName: album.album.name);
        _broadcastSync();
        notifyListeners();
        return;
      }
    }
  }

  void _broadcastSync() {
    for (final user in _users) {
      user.socket.sink.add(jsonEncode({'type': 'sync'}));
    }
  }

  Future<bool> goLive(AssetPathEntity album) async {
    if (_liveAlbums.containsKey(album.id)) return false;
    if (_liveAlbums.length >= maxLiveAlbums) return false;

    if (_server == null) {
      _sessionCode = _generateCode();
      await _startServer();
    }

    final tempDir = await getTemporaryDirectory();
    final shutrDir = Directory('${tempDir.path}/shutr_live_${album.id}');
    if (await shutrDir.exists()) await shutrDir.delete(recursive: true);
    await shutrDir.create();

    _liveAlbums[album.id] = LiveAlbum(album: album, dir: shutrDir);

    for (final user in _users) {
      user.albumRoles[album.id] = UserRole.viewer;
      user.uploadLimits[album.id] = 20;
      user.uploadCounts[album.id] = 0;
      user.socket.sink.add(jsonEncode({
        'type': 'album_added',
        'album': _albumToMap(album),
      }));
    }

    _addLog('${album.name} went live', PeerEventType.hostAction,
        albumId: album.id, albumName: album.name);
    notifyListeners();
    return true;
  }

  Future<void> goOffline(String albumId) async {
    final album = _liveAlbums[albumId];
    if (album == null) return;

    album.contributions.forEach((id, asset) {
      final file = File(asset.path);
      if (file.existsSync()) file.deleteSync();
    });
    await album.dir.delete(recursive: true);
    _liveAlbums.remove(albumId);

    for (final user in _users) {
      user.albumRoles.remove(albumId);
      user.uploadCounts.remove(albumId);
      user.uploadLimits.remove(albumId);
      user.socket.sink.add(jsonEncode({
        'type': 'album_removed',
        'albumId': albumId,
      }));
    }

    _addLog('${album.album.name} went offline', PeerEventType.hostAction,
        albumId: albumId, albumName: album.album.name);

    if (_liveAlbums.isEmpty) {
      await _stopServer();
    }

    notifyListeners();
  }

  Future<void> _startServer() async {
    final router = Router();

    router.get('/', (Request request) {
      final host = request.requestedUri.host;
      final port = request.requestedUri.port;
      return Response.ok(_webPage(host, port),
          headers: {'content-type': 'text/html; charset=utf-8'});
    });
    router.get('/session', (Request request) async {
      final albums = <Map<String, dynamic>>[];
      for (final entry in _liveAlbums.entries) {
        final count = await entry.value.album.assetCountAsync;
        String? firstPhotoId;
        final assets = await entry.value.album.getAssetListRange(start: 0, end: 1);
        if (assets.isNotEmpty) {
          firstPhotoId = assets.first.id;
        }
        if (entry.value.contributions.isNotEmpty && firstPhotoId == null) {
          firstPhotoId = entry.value.contributions.keys.first;
        }
        albums.add({
          'id': entry.key,
          'name': entry.value.album.name,
          'count': count + entry.value.contributions.length,
          'firstPhotoId': firstPhotoId,
        });
      }
      return Response.ok(
          jsonEncode({
            'code': _sessionCode,
            'albums': albums,
          }),
          headers: {'content-type': 'application/json'});
    });

    router.get('/assets/<albumId>', (Request request, String albumId) async {
      final liveAlbum = _liveAlbums[albumId];
      if (liveAlbum == null) return Response.notFound('Album not live');

      final assets = await liveAlbum.album.getAssetListRange(start: 0, end: 500);
      final images = assets.where((a) => a.type == AssetType.image).toList();

      final data = images
          .map((a) => {
                'id': a.id,
                'width': a.width,
                'height': a.height,
                'date': a.createDateTime.millisecondsSinceEpoch,
                'isLive': false,
              })
          .toList();

      liveAlbum.contributions.forEach((id, asset) {
        data.add({
          'id': id,
          'width': 1000,
          'height': 1000,
          'date': DateTime.now().millisecondsSinceEpoch,
          'isLive': true,
          'uploader': asset.uploaderName,
        });
      });
      return Response.ok(jsonEncode(data),
          headers: {'content-type': 'application/json'});
    });

    router.get('/thumb/<id>', (Request request, String id) async {
      final asset = _findLiveAsset(id);
      if (asset != null) {
        final file = File(asset.path);
        return Response.ok(file.openRead(),
            headers: {'content-type': 'image/jpeg'});
      }

      final localAsset = await AssetEntity.fromId(id);
      if (localAsset == null) return Response.notFound('Not found');
      final data =
          await localAsset.thumbnailDataWithSize(const ThumbnailSize.square(200));
      return Response.ok(data, headers: {'content-type': 'image/jpeg'});
    });

    router.get('/photo/<id>', (Request request, String id) async {
      final asset = _findLiveAsset(id);
      if (asset != null) {
        final file = File(asset.path);
        return Response.ok(file.openRead(),
            headers: {'content-type': 'image/jpeg'});
      }

      final localAsset = await AssetEntity.fromId(id);
      if (localAsset == null) return Response.notFound('Not found');
      final file = await localAsset.originFile;
      if (file == null) return Response.internalServerError();
      return Response.ok(file.openRead(),
          headers: {'content-type': 'image/jpeg'});
    });

    router.all('/ws', webSocketHandler((WebSocketChannel socket) {
      _handleNewConnection(socket);
    }));

    router.post('/upload/<name>/<albumId>', (Request request, String name, String albumId) async {
      final user = _users
          .cast<ConnectedUser?>()
          .firstWhere((u) => u?.name == name, orElse: () => null);

      if (user == null) return Response.forbidden('Not authenticated');

      final role = user.getRole(albumId);
      if (role != UserRole.contributor) {
        return Response.forbidden('Only contributors can upload');
      }

      final count = user.getUploadCount(albumId);
      final limit = user.getUploadLimit(albumId);
      if (count >= limit) {
        return Response.forbidden('Upload limit reached ($limit)');
      }

      final liveAlbum = _liveAlbums[albumId];
      if (liveAlbum == null) return Response.notFound('Album not live');

      final id = 'live_${DateTime.now().microsecondsSinceEpoch}';
      final file = File('${liveAlbum.dir.path}/$id.jpg');

      final IOSink sink = file.openWrite();
      await sink.addStream(request.read());
      await sink.close();

      user.uploadCounts[albumId] = count + 1;
      liveAlbum.contributions[id] = LiveAsset(
        id: id,
        path: file.path,
        uploaderName: name,
        albumId: albumId,
      );
      _addLog('$name added a photo', PeerEventType.upload,
          assetIds: [id], userName: name, albumId: albumId, albumName: liveAlbum.album.name);

      _broadcastSync();
      notifyListeners();
      return Response.ok(jsonEncode({'success': true, 'id': id}));
    });

    router.delete('/photo/<id>/<name>', (Request request, String id, String name) async {
      final user = _users
          .cast<ConnectedUser?>()
          .firstWhere((u) => u?.name == name, orElse: () => null);

      if (user == null) return Response.forbidden('Not authenticated');

      final liveAsset = _findLiveAsset(id);
      if (liveAsset == null) return Response.notFound('Not found');

      if (liveAsset.uploaderName != name) {
        return Response.forbidden('Can only delete own uploads');
      }

      final role = user.getRole(liveAsset.albumId);
      if (role != UserRole.contributor) {
        return Response.forbidden('Only contributors can delete');
      }

      final liveAlbum = _liveAlbums[liveAsset.albumId];
      if (liveAlbum == null) return Response.notFound('Album not live');

      liveAlbum.contributions.remove(id);
      final file = File(liveAsset.path);
      if (file.existsSync()) file.deleteSync();

      _addLog('$name deleted a photo', PeerEventType.delete,
          assetIds: [id], userName: name, albumId: liveAsset.albumId, albumName: liveAlbum.album.name);

      _broadcastSync();
      notifyListeners();
      return Response.ok(jsonEncode({'success': true}));
    });

    _server = await io.serve(router.call, InternetAddress.anyIPv4, 8080);
    debugPrint('Server live on port 8080');
  }

  Future<void> _stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _sessionCode = null;
    _activityLog.clear();

    for (final user in _users) {
      user.socket.sink.close();
    }
    _users.clear();
  }

  LiveAsset? _findLiveAsset(String id) {
    for (final album in _liveAlbums.values) {
      if (album.contributions.containsKey(id)) {
        return album.contributions[id];
      }
    }
    return null;
  }

  void acceptUser(String userId) {
    final user = _users.firstWhere((u) => u.id == userId);
    user.status = ConnectionStatus.accepted;
    user.socket.sink.add(jsonEncode({
      'type': 'decision',
      'status': 'accepted',
      'roles': user.albumRoles.map((k, v) =>
          MapEntry(k, v.toString().split('.').last)),
      'limits': user.uploadLimits,
    }));
    _addLog('${user.name} joined', PeerEventType.joinAccept, userName: user.name);
    notifyListeners();
  }

  void updateUserRole(String userId, String albumId, UserRole newRole) {
    final user = _users.firstWhere((u) => u.id == userId);
    if (user.getRole(albumId) == newRole) return;
    user.setRole(albumId, newRole);
    user.socket.sink.add(jsonEncode({
      'type': 'role_update',
      'albumId': albumId,
      'role': newRole.toString().split('.').last,
    }));
    final album = _liveAlbums[albumId];
    _addLog(
        'Host changed ${user.name} to ${newRole.toString().split('.').last} in ${album?.album.name ?? albumId}',
        PeerEventType.roleChange,
        userName: user.name,
        albumId: albumId,
        albumName: album?.album.name);
    notifyListeners();
  }

  void updateUserLimit(String userId, String albumId, int newLimit) {
    final user = _users.firstWhere((u) => u.id == userId);
    user.uploadLimits[albumId] = newLimit.clamp(1, 100);
    user.socket.sink.add(jsonEncode({
      'type': 'limit_update',
      'albumId': albumId,
      'limit': user.getUploadLimit(albumId),
    }));
    notifyListeners();
  }

  void rejectUser(String userId) {
    final user = _users.firstWhere((u) => u.id == userId);
    final name = user.name;
    user.status = ConnectionStatus.rejected;
    user.socket.sink.add(jsonEncode({'type': 'kicked'}));
    user.socket.sink.close();
    _users.remove(user);
    _addLog('$name was removed', PeerEventType.joinReject, userName: name);
    notifyListeners();
  }

  void _handleNewConnection(WebSocketChannel socket) {
    socket.stream.listen((message) {
      final data = jsonDecode(message as String);
      if (data['type'] == 'join') {
        final name = data['name'] ?? 'Guest';
        final albumRoles = <String, UserRole>{};
        final uploadLimits = <String, int>{};
        for (final albumId in _liveAlbums.keys) {
          albumRoles[albumId] = UserRole.viewer;
          uploadLimits[albumId] = 20;
        }
        _users.add(ConnectedUser(
          id: data['id'] ?? 'unknown',
          name: name,
          source: data['source'] ?? 'app',
          albumRoles: albumRoles,
          uploadLimits: uploadLimits,
          socket: socket,
        ));
        _addLog('$name is requesting to join', PeerEventType.joinRequest,
            userName: name);
        notifyListeners();
      }
    }, onDone: () {
      final user = _users.where((u) => u.socket == socket).firstOrNull;
      if (user != null) {
        _addLog('${user.name} left', PeerEventType.hostAction, userName: user.name);
      }
      _users.removeWhere((u) => u.socket == socket);
      notifyListeners();
    });
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = DateTime.now().microsecondsSinceEpoch;
    return List.generate(6, (i) => chars[(rnd + i * 7) % chars.length]).join();
  }

  Map<String, dynamic> _albumToMap(AssetPathEntity album) => {
        'id': album.id,
        'name': album.name,
      };

  String _webPage(String host, int port) => '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Shutr</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: #0A0A0A; color: #fff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    min-height: 100vh; overflow-x: hidden;
  }
  .join-screen {
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    min-height: 100vh; padding: 40px;
  }
  .join-screen h1 { font-size: 28px; font-weight: 700; letter-spacing: -0.5px; margin-bottom: 8px; }
  .join-screen p { color: rgba(255,255,255,0.4); font-size: 14px; margin-bottom: 32px; text-align: center; line-height: 1.5; }
  .join-screen input {
    width: 100%; max-width: 300px; padding: 14px 16px; border-radius: 12px; border: none;
    background: #2A2A2A; color: #fff; font-size: 16px; text-align: center; outline: none;
  }
  .join-screen input:focus { outline: 2px solid #6B8AFF; }
  .join-screen button {
    margin-top: 16px; width: 100%; max-width: 300px; padding: 14px; border-radius: 12px; border: none;
    background: #6B8AFF; color: #000; font-size: 16px; font-weight: 600; cursor: pointer;
  }
  .join-screen button:disabled { opacity: 0.4; cursor: default; }
  .waiting {
    display: none; flex-direction: column; align-items: center; justify-content: center;
    min-height: 100vh; padding: 40px;
  }
  .waiting .spinner {
    width: 32px; height: 32px; border: 3px solid rgba(255,255,255,0.1);
    border-top-color: #6B8AFF; border-radius: 50%; animation: spin 0.8s linear infinite;
  }
  .waiting p { margin-top: 20px; color: rgba(255,255,255,0.5); font-size: 15px; }
  .header {
    position: sticky; top: 0; z-index: 10; background: #0A0A0A;
    padding: 16px; border-bottom: 1px solid rgba(255,255,255,0.05);
  }
  .header h1 { font-size: 22px; font-weight: 700; letter-spacing: -0.3px; }
  .code-badge {
    display: inline-flex; align-items: center; gap: 6px; margin-top: 8px;
    padding: 4px 10px; background: rgba(76,175,80,0.1); border: 1px solid rgba(76,175,80,0.3);
    border-radius: 8px; font-size: 14px; letter-spacing: 2px; color: #4CAF50; cursor: pointer;
  }
  .code-badge.copied::after { content: ' Copied!'; letter-spacing: 0; }
  .section-title {
    padding: 16px 16px 8px; font-size: 11px; font-weight: 700; letter-spacing: 1px;
    color: rgba(255,255,255,0.4); text-transform: uppercase;
  }
  .album-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 2px; padding: 0 2px; }
  .album-card { cursor: pointer; }
  .album-card img { width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: 8px; display: block; }
  .album-info { padding: 6px 6px 12px; }
  .album-info .name { font-size: 13px; font-weight: 400; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .album-info .count { font-size: 12px; color: #8A8A8A; font-weight: 300; margin-top: 2px; }
  .photo-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2px; padding: 0 2px 80px; }
  .photo-grid img { width: 100%; aspect-ratio: 1; object-fit: cover; cursor: pointer; }
  .back-bar {
    display: flex; align-items: center; gap: 8px; padding: 8px 16px;
    background: #0A0A0A; position: sticky; top: 0; z-index: 10;
  }
  .back-bar button {
    background: none; border: none; color: #fff; font-size: 16px; cursor: pointer; padding: 8px 4px;
  }
  .back-bar span { font-size: 16px; font-weight: 600; }
  .viewer {
    display: none; position: fixed; inset: 0; z-index: 100;
    background: #000; flex-direction: column;
  }
  .viewer.open { display: flex; }
  .viewer-top {
    display: flex; align-items: center; justify-content: space-between;
    padding: 8px 16px; padding-top: env(safe-area-inset-top, 8px);
    background: linear-gradient(to bottom, rgba(0,0,0,0.8), transparent);
  }
  .viewer-top button {
    background: none; border: none; color: #fff; font-size: 24px; cursor: pointer; padding: 8px;
  }
  .viewer-body {
    flex: 1; display: flex; align-items: center; justify-content: center;
    overflow: hidden; position: relative;
  }
  .viewer-body img { max-width: 100%; max-height: 100%; object-fit: contain; }
  .viewer-body .loading {
    position: absolute; width: 24px; height: 24px; border: 2px solid rgba(255,255,255,0.2);
    border-top-color: #6B8AFF; border-radius: 50%; animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  .viewer-nav {
    position: absolute; top: 50%; transform: translateY(-50%); color: #fff;
    font-size: 32px; cursor: pointer; padding: 20px 12px; opacity: 0.6;
    background: none; border: none; z-index: 10;
  }
  .viewer-nav:hover { opacity: 1; }
  .viewer-nav.prev { left: 0; }
  .viewer-nav.next { right: 0; }
  .viewer-bottom {
    display: flex; align-items: center; justify-content: center; gap: 16px;
    padding: 16px; padding-bottom: calc(16px + env(safe-area-inset-bottom, 0));
    background: linear-gradient(to top, rgba(0,0,0,0.8), transparent);
  }
  .viewer-bottom a {
    display: inline-flex; align-items: center; gap: 8px;
    padding: 10px 24px; border-radius: 12px; text-decoration: none;
    background: #6B8AFF; color: #000; font-weight: 600; font-size: 14px;
  }
  .empty { text-align: center; padding: 60px 40px; color: rgba(255,255,255,0.3); }
  .empty p { margin-top: 8px; font-size: 14px; line-height: 1.5; }
</style>
</head>
<body>

<div class="join-screen" id="joinScreen">
  <h1>Shutr</h1>
  <p>Enter your name to view shared albums</p>
  <input id="nameInput" placeholder="Your name" maxlength="20" autofocus>
  <button id="joinBtn">Join</button>
</div>

<div class="waiting" id="waitingScreen">
  <div class="spinner"></div>
  <p>Waiting for host to accept...</p>
</div>

<div id="app" style="display:none">
  <div class="header">
    <h1>Shutr</h1>
    <div class="code-badge" id="codeBadge" onclick="copyCode()"></div>
  </div>
  <div id="albumView">
    <div class="section-title">Live</div>
    <div class="album-grid" id="albumGrid"></div>
  </div>
  <div id="photoView" style="display:none">
    <div class="back-bar">
      <button onclick="showAlbums()">&lsaquo; Back</button>
      <span id="albumName"></span>
    </div>
    <div class="photo-grid" id="photoGrid"></div>
  </div>
  <div class="empty" id="emptyState">
    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="rgba(255,255,255,0.15)" stroke-width="1.5"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg>
    <p>No live albums yet.</p>
  </div>
</div>

<div class="viewer" id="viewer">
  <div class="viewer-top">
    <button onclick="closeViewer()">&#10005;</button>
    <span id="viewerCounter" style="font-size:14px;color:rgba(255,255,255,0.6)"></span>
    <button onclick="closeViewer()" style="visibility:hidden">&#10005;</button>
  </div>
  <button class="viewer-nav prev" onclick="navViewer(-1)">&lsaquo;</button>
  <button class="viewer-nav next" onclick="navViewer(1)">&rsaquo;</button>
  <div class="viewer-body" id="viewerBody"><div class="loading"></div></div>
  <div class="viewer-bottom">
    <a id="downloadBtn" href="#" download="photo.jpg">Download</a>
  </div>
</div>

<script>
const host = '$host';
const port = $port;
let ws = null;
let nickname = '';
let albums = [];
let currentAlbum = null;
let currentPhotos = [];
let viewerIndex = 0;

function uuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
    const r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

function sendJoin() {
  const input = document.getElementById('nameInput');
  nickname = input.value.trim();
  if (!nickname) { input.focus(); return; }
  console.log('Sending join request...');
  document.getElementById('joinBtn').disabled = true;
  document.getElementById('joinBtn').textContent = 'Connecting...';
  connectWS(true);
}

function connectWS(join) {
  if (ws) try { ws.close(); } catch(e) {}
  const url = 'ws://' + host + ':' + port + '/ws';
  console.log('Connecting WS:', url);
  ws = new WebSocket(url);
  ws.onopen = () => {
    console.log('WS connected');
    if (join) {
      const msg = {type: 'join', name: nickname, source: 'web', id: uuid()};
      console.log('Sending:', JSON.stringify(msg));
      ws.send(JSON.stringify(msg));
      document.getElementById('joinScreen').style.display = 'none';
      document.getElementById('waitingScreen').style.display = 'flex';
    }
  };
  ws.onmessage = (e) => {
    console.log('WS message:', e.data);
    const data = JSON.parse(e.data);
    if (data.type === 'decision') {
      if (data.status === 'accepted') {
        console.log('Join accepted');
        document.getElementById('waitingScreen').style.display = 'none';
        document.getElementById('app').style.display = 'block';
        fetchAlbums();
      } else {
        alert('Join request denied by host.');
        location.reload();
      }
    }
    if (data.type === 'kicked') {
      alert('You have been removed by the host.');
      location.reload();
    }
    if (['sync', 'album_added', 'album_removed'].includes(data.type)) {
      if (document.getElementById('app').style.display !== 'none') {
        fetchAlbums();
        if (currentAlbum) fetchPhotos();
      }
    }
  };
  ws.onclose = (e) => {
    console.log('WS closed:', e.code, e.reason);
    if (!join) setTimeout(() => connectWS(false), 3000);
  };
  ws.onerror = (e) => {
    console.log('WS error:', e);
    if (join) { alert('Could not connect to host. Make sure the host is on the same WiFi and the app is running.'); location.reload(); }
  };
}

function copyCode() {
  const badge = document.getElementById('codeBadge');
  navigator.clipboard.writeText(badge.textContent).then(() => {
    badge.classList.add('copied');
    setTimeout(() => badge.classList.remove('copied'), 2000);
  });
}

function fetchAlbums() {
  fetch('/session').then(r => r.json()).then(data => {
    document.getElementById('codeBadge').textContent = data.code || '';
    albums = data.albums || [];
    renderAlbums();
  });
}

function renderAlbums() {
  const grid = document.getElementById('albumGrid');
  const empty = document.getElementById('emptyState');
  if (albums.length === 0) {
    grid.innerHTML = '';
    empty.style.display = 'block';
    return;
  }
  empty.style.display = 'none';
  grid.innerHTML = albums.map((a, i) => '<div class="album-card" onclick="openAlbum(' + i + ')">' +
    (a.firstPhotoId ? '<img src="/thumb/' + a.firstPhotoId + '" loading="lazy" onerror="this.style.display=\\'none\\'">' : '<div style="width:100%;aspect-ratio:1;border-radius:8px;background:#1C1C1C"></div>') +
    '<div class="album-info"><div class="name">' + esc(a.name || 'Unnamed') + '</div>' +
    '<div class="count">' + a.count + ' photos</div></div></div>'
  ).join('');
}

function openAlbum(idx) {
  currentAlbum = albums[idx];
  document.getElementById('albumView').style.display = 'none';
  document.getElementById('photoView').style.display = 'block';
  document.getElementById('albumName').textContent = currentAlbum.name || 'Unnamed';
  fetchPhotos();
}

function showAlbums() {
  document.getElementById('photoView').style.display = 'none';
  document.getElementById('albumView').style.display = 'block';
  currentAlbum = null;
  currentPhotos = [];
}

function fetchPhotos() {
  fetch('/assets/' + currentAlbum.id).then(r => r.json()).then(photos => {
    currentPhotos = photos;
    renderPhotos();
  });
}

function renderPhotos() {
  const grid = document.getElementById('photoGrid');
  grid.innerHTML = currentPhotos.map((p, i) =>
    '<img src="/thumb/' + p.id + '" loading="lazy" onclick="openViewer(' + i + ')" onerror="this.style.display=\\'none\\'">'
  ).join('');
}

function openViewer(i) {
  viewerIndex = i;
  document.getElementById('viewer').classList.add('open');
  document.body.style.overflow = 'hidden';
  loadViewerImage();
}

function closeViewer() {
  document.getElementById('viewer').classList.remove('open');
  document.body.style.overflow = '';
}

function navViewer(delta) {
  viewerIndex = (viewerIndex + delta + currentPhotos.length) % currentPhotos.length;
  loadViewerImage();
}

function loadViewerImage() {
  const body = document.getElementById('viewerBody');
  const photo = currentPhotos[viewerIndex];
  if (!photo) return;
  body.innerHTML = '<div class="loading"></div>';
  document.getElementById('viewerCounter').textContent = (viewerIndex + 1) + ' / ' + currentPhotos.length;
  document.getElementById('downloadBtn').href = '/photo/' + photo.id;
  document.getElementById('downloadBtn').download = 'shutr_' + photo.id + '.jpg';
  const img = new Image();
  img.onload = () => { body.innerHTML = ''; body.appendChild(img); };
  img.src = '/photo/' + photo.id;
}

function esc(s) {
  const d = document.createElement('div'); d.textContent = s; return d.innerHTML;
}

document.getElementById('joinBtn').addEventListener('click', sendJoin);
document.getElementById('nameInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') sendJoin(); });
window.addEventListener('beforeunload', (e) => { e.preventDefault(); e.returnValue = ''; });
document.addEventListener('keydown', (e) => {
  if (!document.getElementById('viewer').classList.contains('open')) return;
  if (e.key === 'Escape') closeViewer();
  if (e.key === 'ArrowLeft') navViewer(-1);
  if (e.key === 'ArrowRight') navViewer(1);
});
</script>
</body>
</html>
''';
}
