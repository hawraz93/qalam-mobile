import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';
import 'admin_tools.dart';
import 'announcements.dart';
import 'teachers_admin.dart';
import 'web_page.dart';
import 'work.dart' show WorkShortcut;

/// Management hub: the overview (dashboard.view), accounts to activate (users.manage)
/// and job applications (careers.manage). Each part shows only with its permission.
class ManagementScreen extends StatelessWidget {
  const ManagementScreen({super.key, this.onOpenWork});

  /// Jumps to a section of the Work tab ('tickets', 'complaints', 'contacts').
  final WorkShortcut? onOpenWork;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('management'))),
      body: api.can('management')
          ? Loader(
              load: () async => Map<String, dynamic>.from(await api.get('/management/overview') as Map),
              builder: (context, data, reload) => RefreshIndicator(
                onRefresh: () async => reload(),
                child: _Overview(data: data, reload: reload, onOpenWork: onOpenWork),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: _links(context, const {}, () {}),
            ),
    );
  }
}

List<Widget> _links(BuildContext context, Map<String, dynamic> data, VoidCallback reload) {
  final s = S.of(context);
  int n(String group, String key) => ((data[group] as Map?)?[key] as num?)?.toInt() ?? 0;

  Widget link(IconData icon, String label, int badge, Widget screen) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (badge > 0) Badge(label: Text('$badge')),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded),
          ]),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) => reload()),
        ),
      );

  return [
    if (api.can('activity')) link(Icons.query_stats_rounded, s.t('website_visits'), 0, const VisitsScreen()),
    if (api.can('activity')) link(Icons.history_rounded, s.t('activity_log'), 0, const ActivityLogScreen()),
    if (api.can('teachers')) link(Icons.school_outlined, s.t('teachers_admin'), n('teachers', 'pending'), const TeachersAdminScreen()),
    if (api.can('users')) link(Icons.manage_accounts_outlined, s.t('users_roles'), 0, const UsersScreen()),
    if (api.can('users')) link(Icons.person_add_alt_1_outlined, s.t('pending_users'), n('accounts', 'pending'), const PendingUsersScreen()),
    if (api.can('careers')) link(Icons.work_outline_rounded, s.t('job_applications'), n('careers', 'new'), const ApplicationsScreen()),
    if (api.can('announcements')) link(Icons.campaign_outlined, s.t('announcements'), 0, const AnnouncementsScreen()),
  ];
}

class _Overview extends StatelessWidget {
  const _Overview({required this.data, required this.reload, this.onOpenWork});

  final Map<String, dynamic> data;
  final VoidCallback reload;
  final WorkShortcut? onOpenWork;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    int n(String group, String key) => ((data[group] as Map?)?[key] as num?)?.toInt() ?? 0;
    final tickets = data['tickets'] as Map? ?? {};
    final rating = (tickets['rating_average'] as num?)?.toDouble();
    final announcements = (data['announcements'] as List? ?? []).map((a) => Map<String, dynamic>.from(a as Map)).toList();

    void work(String section) {
      if (onOpenWork == null) return;
      Navigator.of(context).pop();
      onOpenWork!(section);
    }

