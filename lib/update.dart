import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'strings.dart';

/// A newer APK announced by the server (admin: notification settings page).
class UpdateInfo {
  const UpdateInfo({required this.version, required this.url, this.notes, required this.required});

  final String version;
  final String? url;
  final String? notes;

  /// Below the minimum version: the app must be updated before use.
  final bool required;
}

class AppUpdate {
  static const _dismissedKey = 'dismissed_update';
  static const _device = MethodChannel('qalam/device');
  static const _playStoreUrl = 'https://play.google.com/store/apps/details?id=iq.edu.alqalam.qalam_notify';

  /// Null when the installed app is current (or the server says nothing).
  static Future<UpdateInfo?> check() async {
    try {
      final body = await api.get('/config');
      final app = body['app'] as Map?;
      final latest = app?['version']?.toString();
      if (latest == null || latest.isEmpty) return null;

      final current = (await PackageInfo.fromPlatform()).version;
      if (compareVersions(latest, current) <= 0) return null;

      final min = app?['min_version']?.toString();
      return UpdateInfo(
        version: latest,
        url: app?['download_url']?.toString(),
        notes: app?['notes']?.toString(),
        required: min != null && min.isNotEmpty && compareVersions(min, current) > 0,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<bool> wasDismissed(String version) async => (await api.readSetting(_dismissedKey)) == version;

  static Future<void> dismiss(String version) => api.writeSetting(_dismissedKey, version);

  /// Installed from Google Play: updates come through the store, never a downloaded APK.
  static Future<bool> fromPlayStore() async {
    try {
      return await _device.invokeMethod<String>('installerSource') == 'com.android.vending';
    } catch (_) {
      return false;
    }
  }

  /// Optional update from the banner: the same dialog as a required one, but closable.
  static Future<void> start(BuildContext context, UpdateInfo info) {
    return showDialog<void>(context: context, builder: (_) => UpdateDialog(info: info));
  }

  static Future<void> openExternally(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).t('cannot_open'))));
    }
  }

  /// "1.10.0" > "1.9.3"; missing parts count as zero.
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v.split('+').first.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    final pa = parts(a), pb = parts(b);
    for (var i = 0; i < 3; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

/// Non-dismissible prompt for a required update.
Future<void> showRequiredUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(context: context, barrierDismissible: false, builder: (_) => UpdateDialog(info: info));
}

enum _Phase { idle, downloading, installing, permission, failed }

/// Downloads the APK inside the app and hands it to the system installer, which updates
/// the installed app in place (same signing key, so nothing is lost and nothing is uninstalled).
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.info});

  final UpdateInfo info;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> with WidgetsBindingObserver {
  _Phase _phase = _Phase.idle;
  double? _progress;
  String? _path;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from "Install unknown apps": try again without another tap.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _phase == _Phase.permission) _install();
  }

  Future<void> _start() async {
    final url = widget.info.url;
    if (await AppUpdate.fromPlayStore()) {
      if (mounted) await AppUpdate.openExternally(context, AppUpdate._playStoreUrl);
      return;
    }
    if (url == null) return;
    if (!Platform.isAndroid) {
      if (mounted) await AppUpdate.openExternally(context, url);
      return;
    }
    await _download(url);
  }

  Future<void> _download(String url) async {
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
    });
    try {
      final path = await AppUpdate._device.invokeMethod<String>('updateFile');
      final file = File(path!);
      final response = await api.client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');

      final total = response.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      var shown = -1;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          final percent = total > 0 ? received * 100 ~/ total : -1;
          if (percent != shown && mounted) {
            shown = percent;
            setState(() => _progress = percent < 0 ? null : percent / 100);
          }
        }
      } finally {
        await sink.close();
      }

      // An APK is a zip ("PK"); anything else is an error page behind a wrong link
      final head = await file.openRead(0, 2).expand((bytes) => bytes).toList();
      if (head.length < 2 || head[0] != 0x50 || head[1] != 0x4B) throw const FormatException('not an APK');

      _path = path;
      await _install();
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _install() async {
    final path = _path;
    if (path == null) return;
    String? result;
    try {
      result = await AppUpdate._device.invokeMethod<String>('installApk', {'path': path});
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    setState(() => _phase = switch (result) {
          'started' => _Phase.installing,
          'permission' => _Phase.permission,
          _ => _Phase.failed,
        });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final info = widget.info;
    final busy = _phase == _Phase.downloading;

    final message = switch (_phase) {
      _Phase.idle => [
          s.t(info.required ? 'update_required_hint' : 'update_available'),
          if (info.notes != null && info.notes!.trim().isNotEmpty) info.notes!.trim(),
        ].join('\n\n'),
      _Phase.downloading => s.t('update_downloading'),
      _Phase.installing => s.t('update_ready'),
      _Phase.permission => s.t('update_permission'),
      _Phase.failed => s.t('update_failed'),
    };

    return PopScope(
      canPop: !info.required && !busy,
      child: AlertDialog(
        icon: Icon(_phase == _Phase.failed ? Icons.error_outline_rounded : Icons.system_update_rounded, size: 36),
        title: Text('${s.t(info.required ? 'update_required' : 'update_available')} · ${info.version}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: TextStyle(height: 1.5, color: scheme.onSurfaceVariant)),
            if (busy) ...[
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(value: _progress, minHeight: 8),
              ),
              if (_progress != null) ...[
                const SizedBox(height: 8),
                Text('${(_progress! * 100).round()}%', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ],
          ],
        ),
        actions: [
          if (_phase == _Phase.failed && info.url != null)
            TextButton(onPressed: () => AppUpdate.openExternally(context, info.url!), child: Text(s.t('open_in_browser'))),
          if (!info.required && !busy)
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.t('later'))),
          if (!busy)
            FilledButton.icon(
              onPressed: info.url == null
                  ? null
                  : switch (_phase) {
                      _Phase.idle || _Phase.failed => _start,
                      _ => _install,
                    },
              icon: Icon(_phase == _Phase.failed ? Icons.refresh_rounded : Icons.download_rounded),
              label: Text(s.t(switch (_phase) {
                _Phase.idle => 'update_now',
                _Phase.failed => 'retry',
                _ => 'install',
              })),
            ),
        ],
      ),
    );
  }
}

/// Dismissible banner for an optional update.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.info, required this.onDismiss});

  final UpdateInfo info;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.system_update, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${s.t('update_available')} (${info.version})${info.notes == null ? '' : '\n${info.notes}'}',
                      style: TextStyle(color: scheme.onPrimaryContainer, height: 1.4, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (info.url != null)
                    TextButton(onPressed: () => AppUpdate.start(context, info), child: Text(s.t('update_now'))),
                  TextButton(onPressed: onDismiss, child: Text(s.t('later'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
