import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'album_detail_page.dart';
import 'photo_viewer.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<_AlbumData> _albums = [];
  List<AssetEntity> _allAssets = [];
  List<_DateGroup> _dateGroups = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (permission != PermissionState.authorized &&
        permission != PermissionState.limited) {
      setState(() => _loading = false);
      return;
    }

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(needTitle: false),
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false)
        ],
      ),
    );

    // Load albums
    final albums = <_AlbumData>[];
    AssetPathEntity? allPath;
    for (final path in paths) {
      final count = await path.assetCountAsync;
      if (count == 0) continue;
      final first = await path.getAssetListRange(start: 0, end: 1);
      if (first.isEmpty) continue;
      albums.add(_AlbumData(path: path, count: count, thumbnail: first.first));
      if (path.isAll) allPath = path;
    }
    albums.sort((a, b) {
      if (a.path.isAll) return -1;
      if (b.path.isAll) return 1;
      return b.count.compareTo(a.count);
    });

    // Load all assets
    allPath ??= paths.isNotEmpty ? paths.first : null;
    List<AssetEntity> assets = [];
    if (allPath != null) {
      final total = await allPath.assetCountAsync;
      assets =
          await allPath.getAssetListRange(start: 0, end: total.clamp(0, 500));
    }

    setState(() {
      _albums = albums;
      _allAssets = assets;
      _dateGroups = _groupByDate(assets);
      _loading = false;
    });
  }

  List<_DateGroup> _groupByDate(List<AssetEntity> assets) {
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
            ? '${_monthName(dt.month)} ${dt.day}'
            : '${_monthName(dt.month)} ${dt.day}, ${dt.year}';
      }
      map.putIfAbsent(label, () => []).add(asset);
    }
    return map.entries
        .map((e) => _DateGroup(label: e.key, assets: e.value))
        .toList();
  }

  String _monthName(int month) {
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

  List<_AlbumData> get _filteredAlbums {
    if (_query.isEmpty) return [];
    return _albums
        .where((a) => a.path.name.toLowerCase().contains(_query))
        .toList();
  }

  List<_DateGroup> get _filteredGroups {
    if (_query.isEmpty) return _dateGroups;
    return _dateGroups
        .where((g) => g.label.toLowerCase().contains(_query))
        .toList();
  }

  void _openViewer(AssetEntity asset) {
    final index = _allAssets.indexOf(asset);
    if (index == -1) return;
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            PhotoViewer(assets: _allAssets, initialIndex: index),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 280),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF4ADE80),
                    strokeWidth: 1.5,
                  ),
                )
              : _buildResults(),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.search, color: Color(0xFF555555), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                focusNode: _focusNode,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: const Color(0xFF4ADE80),
                decoration: const InputDecoration(
                  hintText: 'Search by date(ex: May 12) or album...',
                  hintStyle: TextStyle(color: Color(0xFF555555), fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  _focusNode.unfocus();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Icon(Icons.close, color: Color(0xFF555555), size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final albums = _filteredAlbums;
    final groups = _filteredGroups;

    if (groups.isEmpty && albums.isEmpty) {
      return const Center(
        child: Text(
          'No results',
          style: TextStyle(color: Color(0xFF555555), fontSize: 15),
        ),
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // Albums section (only when searching)
        if (albums.isNotEmpty) ...[
          _sectionHeader('Albums'),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 136,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: albums.length,
                itemBuilder: (_, i) => _AlbumChip(
                  data: albums[i],
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailPage(
                        album: albums[i].path,
                        totalCount: albums[i].count,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],

        // Photos section header (only when searching)
        if (_query.isNotEmpty && groups.isNotEmpty) _sectionHeader('Photos'),

        // Date groups
        ...groups.expand((g) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Text(
                    g.label,
                    style: const TextStyle(
                      color: Color(0xFF8A8A8A),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => GestureDetector(
                    onTap: () => _openViewer(g.assets[i]),
                    child: AssetEntityImage(
                      g.assets[i],
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(300),
                      fit: BoxFit.cover,
                      frameBuilder: (_, child, frame, __) {
                        if (frame == null) {
                          return const ColoredBox(color: Color(0xFF1C1C1C));
                        }
                        return child;
                      },
                    ),
                  ),
                  childCount: g.assets.length,
                ),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
              ),
            ]),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  SliverToBoxAdapter _sectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _AlbumChip extends StatelessWidget {
  final _AlbumData data;
  final VoidCallback onTap;

  const _AlbumChip({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: AssetEntityImage(
                data.thumbnail,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(200),
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, __) {
                  if (frame == null) {
                    return const SizedBox(
                        width: 100,
                        height: 100,
                        child: ColoredBox(color: Color(0xFF1C1C1C)));
                  }
                  return child;
                },
              ),
            ),
            const SizedBox(height: 5),
            Text(
              data.path.name.isEmpty ? 'Unnamed' : data.path.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w400),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${data.count}',
              style: const TextStyle(
                  color: Color(0xFF8A8A8A),
                  fontSize: 11,
                  fontWeight: FontWeight.w300),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumData {
  final AssetPathEntity path;
  final int count;
  final AssetEntity thumbnail;
  _AlbumData(
      {required this.path, required this.count, required this.thumbnail});
}

class _DateGroup {
  final String label;
  final List<AssetEntity> assets;
  _DateGroup({required this.label, required this.assets});
}
