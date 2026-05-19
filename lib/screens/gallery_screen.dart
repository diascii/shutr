import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import 'recent_page.dart';
import 'albums_page.dart';
import 'search_page.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  int _currentIndex = 0;

  final List<String> _titles = ['Photos', 'Albums', 'Join'];

  final List<Widget> _pages = const [
    RecentPage(),
    AlbumsPage(),
    SearchPage(),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      barrierColor: Colors.black87,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (_) => const _SettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ext = theme.extension<ShutrThemeExtension>()!;

    return ChangeNotifierProvider.value(
      value: ValueNotifier<int>(0),
      child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(theme),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: _pages,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(theme, ext),
    ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
      child: Row(
        children: [
          Text(
            _titles[_currentIndex],
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w300,
              letterSpacing: -0.8,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.settings_outlined,
                color: theme.colorScheme.onSurface, size: 22),
            onPressed: _showSettings,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav(ThemeData theme, ShutrThemeExtension ext) {
    return Container(
      decoration: BoxDecoration(
        color: ext.surfaceVariant.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.05),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _navItem(0, Icons.grid_view_rounded, Icons.grid_view_rounded,
                  'Photos', theme),
              _navItem(1, Icons.photo_album_rounded, Icons.photo_album_outlined,
                  'Albums', theme),
              _navItem(
                  2, Icons.link_rounded, Icons.link_outlined, 'Join', theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData activeIcon, IconData inactiveIcon,
      String label, ThemeData theme) {
    final isActive = _currentIndex == index;
    final color = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_currentIndex != index) {
            setState(() => _currentIndex = index);
            HapticFeedback.selectionClick();
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primary.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isActive ? activeIcon : inactiveIcon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet();

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  final TextEditingController _nameCtrl = TextEditingController();
  String _cacheSize = 'Checking...';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkCache();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _nameCtrl.text = prefs.getString('nickname') ?? '');
  }

  Future<void> _saveNickname(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', value);
  }

  Future<void> _checkCache() async {
    final tempDir = await getTemporaryDirectory();
    final shutrDir = Directory('${tempDir.path}/shutr_live');
    if (!await shutrDir.exists()) {
      setState(() => _cacheSize = '0 KB');
      return;
    }

    int totalSize = 0;
    await for (final file in shutrDir.list(recursive: true)) {
      if (file is File) totalSize += await file.length();
    }

    setState(() {
      if (totalSize < 1024) {
        _cacheSize = '$totalSize B';
      } else if (totalSize < 1024 * 1024) {
        _cacheSize = '${(totalSize / 1024).toStringAsFixed(1)} KB';
      } else {
        _cacheSize = '${(totalSize / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
    });
  }

  Future<void> _clearCache() async {
    final tempDir = await getTemporaryDirectory();
    final shutrDir = Directory('${tempDir.path}/shutr_live');
    if (await shutrDir.exists()) {
      await shutrDir.delete(recursive: true);
      await shutrDir.create();
    }
    _checkCache();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cache cleared')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Settings',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Display Name',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            onChanged: _saveNickname,
            decoration: const InputDecoration(
              hintText: 'Enter your name',
            ),
          ),
          const SizedBox(height: 32),
          Text('Storage',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Live Cache', style: theme.textTheme.bodyLarge),
            subtitle: Text(_cacheSize,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            trailing: TextButton(
              onPressed: _clearCache,
              child: Text('Clear',
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: Text(
              'Shutr v1.0.0',
              style: theme.textTheme.labelSmall?.copyWith(
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

