import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'announcements.dart';
import 'directory.dart';
import 'inbox.dart' show NotificationCard;
import 'management.dart';
import 'portfolio.dart';
import 'teacher.dart';
import 'ticket_form.dart';
import 'web_page.dart';

/// Dashboard: who is signed in, what is waiting, shortcuts, latest notifications.
class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    required this.summary,
    required this.onRefresh,
    required this.onOpenTab,
  });

  /// Counts from /summary, owned by the home screen so the badges share them.
  final Map<String, dynamic> summary;
  final Future<void> Function() onRefresh;

  /// Switches the bottom navigation to a tab key ('inbox', 'work', 'account').
  final void Function(String key, {String? section}) onOpenTab;

  @override
  State<HomeTab> createState() => HomeTabState();
}

class HomeTabState extends State<HomeTab> {
  List<Map<String, dynamic>> _recent = [];
  bool _recentLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> refresh() async {
    await Future.wait([widget.onRefresh(), _loadRecent()]);
  }

  Future<void> _loadRecent() async {
    try {
      final body = await api.get('/notifications', {'per_page': '5'});
      if (!mounted) return;
      setState(() {
        _recent = (body['data'] as List).map((row) => Map<String, dynamic>.from(row as Map)).toList();
        _recentLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _recentLoading = false);
    }
  }

  String _greeting(S s) {
    final hour = DateTime.now().hour;
    if (hour < 12) return s.t('good_morning');
    if (hour < 17) return s.t('good_afternoon');
    return s.t('good_evening');
  }

  void _openWeb(BuildContext context, String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebPageScreen(path: path, title: title)));
  }

  Future<void> _newTicket(BuildContext context) async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const TicketFormScreen()));
    if (sent == true) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final user = api.user ?? {};
    final summary = widget.summary;
    final links = api.webLinks;
    final teacher = user['teacher'] as Map?;
    final completion = teacher?['completion'] as int?;

    int count(String key) => (summary[key] as int?) ?? 0;

    void push(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)).then((_) => refresh());
    final managementScreen = ManagementScreen(onOpenWork: (section) => widget.onOpenTab('work', section: section));
    final hasManagement = api.can('management') || api.can('users') || api.can('careers');

    final stats = <Widget>[
      StatCell(
        icon: Icons.notifications_active_outlined,
        label: s.t('unread'),
        value: count('unread_notifications'),
        color: brandColor,
        onTap: () => widget.onOpenTab('inbox'),
      ),
      StatCell(
        icon: Icons.campaign_outlined,
        label: s.t('announcements'),
        value: count('announcements'),
        color: const Color(0xFF7C4DFF),
        onTap: () => push(const AnnouncementsScreen()),
      ),
      StatCell(
        icon: Icons.confirmation_number_outlined,
        label: s.t('my_tickets'),
        value: count('my_open_tickets'),
        color: Tone.info,
        onTap: () => widget.onOpenTab('work', section: 'my_tickets'),
      ),
      if (api.can('it_tickets'))
        StatCell(
          icon: Icons.support_agent_rounded,
          label: s.t('tickets'),
          value: count('it_tickets'),
          color: Tone.warning,
          onTap: () => widget.onOpenTab('work', section: 'tickets'),
        ),
      if (api.can('complaints'))
        StatCell(
          icon: Icons.campaign_outlined,
          label: s.t('complaints'),
          value: count('complaints'),
          color: Tone.danger,
          onTap: () => widget.onOpenTab('work', section: 'complaints'),
        ),
      if (api.can('contacts'))
        StatCell(
          icon: Icons.mail_outline_rounded,
          label: s.t('contacts'),
          value: count('contacts'),
          color: Tone.success,
          onTap: () => widget.onOpenTab('work', section: 'contacts'),
        ),
      if (api.can('users'))
        StatCell(
          icon: Icons.person_add_alt_1_outlined,
          label: s.t('pending_users'),
          value: count('pending_users'),
          color: Tone.info,
          onTap: () => push(const PendingUsersScreen()),
        ),
      if (api.can('careers'))
        StatCell(
          icon: Icons.work_outline_rounded,
          label: s.t('job_applications'),
          value: count('new_applications'),
          color: Tone.neutral,
          onTap: () => push(const ApplicationsScreen()),
        ),
    ];
    final waiting = [
      'unread_notifications',
      'announcements',
      'my_open_tickets',
      if (api.can('it_tickets')) 'it_tickets',
      if (api.can('complaints')) 'complaints',
      if (api.can('contacts')) 'contacts',
      if (api.can('users')) 'pending_users',
      if (api.can('careers')) 'new_applications',
    ].fold(0, (sum, key) => sum + count(key));

    final actions = <Widget>[
      ActionTile(icon: Icons.add_comment_outlined, label: s.t('new_ticket'), onTap: () => _newTicket(context)),
      ActionTile(icon: Icons.campaign_outlined, label: s.t('announcements'), onTap: () => push(const AnnouncementsScreen())),
      ActionTile(icon: Icons.contact_phone_outlined, label: s.t('directory'), onTap: () => push(const DirectoryScreen())),
      if (hasManagement)
        ActionTile(icon: Icons.insights_rounded, label: s.t('management'), onTap: () => push(managementScreen)),
      if (api.isTeacher)
        ActionTile(
          icon: Icons.school_outlined,
          label: s.t('academic_profile'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const TeacherProfileScreen()))
              .then((_) => refresh()),
        ),
      for (final link in links.where((l) => const ['teacher_registration', 'dashboard', 'research'].contains(l['key'])))
        ActionTile(
          icon: switch (link['key']) {
            'dashboard' => Icons.space_dashboard_outlined,
            'research' => Icons.science_outlined,
            _ => Icons.school_outlined,
          },
          label: s.t(link['key'].toString()),
          onTap: link['key'] == 'research'
              ? () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const PortfolioListScreen(kind: PortfolioKind.research)))
                  .then((_) => refresh())
              : () => _openWeb(context, link['path'].toString(), s.t(link['key'].toString())),
        ),
    ];

    final subtitle =
        [teacher?['academic_title'], user['department']].where((v) => v != null && v.toString().isNotEmpty).join(' · ');

    return RefreshIndicator(
      onRefresh: refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Brand header; the summary card below overlaps its lower edge.
                Container(
                  decoration: BoxDecoration(
                    gradient: brandGradient(context),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
                  ),
                  padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 14, 20, 84),
                  child: Row(
                    children: [
                      Avatar(
                          name: user['name']?.toString() ?? '',
                          url: user['avatar']?.toString(),
                          size: 54,
                          onBrand: true),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_greeting(s),
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 13)),
                            const SizedBox(height: 1),
                            Text(
                              user['name']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, height: 1.3),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 12.5),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => widget.onOpenTab('inbox'),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                          fixedSize: const Size(46, 46),
                        ),
                        icon: Badge(
                          isLabelVisible: count('unread_notifications') > 0,
                          backgroundColor: Colors.white,
                          textColor: brandColor,
                          label: Text('${count('unread_notifications')}'),
                          child: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 104, 16, 0),
                  child: _SummaryCard(waiting: waiting, stats: stats),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SectionTitle(s.t('quick_actions')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    child: ColumnsWrap(columns: 4, children: actions),
                  ),
                ),
                if (completion != null && completion < 100) ...[
                  const SizedBox(height: 12),
                  _CompletionCard(
                    completion: completion,
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => const TeacherProfileScreen()))
                        .then((_) => refresh()),
                  ),
                ],
                SectionTitle(s.t('recent_notifications'),
                    action: s.t('see_all'), onAction: () => widget.onOpenTab('inbox')),
              ]),
            ),
          ),
          if (_recentLoading)
            const SliverToBoxAdapter(child: SizedBox(height: 280, child: SkeletonList(rows: 3)))
          else if (_recent.isEmpty)
            SliverToBoxAdapter(child: EmptyState(icon: Icons.notifications_none, text: s.t('no_recent')))
          else
            SliverList.builder(
              itemCount: _recent.length,
              itemBuilder: (context, index) => NotificationCard(item: _recent[index], onChanged: refresh),
            ),
          SliverToBoxAdapter(child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom)),
        ],
      ),
    );
  }
}

/// "Waiting for you": the total, then one cell per area in a three-column grid.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.waiting, required this.stats});

  final int waiting;
  final List<Widget> stats;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Theme.of(context).cardTheme.color,
      elevation: dark ? 0 : 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      waiting == 0 ? s.t('all_clear') : s.t('needs_attention'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (waiting > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(20)),
                      child: Text('$waiting',
                          style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ColumnsWrap(columns: 3, children: stats),
          ],
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.completion, required this.onTap});

  final int completion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: completion / 100,
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    ),
                    Center(
                        child: Text('$completion%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.t('profile_completion'), style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(s.t('profile_completion_hint'),
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: scheme.primary, textDirection: textDirectionFor(context)),
            ],
          ),
        ),
      ),
    );
  }
}
