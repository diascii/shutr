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
  final String path;
  final String uploaderName;
  LiveAsset({required this.path, required this.uploaderName});
}

class ConnectedUser {
  final String id;
  final String name;
  UserRole role;
  ConnectionStatus status;
  int uploadLimit;
  int uploadCount;
  final WebSocketChannel socket;

  ConnectedUser({
    required this.id,
    required this.name,
    required this.role,
    this.status = ConnectionStatus.pending,
    this.uploadLimit = 20,
    this.uploadCount = 0,
    required this.socket,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'role': role.toString().split('.').last,
        'limit': uploadLimit,
        'count': uploadCount,
      };
}

enum PeerEventType {
  joinRequest,
  joinAccept,
  joinReject,
  upload,
  hostAction,
  roleChange
}

class PeerEvent {
  final String message;
  final DateTime timestamp;
  final PeerEventType type;
  final List<String> assetIds;
  final String? userName;
  final String? targetUser;

  PeerEvent({
    required this.message,
    required this.type,
    this.assetIds = const [],
    this.userName,
    this.targetUser,
  }) : timestamp = DateTime.now();
}

class PeerService extends ChangeNotifier {
  HttpServer? _server;
  AssetPathEntity? _activeAlbum;
  String? _sessionCode;

  final Map<String, LiveAsset> _liveContributions = {};
  final List<ConnectedUser> _users = [];
  final List<PeerEvent> _activityLog = [];

  List<ConnectedUser> get users => List.unmodifiable(_users);
  List<String> get liveContributionIds => _liveContributions.keys.toList();
  List<PeerEvent> get activityLog => List.unmodifiable(_activityLog);
  LiveAsset? getLiveAsset(String id) => _liveContributions[id];

