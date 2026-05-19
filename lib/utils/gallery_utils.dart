import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

// ─── Date grouping ────────────────────────────────────────────────────────────

class DateGroup {
  final String label;
  final List<AssetEntity> assets;
  DateGroup({required this.label, required this.assets});
}

List<DateGroup> groupAssetsByDate(List<AssetEntity> assets) {
  final map = <String, List<AssetEntity>>{};
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  for (final asset in assets) {
    final dt = asset.createDateTime;
    final day = DateTime(dt.year, dt.month, dt.day);

    String label;
    if (day == today) {
      label = 'Today';
    } else if (day == yesterday) {
      label = 'Yesterday';
    } else {
      final sameYear = dt.year == now.year;
      label = sameYear
          ? '${monthName(dt.month)} ${dt.day}'
          : '${monthName(dt.month)} ${dt.day}, ${dt.year}';
    }
    map.putIfAbsent(label, () => []).add(asset);
  }
  // Sort groups: Today, Yesterday, then newest date first
  final order = <String, int>{'Today': 0, 'Yesterday': 1};
  return map.entries
      .map((e) => DateGroup(label: e.key, assets: e.value))
      .toList()
      ..sort((a, b) {
        final oa = order[a.label] ?? -1;
        final ob = order[b.label] ?? -1;
        if (oa >= 0 && ob >= 0) return oa.compareTo(ob);
        if (oa >= 0) return -1;
        if (ob >= 0) return 1;
        // Both are date strings — compare by parsing
        final da = _parseDateLabel(a.label);
        final db = _parseDateLabel(b.label);
        return db.compareTo(da); // newest first
      });
}

DateTime _parseDateLabel(String label) {
  // e.g. "May 10" or "May 10, 2025"
  final now = DateTime.now();
  final parts = label.replaceAll(',', '').split(' ');
  final month = _monthIndex(parts[0]);
  final day = int.tryParse(parts[1]) ?? 1;
  final year = parts.length > 2 ? int.tryParse(parts[2]) ?? now.year : now.year;
  return DateTime(year, month, day);
}

int _monthIndex(String name) {
  const names = ['January','February','March','April','May','June',
    'July','August','September','October','November','December'];
  for (int i = 0; i < names.length; i++) {
    if (names[i].toLowerCase() == name.toLowerCase()) return i + 1;
  }
  return 1;
}

String monthName(int month) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  return names[month - 1];
}

String monthNameShort(int month) {
  const names = [
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
  return names[month - 1];
}

// ─── Shared PhotoCell ─────────────────────────────────────────────────────────

class PhotoCell extends StatefulWidget {
  final AssetEntity asset;
  final int index;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const PhotoCell({
    super.key,
    required this.asset,
    required this.index,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<PhotoCell> createState() => _PhotoCellState();
}

class _PhotoCellState extends State<PhotoCell> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: widget.asset.id,
            child: AssetEntityImage(
              widget.asset,
              isOriginal: false,
              thumbnailSize: const ThumbnailSize.square(200),
              fit: BoxFit.cover,
              frameBuilder: (_, child, frame, __) {
                if (frame == null) {
                  return ColoredBox(
                    color: theme.colorScheme.surfaceContainer,
                  );
                }
                return child;
              },
            ),
          ),
          if (widget.selectionMode && !widget.selected)
            const DecoratedBox(
                decoration: BoxDecoration(color: Colors.black54)),
          if (widget.selected)
            DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
          if (widget.selectionMode)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: widget.selected
                        ? theme.colorScheme.primary
                        : Colors.white,
                    width: 1.5,
                  ),
                  boxShadow: widget.selected
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
                child: widget.selected
                    ? Icon(Icons.check,
                        size: 14, color: theme.colorScheme.onPrimary)
                    : null,
              ),
            ),
          if (widget.asset.type == AssetType.video)
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 24),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Shared SelectionBar ──────────────────────────────────────────────────────

class SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final VoidCallback onCreateAlbum;
  final VoidCallback onSelectAll;

  const SelectionBar({
    super.key,
    required this.count,
    required this.onDelete,
    required this.onCancel,
    required this.onCreateAlbum,
    required this.onSelectAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
            top: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.1), width: 0.5)),
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
                    onPressed: onSelectAll,
                    child: Text('Select All',
                        style: TextStyle(color: theme.colorScheme.primary)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onCancel,
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
                    onPressed: count > 0 ? onCreateAlbum : null,
                    icon: Icon(Icons.add_to_photos_outlined,
                        color: count > 0
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3),
                        size: 18),
                    label: Text('New Album',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: count > 0
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.3),
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: count > 0 ? onDelete : null,
                    icon: Icon(Icons.delete_outline,
                        color: theme.colorScheme.error, size: 18),
                    label: Text('Delete $count',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared DeleteDialog ──────────────────────────────────────────────────────

class DeleteDialog extends StatelessWidget {
  final int count;
  final bool single;
  const DeleteDialog({super.key, required this.count, this.single = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = single
        ? 'Permanently delete this photo from your device?'
        : 'Delete $count ${count == 1 ? 'photo' : 'photos'} permanently from your device?';
    return AlertDialog(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(single ? 'Delete photo' : 'Delete photos',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w600)),
      content: Text(body,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          )),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('Delete',
              style: TextStyle(
                  color: theme.colorScheme.error, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ─── Shared DateHeaderDelegate ────────────────────────────────────────────────

class DateHeaderDelegate extends SliverPersistentHeaderDelegate {
  final String label;
  final bool uppercase;
  DateHeaderDelegate({required this.label, this.uppercase = false});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      alignment: Alignment.centerLeft,
      child: Text(
        uppercase ? label.toUpperCase() : label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: uppercase ? FontWeight.w700 : FontWeight.w600,
          letterSpacing: uppercase ? 1.0 : 0.2,
          fontSize: uppercase ? 11 : 13,
        ),
      ),
    );
  }

  @override
  double get maxExtent => 44;
  @override
  double get minExtent => 44;
  @override
  bool shouldRebuild(covariant DateHeaderDelegate old) => old.label != label;
}
