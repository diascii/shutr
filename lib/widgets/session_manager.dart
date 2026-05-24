import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/peer_service.dart';

class SessionManagerSheet extends StatefulWidget {
  const SessionManagerSheet({super.key});

  @override
  State<SessionManagerSheet> createState() => _SessionManagerSheetState();
}

class _SessionManagerSheetState extends State<SessionManagerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String? _selectedGuest;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PeerService>(
      builder: (context, peerService, _) {
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 8),
              TabBar(
                controller: _tabCtrl,
                dividerColor: Colors.transparent,
                indicatorColor: const Color(0xFF6B8AFF),
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white24,
                labelStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
                tabs: [
                  Tab(text: 'Members (${peerService.users.length})'),
                  const Tab(text: 'Activity Log'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildMembersTab(peerService),
                    _buildActivityTab(peerService),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMembersTab(PeerService peerService) {
    if (peerService.users.isEmpty) {
      return const Center(
          child: Text('No members yet', style: TextStyle(color: Colors.white24)));
    }
    final liveAlbumIds = peerService.liveAlbumIds;
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: peerService.users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final user = peerService.users[i];
        final isPending = user.status == ConnectionStatus.pending;
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: isPending
                    ? Colors.orange.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isPending
                        ? Colors.orange.withValues(alpha: 0.1)
                        : const Color(0xFF2A2A2A),
                    child: Text(user.name[0].toUpperCase(),
                        style: TextStyle(
                            color: isPending ? Colors.orange : Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(user.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
                  ),
                  if (isPending) ...[
                    IconButton(
                        icon: const Icon(Icons.check_circle_outline,
                            color: Color(0xFF6B8AFF)),
                        onPressed: () => peerService.acceptUser(user.id)),
                    IconButton(
                        icon: const Icon(Icons.remove_circle_outline,
                            color: Color(0xFFF87171)),
                        onPressed: () => peerService.rejectUser(user.id)),
                  ] else
                    IconButton(
                        icon: const Icon(Icons.logout,
                            color: Color(0xFFF87171), size: 20),
                        onPressed: () => peerService.rejectUser(user.id)),
                ],
              ),
              if (!isPending) ...[
                const SizedBox(height: 12),
                const Divider(color: Color(0x12FFFFFF), height: 1),
                const SizedBox(height: 8),
                if (user.source == 'web')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text('Web viewer',
                            style: const TextStyle(
                                color: Colors.white24, fontSize: 12)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('V',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  )
                else
                  ...liveAlbumIds.map((albumId) {
                  final album = peerService.liveAlbums[albumId];
                  if (album == null) return const SizedBox.shrink();
                  final role = user.getRole(albumId);
                  final count = user.getUploadCount(albumId);
                  final limit = user.getUploadLimit(albumId);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            album.album.name.isEmpty ? 'Unnamed' : album.album.name,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ),
                        RoleToggle(
                          role: role,
                          onToggle: (newRole) =>
                              peerService.updateUserRole(user.id, albumId, newRole),
                        ),
                        if (role == UserRole.contributor)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: GestureDetector(
                              onTap: () =>
                                  _showLimitDialog(context, peerService, user, albumId),
                              child: Text('($count/$limit)',
                                  style: const TextStyle(
                                      color: Colors.white24, fontSize: 11)),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showLimitDialog(
      BuildContext context, PeerService peerService, ConnectedUser user, String albumId) {
    final ctrl = TextEditingController(text: user.getUploadLimit(albumId).toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title: Text('Limit for ${user.name}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
              hintText: 'Limit (1-100)',
              hintStyle: TextStyle(color: Colors.white24)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final val = int.tryParse(ctrl.text);
              if (val != null) peerService.updateUserLimit(user.id, albumId, val);
              Navigator.pop(ctx);
            },
            child: const Text('Update',
                style: TextStyle(color: Color(0xFF6B8AFF))),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityTab(PeerService peerService) {
    final logs = peerService.activityLog.reversed.toList();
    final guests = peerService.users
        .where((u) => u.status == ConnectionStatus.accepted)
        .toList();

    final filteredLogs = _selectedGuest == null
        ? logs
        : logs.where((l) => l.userName == _selectedGuest).toList();

    return Column(
      children: [
        if (guests.isNotEmpty)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              children: [
                GuestAvatar(
                  name: 'All',
                  initial: '★',
                  selected: _selectedGuest == null,
                  onTap: () => setState(() => _selectedGuest = null),
                ),
                const SizedBox(width: 8),
                ...guests.map((u) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GuestAvatar(
                        name: u.name,
                        initial: u.name[0].toUpperCase(),
                        selected: _selectedGuest == u.name,
                        onTap: () => setState(
                            () => _selectedGuest = _selectedGuest == u.name ? null : u.name),
                      ),
                    )),
              ],
            ),
          ),
        Expanded(
          child: filteredLogs.isEmpty
              ? const Center(
                  child: Text('No activity yet',
                      style: TextStyle(color: Colors.white24)))
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: filteredLogs.length,
                  itemBuilder: (context, i) {
                    final log = filteredLogs[i];
                    final isUpload = log.type == PeerEventType.upload;
                    final isDelete = log.type == PeerEventType.delete;
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isUpload
                                      ? const Color(0xFF6B8AFF)
                                      : isDelete
                                          ? const Color(0xFFF87171)
                                          : const Color(0xFF2A2A2A),
                                  border: Border.all(
                                      color: Colors.black, width: 2),
                                ),
                              ),
                              if (i < filteredLogs.length - 1)
                                Expanded(
                                    child: Container(
                                        width: 1, color: Colors.white10)),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(log.message,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500)),
                                    ),
                                    Text(
                                      '${log.timestamp.hour}:${log.timestamp.minute.toString().padLeft(2, '0')}',
                                      style: const TextStyle(
                                          color: Colors.white24, fontSize: 11),
                                    ),
                                  ],
                                ),
                                if ((isUpload || isDelete) &&
                                    log.assetIds.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    height: 60,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: log.assetIds.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 8),
                                      itemBuilder: (_, j) {
                                        final asset = peerService
                                            .getLiveAsset(log.assetIds[j]);
                                        if (asset == null) {
                                          return const SizedBox();
                                        }
                                        return ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.file(File(asset.path),
                                              width: 60,
                                              height: 60,
                                              fit: BoxFit.cover),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class GuestAvatar extends StatelessWidget {
  final String name;
  final String initial;
  final bool selected;
  final VoidCallback onTap;

  const GuestAvatar({
    super.key,
    required this.name,
    required this.initial,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected
                  ? const Color(0xFF6B8AFF)
                  : const Color(0xFF2A2A2A),
              border: Border.all(
                color: selected
                    ? const Color(0xFF6B8AFF)
                    : Colors.white.withValues(alpha: 0.1),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? const Color(0xFF6B8AFF)
                    : Colors.white54,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RoleToggle extends StatelessWidget {
  final UserRole role;
  final ValueChanged<UserRole> onToggle;

  const RoleToggle({super.key, required this.role, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _roleChip('V', UserRole.viewer, role, onToggle),
          _roleChip('C', UserRole.contributor, role, onToggle),
        ],
      ),
    );
  }

  Widget _roleChip(String label, UserRole chipRole, UserRole current, ValueChanged<UserRole> onToggle) {
    final isActive = current == chipRole;
    return GestureDetector(
      onTap: () => onToggle(chipRole),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? (chipRole == UserRole.contributor
                  ? const Color(0xFF6B8AFF)
                  : Colors.white54)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.black : Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