  void _addLog(String message, PeerEventType type,
      {List<String> assetIds = const [],
      String? userName,
      String? targetUser}) {
    // Smart grouping for uploads: If same user uploads within 10 seconds, group them
    if (type == PeerEventType.upload && _activityLog.isNotEmpty) {
      final last = _activityLog.last;
      final diff = DateTime.now().difference(last.timestamp).inSeconds;
      if (last.type == PeerEventType.upload &&
          last.userName == userName &&
          diff < 10) {
        final updatedIds = List<String>.from(last.assetIds)..addAll(assetIds);
        _activityLog.removeLast();
        _activityLog.add(PeerEvent(
          message: '$userName added ${updatedIds.length} photos',
          type: PeerEventType.upload,
          assetIds: updatedIds,
          userName: userName,
        ));
        notifyListeners();
        return;
      }
    }

    // Smart grouping for host removals
    if (type == PeerEventType.hostAction &&
        message.contains('removed') &&
        _activityLog.isNotEmpty) {
      final last = _activityLog.last;
      final diff = DateTime.now().difference(last.timestamp).inSeconds;
      if (last.type == PeerEventType.hostAction &&
          last.targetUser == targetUser &&
          diff < 5) {
        final oldCountText = last.message
            .split(' ')
            .firstWhere((s) => int.tryParse(s) != null, orElse: () => '1');
        final oldCount = int.tryParse(oldCountText) ?? 1;
        final newCount = oldCount + 1;
        _activityLog.removeLast();
        _activityLog.add(PeerEvent(
          message: 'Host removed $newCount photos from $targetUser',
          type: PeerEventType.hostAction,
          userName: 'Host',
          targetUser: targetUser,
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
        targetUser: targetUser));
    notifyListeners();
  }

  void removeLiveAsset(String id) {
    final asset = _liveContributions[id];
    if (asset != null) {
      final uploader = asset.uploaderName;
      _liveContributions.remove(id);
      final file = File(asset.path);
      if (file.existsSync()) file.deleteSync();
      _addLog('Host removed a photo from $uploader', PeerEventType.hostAction,
          targetUser: uploader);
    }
    for (final user in _users) {
      user.socket.sink.add(jsonEncode({'type': 'sync'}));
    }
    notifyListeners();
  }

  bool get isLive => _server != null;
  String? get sessionCode => _sessionCode;
  AssetPathEntity? get activeAlbum => _activeAlbum;

  void acceptUser(String userId) {
    final user = _users.firstWhere((u) => u.id == userId);
    user.status = ConnectionStatus.accepted;
    user.socket.sink.add(jsonEncode({
      'type': 'decision',
      'status': 'accepted',
      'role': user.role.toString().split('.').last,
      'limit': user.uploadLimit,
    }));
    _addLog('${user.name} joined the gallery', PeerEventType.joinAccept,
        userName: user.name);
    notifyListeners();
  }

  void updateUserRole(String userId, UserRole newRole) {
    final user = _users.firstWhere((u) => u.id == userId);
    if (user.role == newRole) return;
    user.role = newRole;
    user.socket.sink.add(jsonEncode({
      'type': 'role_update',
      'role': newRole.toString().split('.').last,
    }));
    _addLog(
        'Host changed ${user.name} to ${newRole.toString().split('.').last}',
        PeerEventType.roleChange,
        userName: user.name);
    notifyListeners();
  }

  void updateUserLimit(String userId, int newLimit) {
    final user = _users.firstWhere((u) => u.id == userId);
    user.uploadLimit = newLimit.clamp(1, 100);
    user.socket.sink.add(jsonEncode({
      'type': 'limit_update',
      'limit': user.uploadLimit,
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

  Future<void> goLive(AssetPathEntity album, String code) async {
    if (isLive) await stopLive();

    _activeAlbum = album;
    _sessionCode = code;
    _liveContributions.clear();
    _activityLog.clear();

    // Prepare temp directory for live assets
    final tempDir = await getTemporaryDirectory();
    final shutrDir = Directory('${tempDir.path}/shutr_live');
    if (await shutrDir.exists()) await shutrDir.delete(recursive: true);
    await shutrDir.create();

    final router = Router();

    router.get('/info', (Request request) async {
      final count = await album.assetCountAsync;
      return Response.ok(
          jsonEncode({
            'name': album.name,
            'code': code,
            'count': count + _liveContributions.length,
          }),
          headers: {'content-type': 'application/json'});
    });

    router.get('/assets', (Request request) async {
      final assets = await album.getAssetListRange(start: 0, end: 500);
      // Filter out videos - only serve images to guests
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

      _liveContributions.forEach((id, asset) {
        data.add({
          'id': id,
          'width': 1000,
          'height': 1000,
          'date': DateTime.now().millisecondsSinceEpoch,
          'isLive': true,
        });
      });
      return Response.ok(jsonEncode(data),
          headers: {'content-type': 'application/json'});
    });

    router.get('/thumb/<id>', (Request request, String id) async {
      if (_liveContributions.containsKey(id)) {
        final file = File(_liveContributions[id]!.path);
        return Response.ok(file.openRead(),
            headers: {'content-type': 'image/jpeg'});
      }

      final asset = await AssetEntity.fromId(id);
      if (asset == null) return Response.notFound('Not found');
      final data =
          await asset.thumbnailDataWithSize(const ThumbnailSize.square(200));
      return Response.ok(data, headers: {'content-type': 'image/jpeg'});
    });

    router.get('/photo/<id>', (Request request, String id) async {
      if (_liveContributions.containsKey(id)) {
        final file = File(_liveContributions[id]!.path);
        return Response.ok(file.openRead(),
            headers: {'content-type': 'image/jpeg'});
      }

      final asset = await AssetEntity.fromId(id);
      if (asset == null) return Response.notFound('Not found');
      final file = await asset.originFile;
      if (file == null) return Response.internalServerError();
      return Response.ok(file.openRead(),
          headers: {'content-type': 'image/jpeg'});
    });

    router.all('/ws', webSocketHandler((WebSocketChannel socket) {
      _handleNewConnection(socket);
    }));

    router.post('/upload/<name>', (Request request, String name) async {
      final user = _users
          .cast<ConnectedUser?>()
          .firstWhere((u) => u?.name == name, orElse: () => null);

      if (user == null || user.role != UserRole.contributor) {
        return Response.forbidden('Only contributors can upload');
      }

      if (user.uploadCount >= user.uploadLimit) {
        return Response.forbidden('Upload limit reached (${user.uploadLimit})');
      }

      final id = 'live_${DateTime.now().microsecondsSinceEpoch}';
      final file = File('${shutrDir.path}/$id.jpg');

      final IOSink sink = file.openWrite();
      await sink.addStream(request.read());
      await sink.close();

      user.uploadCount++;
      _liveContributions[id] = LiveAsset(path: file.path, uploaderName: name);
      _addLog('$name added a photo', PeerEventType.upload,
          assetIds: [id], userName: name);

      for (final u in _users) {
        u.socket.sink.add(jsonEncode({'type': 'sync'}));
      }
      notifyListeners();
      return Response.ok(jsonEncode({'success': true, 'id': id}));
    });

    _server = await io.serve(router.call, InternetAddress.anyIPv4, 8080);
    _addLog('Gallery session started', PeerEventType.hostAction);
    notifyListeners();
    debugPrint('Server live on port 8080');
  }

  Future<void> stopLive() async {
    await _server?.close(force: true);
    _server = null;
    _activeAlbum = null;
    _sessionCode = null;
    _activityLog.clear();

    // Clean up temp files
    _liveContributions.forEach((id, asset) {
      final file = File(asset.path);
      if (file.existsSync()) file.deleteSync();
    });
    _liveContributions.clear();

    for (final user in _users) {
      user.socket.sink.close();
    }
    _users.clear();
    notifyListeners();
  }

  void _handleNewConnection(WebSocketChannel socket) {
    socket.stream.listen((message) {
      final data = jsonDecode(message as String);
      if (data['type'] == 'join') {
        final name = data['name'] ?? 'Guest';
        _users.add(ConnectedUser(
          id: data['id'] ?? 'unknown',
          name: name,
          role: UserRole.viewer,
          socket: socket,
        ));
        _addLog('$name is requesting to join', PeerEventType.joinRequest,
            userName: name);
        notifyListeners();
      }
    }, onDone: () {
      _users.removeWhere((u) => u.socket == socket);
      notifyListeners();
    });
  }
}
