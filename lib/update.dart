import 'package:flutter/material.dart';
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

  static Future<void> download(BuildContext context, UpdateInfo info) async {
    final url = info.url;
    if (url == null) return;
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
  final s = S.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.system_update, size: 36),
        title: Text(s.t('update_required')),
        content: Text('${s.t('update_required_hint')}\n\n${s.t('version')}: ${info.version}${info.notes == null ? '' : '\n\n${info.notes}'}'),
        actions: [
          FilledButton.icon(
            onPressed: info.url == null ? null : () => AppUpdate.download(context, info),
            icon: const Icon(Icons.download),
            label: Text(s.t('download')),
          ),
        ],
      ),
    ),
  );
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
                    TextButton(onPressed: () => AppUpdate.download(context, info), child: Text(s.t('download'))),
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