    final attention = n('tickets', 'needs_attention') + n('complaints', 'needs_attention') + n('contacts', 'unread') + n('accounts', 'pending') + n('careers', 'new');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        FieldGroup(
          title: attention == 0 ? s.t('all_clear') : s.t('needs_attention'),
          icon: attention == 0 ? Icons.verified_outlined : Icons.notification_important_outlined,
          children: [
            ColumnsWrap(
              columns: 3,
              children: [
                StatCell(icon: Icons.support_agent_rounded, label: s.t('ov_tickets'), value: n('tickets', 'needs_attention'), color: Tone.warning, onTap: () => work('tickets')),
                StatCell(icon: Icons.campaign_outlined, label: s.t('complaints'), value: n('complaints', 'needs_attention'), color: Tone.danger, onTap: () => work('complaints')),
                StatCell(icon: Icons.mail_outline_rounded, label: s.t('contacts'), value: n('contacts', 'unread'), color: Tone.success, onTap: () => work('contacts')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('ov_tickets'),
          icon: Icons.support_agent_rounded,
          children: [
            _Metric(label: s.t('ov_overdue'), value: '${n('tickets', 'overdue')}', alert: n('tickets', 'overdue') > 0),
            _Metric(label: s.t('ov_unassigned'), value: '${n('tickets', 'unassigned')}', alert: n('tickets', 'unassigned') > 0),
            _Metric(label: s.t('ov_resolved_week'), value: '${n('tickets', 'resolved_week')}'),
            _Metric(
              label: s.t('ov_rating'),
              value: rating == null ? '—' : '${rating.toStringAsFixed(1)} / 5',
              detail: rating == null ? null : '(${tickets['rating_count']})',
              alert: rating != null && rating < 3,
            ),
            _Metric(label: '${s.t('complaints')} · ${s.t('ov_overdue')}', value: '${n('complaints', 'overdue')}', alert: n('complaints', 'overdue') > 0),
          ],
        ),
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('ov_website'),
          icon: Icons.insights_rounded,
          children: [
            _Metric(label: s.t('ov_visits_today'), value: '${n('visits', 'today')}'),
            _Metric(label: s.t('ov_visits_week'), value: '${n('visits', 'week')}'),
            _Metric(label: s.t('ov_active_users'), value: '${n('accounts', 'active')}'),
            _Metric(label: s.t('pending_users'), value: '${n('accounts', 'pending')}', alert: n('accounts', 'pending') > 0),
            _Metric(label: '${s.t('job_applications')} · ${s.t('ov_month_apps')}', value: '${n('careers', 'month')}'),
          ],
        ),
        if (announcements.isNotEmpty) ...[
          const SizedBox(height: 12),
          FieldGroup(
            title: s.t('ov_latest_announcements'),
            icon: Icons.campaign_outlined,
            children: [
              for (final a in announcements)
                InkWell(
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => AnnouncementDetailScreen(id: a['id'] as int)))
                      .then((_) => reload()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: (a['recipients_count'] as num? ?? 0) == 0 ? 0 : (a['read_count'] as num) / (a['recipients_count'] as num),
                            minHeight: 6,
                            color: Tone.success,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.t('read_by').replaceAll('{r}', '${a['read_count']}').replaceAll('{t}', '${a['recipients_count']}'),
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        ..._links(context, data, reload),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.detail, this.alert = false});

  final String label;
  final String value;
  final String? detail;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant))),
          if (detail != null) Text('$detail  ', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          Text(value, textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w700, color: alert ? Tone.danger : scheme.onSurface)),
        ],
      ),
    );
  }
}

/// Accounts that signed up on the website and wait for activation.
class PendingUsersScreen extends StatelessWidget {
  const PendingUsersScreen({super.key});

