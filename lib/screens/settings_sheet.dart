import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      barrierColor: Colors.black87,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (_) => const SettingsSheet(),
    );
  }
}

class _SettingsSheetState extends State<SettingsSheet> {
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
          const SizedBox(height: 16),
          Text('About',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Shutr'),
            subtitle: Text('v1.0.0',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
            trailing: Text('Peer-to-peer photo sharing',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                )),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
