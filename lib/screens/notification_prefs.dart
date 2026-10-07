import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

/// Which push categories this user wants on their phone. The inbox still receives everything.
class NotificationPrefsScreen extends StatefulWidget {
  const NotificationPrefsScreen({super.key});

  @override
  State<NotificationPrefsScreen> createState() => _NotificationPrefsScreenState();
}

class _NotificationPrefsScreenState extends State<NotificationPrefsScreen> {
  late Map<String, bool> _prefs = {
    for (final e in (api.user?['push_preferences'] as Map? ?? {}).entries) e.key.toString(): e.value == true,
  };
  bool _busy = false;

  List<(String key, IconData icon)> get _categories => [
        ('ticket_updates', Icons.reply),
        if (api.can('it_tickets')) ('it_tickets', Icons.confirmation_number_outlined),
        if (api.can('complaints')) ('complaints', Icons.campaign_outlined),
        if (api.can('contacts')) ('contacts', Icons.mail_outline),
        if (api.can('careers')) ('careers', Icons.work_outline),
      ];

  Future<void> _set(String key, bool value) async {
    final previous = _prefs[key] ?? true;
    setState(() {
      _prefs[key] = value;
      _busy = true;
    });
    try {
      final body = await api.put('/me/push-preferences', {key: value});
      _prefs = {for (final e in (body['data'] as Map).entries) e.key.toString(): e.value == true};
      api.user?['push_preferences'] = Map<String, dynamic>.from(body['data'] as Map);
    } catch (e) {
      _prefs[key] = previous;
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('notification_prefs'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.t('notification_prefs_hint'), style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.5)),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (key, icon) in _categories) ...[
                  SwitchListTile(
                    secondary: Icon(icon, color: scheme.primary),
                    title: Text(s.t('notif_$key'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    value: _prefs[key] ?? true,
                    onChanged: _busy ? null : (v) => _set(key, v),
                  ),
                  if (key != _categories.last.$1) const Divider(indent: 56),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
