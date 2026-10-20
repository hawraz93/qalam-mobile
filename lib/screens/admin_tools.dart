import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

/// Label for a part of the site ('posts', 'department', …), or the raw path when unknown.
String sectionLabel(S s, String key) {
  final label = s.t('sec_$key');
  return label == 'sec_$key' ? '/$key' : label;
}

String eventLabel(S s, String? event) {
  if (event == null || event.isEmpty) return '—';
  final label = s.t('ev_$event');
  return label == 'ev_$event' ? event : label;
}

Color eventColor(String? event) => switch (event) {
      'delete' || 'failed_login' || 'deactivate' => Tone.danger,
      'create' || 'activate' => Tone.success,
      'edit' || 'status_update' || 'role_change' => Tone.warning,
      'login' || 'logout' => Tone.info,
      _ => Tone.neutral,
    };

String _formatNumber(int n) {
  final digits = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

// ---------------------------------------------------------------------------
// Website visits
// ---------------------------------------------------------------------------

class VisitsScreen extends StatefulWidget {
  const VisitsScreen({super.key});

  @override
  State<VisitsScreen> createState() => _VisitsScreenState();
}

class _VisitsScreenState extends State<VisitsScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('website_visits'))),
      body: Column(
        children: [
          FilterBar(
            segments: {for (final d in const [7, 30, 90]) '$d': s.t('days_n').replaceAll('{n}', '$d')},
            selected: '$_days',
            onChanged: (value) => setState(() => _days = int.parse(value)),
          ),
          Expanded(
            child: Loader(
              key: ValueKey(_days),
              load: () async => Map<String, dynamic>.from(await api.get('/insights/visits', {'days': '$_days'}) as Map),
              builder: (context, data, reload) => RefreshIndicator(
                onRefresh: () async => reload(),
                child: _VisitsBody(data: data),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VisitsBody extends StatelessWidget {
  const _VisitsBody({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final total = (data['total'] as num?)?.toInt() ?? 0;
    final previous = (data['previous_total'] as num?)?.toInt() ?? 0;
    final change = previous == 0 ? null : ((total - previous) / previous * 100).round();
    final trend = (data['trend'] as List? ?? []).map((p) => (p as Map)['visits'] as int).toList();
    final sections = (data['sections'] as List? ?? []).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final pages = (data['top_pages'] as List? ?? []).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    final sectionMax = sections.isEmpty ? 1 : (sections.first['visits'] as num).toInt().clamp(1, 1 << 31);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.t('total_visits'), style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_formatNumber(total), textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
                    const SizedBox(width: 10),
                    if (change != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Pill(
                          // Embedded LTR so "+16%" does not flip to "16%+" in Arabic / Kurdish
                          '\u202A${change >= 0 ? '+' : ''}$change%\u202C',
                          color: change >= 0 ? Tone.success : Tone.danger,
                          icon: change >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        ),
                      ),
                  ],
                ),
                if (change != null)
                  Text(s.t('vs_previous'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                SizedBox(height: 120, child: _TrendBars(values: trend, color: scheme.primary)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.today_outlined, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(s.t('ov_visits_today'), style: TextStyle(color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    Text(_formatNumber((data['today'] as num?)?.toInt() ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('by_section'),
          icon: Icons.pie_chart_outline_rounded,
          children: [
            for (final row in sections)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(child: Text(sectionLabel(s, row['key'].toString()), style: const TextStyle(fontWeight: FontWeight.w600))),
                      Text(_formatNumber((row['visits'] as num).toInt()), style: TextStyle(color: scheme.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (row['visits'] as num) / sectionMax,
                        minHeight: 7,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('top_pages'),
          icon: Icons.leaderboard_outlined,
          children: [
            for (var i = 0; i < pages.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text('${i + 1}', style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pages[i]['title']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(pages[i]['path']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_formatNumber((pages[i]['visits'] as num).toInt()), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Daily visits as slim bars, oldest on the left (dates read left to right in every language).
class _TrendBars extends StatelessWidget {
  const _TrendBars({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final max = values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b).clamp(1, 1 << 31);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: values.length > 40 ? 0.5 : 1.5),
                child: FractionallySizedBox(
                  heightFactor: (values[i] / max).clamp(0.02, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i == values.length - 1 ? color : color.withValues(alpha: 0.45),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity log
// ---------------------------------------------------------------------------

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key, this.causerId, this.title});

  /// Only this person's actions (opened from a user's page).
  final int? causerId;
  final String? title;

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  static const _events = ['', 'login', 'failed_login', 'create', 'edit', 'delete', 'status_update', 'role_change'];
  String _event = '';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? s.t('activity_log'))),
      body: Column(
        children: [
          FilterBar(
            segments: {for (final e in _events) e: e.isEmpty ? s.t('all_events') : eventLabel(s, e)},
            selected: _event,
            onChanged: (value) => setState(() => _event = value),
          ),
          SearchField(onChanged: (value) => setState(() => _search = value)),
          Expanded(
            child: PagedList(
              path: '/activity',
              query: {
                if (_event.isNotEmpty) 'event': _event,
                if (_search.isNotEmpty) 'search': _search,
                if (widget.causerId != null) 'causer_id': '${widget.causerId}',
              },
              emptyIcon: Icons.history_rounded,
              itemBuilder: (context, row, refresh) => ItemCard(
                icon: Icons.history_rounded,
                accent: eventColor(row['event']?.toString()),
                title: row['description']?.toString() ?? '',
                subtitle: [
                  (row['causer'] as Map?)?['name'],
                  row['ip'],
                ].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                trailing: relativeDate(context, row['created_at']),
                chips: [
                  Pill(eventLabel(s, row['event']?.toString()), color: eventColor(row['event']?.toString())),
                  if (row['subject'] != null) Pill(row['subject'].toString()),
                  if (row['source'] == 'mobile_app') const Pill('App', icon: Icons.phone_android_rounded),
                ],
                onTap: () => _showDetails(context, row['id'] as int),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDetails(BuildContext context, int id) {
    final s = S.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => Loader(
          load: () async {
            final body = await api.get('/activity/$id');
            return Map<String, dynamic>.from(body['data'] as Map);
          },
          builder: (context, row, reload) {
            final properties = Map<String, dynamic>.from(row['properties'] as Map? ?? {});
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(row['description']?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                InfoRow(s.t('done_by'), (row['causer'] as Map?)?['name'], icon: Icons.person_outline),
                InfoRow(s.t('ip_address'), row['ip'], icon: Icons.lan_outlined),
                InfoRow('Device', [row['device'], row['platform'], row['browser']].where((v) => v != null).join(' · '), icon: Icons.devices_outlined),
                InfoRow(s.t('details'), shortDate(row['created_at']), icon: Icons.schedule),
                if (properties.isNotEmpty) ...[
                  const Divider(height: 28),
                  for (final entry in properties.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(entry.key, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ),
                            Expanded(child: SelectableText('${entry.value}', style: const TextStyle(fontSize: 12.5))),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Users and roles
// ---------------------------------------------------------------------------

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  String _tab = 'all';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('users_roles'))),
      body: Column(
        children: [
          FilterBar(
            segments: {'all': s.t('users_all'), 'active': s.t('users_active'), 'pending': s.t('users_pending')},
            selected: _tab,
            onChanged: (value) => setState(() => _tab = value),
          ),
          SearchField(onChanged: (value) => setState(() => _search = value)),
          Expanded(
            child: PagedList(
              path: '/users',
              query: {'tab': _tab, if (_search.isNotEmpty) 'search': _search},
              emptyIcon: Icons.people_outline_rounded,
              itemBuilder: (context, user, refresh) => ItemCard(
                icon: user['is_active'] == true ? Icons.person_outline_rounded : Icons.person_off_outlined,
                accent: user['is_active'] == true ? null : Tone.warning,
                title: user['name']?.toString() ?? '',
                subtitle: [user['email'], user['department']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                unread: user['is_active'] != true,
                chips: [
                  for (final role in (user['roles'] as List? ?? [])) Pill(role.toString(), color: Tone.info),
                  if (user['is_active'] != true) Pill(s.t('users_pending'), color: Tone.warning),
                ],
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserDetailScreen(id: user['id'] as int)));
                  refresh();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserDetailScreen extends StatelessWidget {
  const UserDetailScreen({super.key, required this.id});

  final int id;

  Future<void> _setActive(BuildContext context, Map<String, dynamic> user, bool active, VoidCallback reload) async {
    final s = S.of(context);
    if (!active) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(s.t('deactivate_confirm').replaceAll('{name}', user['name']?.toString() ?? '')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Tone.danger),
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('ev_deactivate')),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    try {
      await api.put('/users/$id/active', {'active': active});
      if (context.mounted) toast(context, s.t(active ? 'activated' : 'saved'));
      reload();
    } catch (e) {
      if (context.mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _changeRole(BuildContext context, Map<String, dynamic> user, VoidCallback reload) async {
    final s = S.of(context);
    final List<Map<String, dynamic>> roles;
    try {
      final body = await api.get('/roles');
      roles = (body['data'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } catch (e) {
      if (context.mounted) toast(context, errorText(context, e));
      return;
    }
    if (!context.mounted) return;

    final current = (user['roles'] as List? ?? []).firstOrNull?.toString();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(s.t('change_role'), style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(s.t('roles_on_website_hint'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            for (final role in roles)
              ListTile(
                leading: Icon(
                  role['name'] == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: role['name'] == current ? Theme.of(context).colorScheme.primary : null,
                ),
                title: Text(role['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${role['users']}'),
                trailing: role['privileged'] == true ? Pill(s.t('role_privileged'), color: Tone.danger, icon: Icons.shield_outlined) : null,
                onTap: () => Navigator.pop(context, role['name'].toString()),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == current || !context.mounted) return;

    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.t('role_confirm').replaceAll('{name}', user['name']?.toString() ?? '').replaceAll('{role}', picked)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('change_role'))),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;

    try {
      await api.put('/users/$id/role', {'role': picked});
      if (context.mounted) toast(context, s.t('saved'));
      reload();
    } catch (e) {
      if (context.mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('users_roles'))),
      body: Loader(
        load: () async {
          final body = await api.get('/users/$id');
          return Map<String, dynamic>.from(body['data'] as Map);
        },
        builder: (context, user, reload) {
          final active = user['is_active'] == true;
          final roles = (user['roles'] as List? ?? []).map((r) => r.toString()).toList();
          final recent = (user['recent_activity'] as List? ?? []).map((r) => Map<String, dynamic>.from(r as Map)).toList();
          final isMe = user['id'] == api.user?['id'];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Avatar(name: user['name']?.toString() ?? '', size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(user['name']?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final role in roles) Pill(role, color: Tone.info),
                          Pill(s.t(active ? 'users_active' : 'users_pending'), color: active ? Tone.success : Tone.warning),
                        ]),
                      ]),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FieldGroup(
                title: s.t('details'),
                icon: Icons.badge_outlined,
                children: [
                  InfoRow(s.t('email'), user['email'], icon: Icons.alternate_email),
                  InfoRow(s.t('phone'), user['phone'], icon: Icons.phone_outlined),
                  InfoRow(s.t('department'), user['department'], icon: Icons.account_tree_outlined),
                  InfoRow('Username', user['username'], icon: Icons.alternate_email_rounded),
                  InfoRow(s.t('recent_activity'), user['last_activity'] == null ? null : shortDate(user['last_activity']), icon: Icons.schedule),
                ],
              ),
              const SizedBox(height: 12),
              FieldGroup(
                title: s.t('role'),
                icon: Icons.admin_panel_settings_outlined,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: active,
                    onChanged: isMe ? null : (value) => _setActive(context, user, value, reload),
                    title: Text(s.t('active_account'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 6),
                  FilledButton.tonalIcon(
                    onPressed: () => _changeRole(context, user, reload),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: Text(s.t('change_role')),
                  ),
                ],
              ),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 12),
                FieldGroup(
                  title: s.t('recent_activity'),
                  icon: Icons.history_rounded,
                  children: [
                    for (var i = 0; i < recent.length; i++)
                      TimelineEntry(
                        icon: Icons.circle,
                        color: eventColor(recent[i]['event']?.toString()),
                        title: eventLabel(s, recent[i]['event']?.toString()),
                        text: recent[i]['description']?.toString() ?? '',
                        date: relativeDate(context, recent[i]['created_at']),
                        last: i == recent.length - 1,
                      ),
                    if (api.can('activity'))
                      TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ActivityLogScreen(causerId: id, title: user['name']?.toString()),
                        )),
                        child: Text(s.t('see_all')),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
