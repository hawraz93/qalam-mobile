import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'inbox.dart' show NotificationCard;
import 'portfolio.dart';
import 'teacher.dart';
import 'ticket_form.dart';
import 'web_page.dart';

/// Dashboard: who is signed in, what needs attention, quick actions, latest notifications.
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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final user = api.user ?? {};
    final summary = widget.summary;
    final links = api.webLinks;
    final scheme = Theme.of(context).colorScheme;

    int count(String key) => (summary[key] as int?) ?? 0;

    final stats = <Widget>[
      StatTile(
        icon: Icons.notifications_active_outlined,
        label: s.t('unread'),
        value: count('unread_notifications'),
        color: brandColor,
        onTap: () => widget.onOpenTab('inbox'),
      ),
      StatTile(
        icon: Icons.person_outline,
        label: s.t('my_tickets'),
        value: count('my_open_tickets'),
        color: const Color(0xFF1976D2),
        onTap: () => widget.onOpenTab('work', section: 'my_tickets'),
      ),
      if (api.can('it_tickets'))
        StatTile(
          icon: Icons.confirmation_number_outlined,
          label: s.t('tickets'),
          value: count('it_tickets'),
          color: const Color(0xFFEF6C00),
          onTap: () => widget.onOpenTab('work', section: 'tickets'),
        ),
      if (api.can('complaints'))
        StatTile(
          icon: Icons.campaign_outlined,
          label: s.t('complaints'),
          value: count('complaints'),
          color: const Color(0xFFD32F2F),
          onTap: () => widget.onOpenTab('work', section: 'complaints'),
        ),
      if (api.can('contacts'))
        StatTile(
          icon: Icons.mail_outline,
          label: s.t('contacts'),
          value: count('contacts'),
          color: const Color(0xFF00897B),
          onTap: () => widget.onOpenTab('work', section: 'contacts'),
        ),
    ];

    return RefreshIndicator(
      onRefresh: refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                gradient: brandGradient(context),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
              padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 16, 20, 28),
              child: Row(
                children: [
                  Avatar(name: user['name']?.toString() ?? '', url: user['avatar']?.toString(), size: 58, onBrand: true),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_greeting(s), style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                        Text(
                          user['name']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        if ((user['department'] ?? user['teacher']?['academic_title']) != null)
                          Text(
                            [user['teacher']?['academic_title'], user['department']]
                                .where((v) => v != null && v.toString().isNotEmpty)
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => widget.onOpenTab('inbox'),
                    style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.18)),
                    icon: Badge(
                      isLabelVisible: count('unread_notifications') > 0,
                      label: Text('${count('unread_notifications')}'),
                      child: const Icon(Icons.notifications_none, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: stats,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SectionTitle(s.t('quick_actions')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          QuickAction(
                            icon: Icons.add_comment_outlined,
                            label: s.t('new_ticket'),
                            onTap: () async {
                              final sent = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(builder: (_) => const TicketFormScreen()),
                              );
                              if (sent == true) refresh();
                            },
                          ),
                          if (api.isTeacher)
                            QuickAction(
                              icon: Icons.school_outlined,
                              label: s.t('academic_profile'),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherProfileScreen())).then((_) => refresh()),
                            ),
                          for (final link in links.where((l) => const ['teacher_registration', 'dashboard', 'research'].contains(l['key'])))
                            QuickAction(
                              icon: switch (link['key']) {
                                'dashboard' => Icons.space_dashboard_outlined,
                                'research' => Icons.science_outlined,
                                _ => Icons.school_outlined,
                              },
                              label: s.t(link['key'].toString()),
                              onTap: link['key'] == 'research'
                                  ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PortfolioListScreen(kind: PortfolioKind.research))).then((_) => refresh())
                                  : () => _openWeb(context, link['path'].toString(), s.t(link['key'].toString())),
                            ),
                          QuickAction(
                            icon: Icons.manage_accounts_outlined,
                            label: s.t('account'),
                            onTap: () => widget.onOpenTab('account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (api.isTeacher && (user['teacher']?['completion'] as int?) != null && (user['teacher']['completion'] as int) < 100) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherProfileScreen())).then((_) => refresh()),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 48,
                              height: 48,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CircularProgressIndicator(
                                    value: (user['teacher']['completion'] as int) / 100,
                                    strokeWidth: 5,
                                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                                  ),
                                  Center(
                                    child: Text('${user['teacher']['completion']}%',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.t('profile_completion'), style: const TextStyle(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(s.t('profile_completion_hint'),
                                      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: scheme.outline, textDirection: textDirectionFor(context)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                SectionTitle(s.t('recent_notifications'), action: s.t('see_all'), onAction: () => widget.onOpenTab('inbox')),
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
              itemBuilder: (context, index) => NotificationCard(
                item: _recent[index],
                onChanged: refresh,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