  Future<void> _activate(BuildContext context, Map<String, dynamic> user, VoidCallback reload) async {
    final s = S.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.t('activate_confirm').replaceAll('{name}', user['name']?.toString() ?? '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('activate'))),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      await api.post('/users/${user['id']}/activate');
      if (context.mounted) toast(context, s.t('activated'));
      reload();
    } catch (e) {
      if (context.mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('pending_users'))),
      body: Loader(
        load: () async => Map<String, dynamic>.from(await api.get('/users/pending') as Map),
        builder: (context, body, reload) {
          final users = (body['data'] as List).map((u) => Map<String, dynamic>.from(u as Map)).toList();
          if (users.isEmpty) return const EmptyState(icon: Icons.how_to_reg_outlined);
          return RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: users.length,
              itemBuilder: (context, i) {
                final user = users[i];
                final roles = (user['roles'] as List? ?? []).join('، ');
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Avatar(name: user['name']?.toString() ?? '', size: 42),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(user['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(relativeDate(context, user['created_at']), style: const TextStyle(fontSize: 12)),
                              ]),
                            ),
                            if (roles.isNotEmpty) Pill(roles),
                          ]),
                          const SizedBox(height: 8),
                          InfoRow(s.t('department'), user['department'], icon: Icons.account_tree_outlined),
                          InfoRow(s.t('email'), user['email'], icon: Icons.alternate_email),
                          InfoRow(s.t('phone'), user['phone'], icon: Icons.phone_outlined),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () => _activate(context, user, reload),
                            icon: const Icon(Icons.how_to_reg_outlined),
                            label: Text(s.t('activate')),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

Color applicationColor(String? status) => switch (status) {
      'applied' => Tone.info,
      'under_review' || 'shortlisted' => Tone.warning,
      'interview' => const Color(0xFF7C4DFF),
      'accepted' => Tone.success,
      'rejected' => Tone.danger,
      _ => Tone.neutral,
    };

class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  String _status = 'applied';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    const statuses = ['applied', 'under_review', 'shortlisted', 'interview', 'accepted', 'rejected'];

    return Scaffold(
      appBar: AppBar(title: Text(s.t('job_applications'))),
      body: Column(
        children: [
          FilterBar(
            segments: {for (final st in statuses) st: s.t('app_$st')},
            selected: _status,
            onChanged: (value) => setState(() => _status = value),
          ),
          SearchField(onChanged: (value) => setState(() => _search = value)),
          Expanded(
            child: PagedList(
              path: '/careers/applications',
              query: {'status': _status, if (_search.isNotEmpty) 'search': _search},
              emptyIcon: Icons.work_outline_rounded,
              itemBuilder: (context, app, refresh) => ItemCard(
                icon: Icons.person_outline_rounded,
                title: app['name']?.toString() ?? '',
                subtitle: [app['vacancy'], app['specialty']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                trailing: relativeDate(context, app['created_at']),
                unread: app['is_new'] == true,
                chips: [
                  Pill(s.t('app_${app['status']}'), color: applicationColor(app['status']?.toString())),
                  if (app['degree'] != null) Pill(app['degree'].toString()),
                ],
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ApplicationDetailScreen(id: app['id'] as int)));
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

class ApplicationDetailScreen extends StatelessWidget {
  const ApplicationDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('job_applications'))),
      body: Loader(
        load: () async {
          final body = await api.get('/careers/applications/$id');
          return Map<String, dynamic>.from(body['data'] as Map);
        },
        builder: (context, app, reload) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            DetailHeader(
              pills: [
                Pill(app['tracking_code']?.toString() ?? ''),
                Pill(s.t('app_${app['status']}'), color: applicationColor(app['status']?.toString())),
              ],
              title: app['name']?.toString(),
              body: app['vacancy']?.toString(),
              meta: shortDate(app['created_at']),
            ),
            const SizedBox(height: 12),
            FieldGroup(
              title: s.t('qualification'),
              icon: Icons.school_outlined,
              children: [
                InfoRow(s.t('qualification'), [app['degree'], app['academic_title']].where((v) => v != null).join(' · '), icon: Icons.workspace_premium_outlined),
                InfoRow(s.t('specialty'), [app['specialty'], app['specific_specialty']].where((v) => v != null).join(' · '), icon: Icons.menu_book_outlined),
                InfoRow(s.t('university'), [app['university'], app['country']].where((v) => v != null).join(' · '), icon: Icons.account_balance_outlined),
              ],
            ),
            const SizedBox(height: 12),
            FieldGroup(
              title: s.t('contact_details'),
              icon: Icons.contact_mail_outlined,
              children: [
                InfoRow(s.t('phone'), app['phone'], icon: Icons.phone_outlined),
                InfoRow(s.t('email'), app['email'], icon: Icons.alternate_email),
                InfoRow(s.t('interview_date'), app['interview_date'], icon: Icons.event_outlined),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WebPageScreen(path: app['web_path'].toString(), title: app['name']?.toString() ?? ''),
              )),
              icon: const Icon(Icons.open_in_browser_rounded),
              label: Text(s.t('open_on_website')),
            ),
          ],
        ),
      ),
    );
  }
}
