import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'shared_gallery_screen.dart';
import 'settings_sheet.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _codeCtrl = TextEditingController();
  bool _searching = false;
  String? _status;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length != 6) return;

    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('nickname') ?? '';

    if (name.isEmpty) {
      setState(() {
        _status = 'Please add your name in Settings first.';
        _searching = false;
      });
      return;
    }

    setState(() {
      _searching = true;
      _status = 'Scanning local network...';
    });

    try {
      final info = NetworkInfo();
      final wifiIp = await info.getWifiIP();
      if (wifiIp == null) throw 'Not connected to WiFi';

      final subnet = wifiIp.substring(0, wifiIp.lastIndexOf('.'));

      String? foundIp;
      final completer = Completer<String?>();

      // Scan all 254 IPs in parallel with a very short timeout
      final List<Future> scans = [];
      for (int i = 1; i < 255; i++) {
        final targetIp = '$subnet.$i';
        scans.add(_checkIp(targetIp, code).then((success) {
          if (success && !completer.isCompleted) {
            foundIp = targetIp;
            completer.complete(targetIp);
          }
        }));
      }

      // Wait for either a find or for all to fail
      await Future.any([
        completer.future,
        Future.wait(scans).then((_) => null),
      ]).timeout(const Duration(seconds: 8));

      if (foundIp != null) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SharedGalleryScreen(
                hostIp: foundIp!, port: 8080, code: code, nickname: name),
          ),
        );
      } else {
        throw 'Album not found. Make sure the host is on the same WiFi and has "Go Live" active.';
      }
    } catch (e) {
      if (mounted) {
        setState(() => _status = e.toString());
        _showManualIpDialog(code, name);
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<bool> _checkIp(String ip, String code) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 800);
    try {
      final request = await client.getUrl(Uri.parse('http://$ip:8080/session'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(const Utf8Decoder()).join();
        final data = jsonDecode(body);
        return data['code'] == code;
      }
    } catch (_) {}
    return false;
  }

  void _showManualIpDialog(String code, String name) {
    final ipCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        title:
            const Text('Host not found', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'UDP Discovery is blocked on this network. Please enter the host\'s IP address manually:',
              style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipCtrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'e.g. 192.168.1.15',
                hintStyle: TextStyle(color: Color(0xFF444444)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final ip = ipCtrl.text.trim();
              if (ip.isEmpty) return;
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SharedGalleryScreen(
                      hostIp: ip, port: 8080, code: code, nickname: name),
                ),
              );
            },
            child: const Text('Connect',
                style: TextStyle(color: Color(0xFF6B8AFF))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: const Color(0xFF0A0A0A),
            title: Text(
              'Join',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
            ),
            centerTitle: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 22),
                onPressed: () => SettingsSheet.show(context),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(),
                  Icon(Icons.link_rounded,
                      color: Colors.white.withValues(alpha: 0.15), size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Join Album',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the 6-digit code to join a live gallery.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Center(
                    child: SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _codeCtrl,
                        maxLength: 6,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        keyboardType: TextInputType.text,
                        style: const TextStyle(
                          color: Color(0xFF6B8AFF),
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 16,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: '000000',
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.05),
                              letterSpacing: 16),
                          filled: true,
                          fillColor: const Color(0xFF1C1C1C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                                color: Color(0xFF6B8AFF), width: 1),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 24),
                        ),
                        onSubmitted: (_) => _join(),
                      ),
                    ),
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 24),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          _status!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Color(0xFFF87171),
                              fontSize: 13,
                              height: 1.4),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _searching ? null : _join,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6B8AFF),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: _searching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black))
                          : const Text('Join Gallery',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
