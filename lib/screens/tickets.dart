import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';
import 'ticket_form.dart';

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket, required this.admin, required this.onChanged});

  final Map<String, dynamic> ticket;
  final bool admin;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final attention = admin && ticket['needs_attention'] == true;
    final status = ticket['status']?.toString();

    return ItemCard(
      icon: attention ? Icons.mark_email_unread_outlined : Icons.confirmation_number_outlined,
      title: ticket['title']?.toString() ?? '',
      subtitle: '${ltr(ticket['ticket_no'])}${admin ? ' · ${ticket['requester_name']}' : ''}',
      trailing: relativeDate(context, ticket['created_at']),
      unread: attention || (!admin && status == 'open'),
      accent: statusColor(status),
      chips: [
        Pill(s.t(status ?? ''), color: statusColor(status)),
        Pill(s.t(ticket['priority']?.toString() ?? ''), color: priorityColor(ticket['priority']?.toString())),
      ],
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TicketDetailScreen(id: ticket['id'] as int, admin: admin),
        ));
        onChanged();
      },
    );
  }
}

/// Tickets the signed-in teacher / employee opened, with a button to open a new one.
class MyTicketsTab extends StatefulWidget {
  const MyTicketsTab({super.key});

  @override
  State<MyTicketsTab> createState() => _MyTicketsTabState();
}

class _MyTicketsTabState extends State<MyTicketsTab> {
  final _list = GlobalKey<PagedListState>();
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            SearchField(onChanged: (value) => setState(() => _search = value)),
            Expanded(
              child: PagedList(
                key: _list,
                path: '/my/tickets',
                query: {if (_search.isNotEmpty) 'search': _search},
                emptyIcon: Icons.confirmation_number_outlined,
                itemBuilder: (context, ticket, refresh) => _TicketTile(ticket: ticket, admin: false, onChanged: refresh),
              ),
            ),
          ],
        ),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'new-ticket',
            onPressed: () async {
              final sent = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const TicketFormScreen()),
              );
              if (sent == true) _list.currentState?.refresh();
            },
            icon: const Icon(Icons.add),
            label: Text(S.of(context).t('new_ticket')),
          ),
        ),
      ],
    );
  }
}

/// "2026-00116" / "2026-11-11" kept left-to-right inside Arabic / Kurdish text.
String ltr(Object? text) => '\u2066${text ?? ''}\u2069';

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Statuses each desk tab holds; the status filter only offers these.
const _tabStatuses = {
  'active': ['open', 'in_progress'],
  'archived': ['resolved', 'closed'],
  'all': ['open', 'in_progress', 'resolved', 'closed'],
};
const _priorities = ['low', 'medium', 'high', 'urgent'];
const _categories = ['hardware', 'software', 'network', 'account', 'printer', 'other'];

/// The desk's narrowing filters (the tab and search sit outside).
class _TicketFilters {
  const _TicketFilters({this.status = '', this.priority = '', this.category = '', this.from, this.to});

  final String status;
  final String priority;
  final String category;
  final DateTime? from;
  final DateTime? to;

  int get count => [status.isNotEmpty, priority.isNotEmpty, category.isNotEmpty, from != null, to != null].where((on) => on).length;

  Map<String, String> get query => {
        if (status.isNotEmpty) 'status': status,
        if (priority.isNotEmpty) 'priority': priority,
        if (category.isNotEmpty) 'category': category,
        if (from != null) 'minDate': _ymd(from!),
        if (to != null) 'maxDate': _ymd(to!),
      };

  /// Drops a status the new tab cannot have (the server would ignore it anyway).
  _TicketFilters forTab(String tab) =>
      (_tabStatuses[tab] ?? const []).contains(status) ? this : _TicketFilters(priority: priority, category: category, from: from, to: to);

  _TicketFilters without(String key) => _TicketFilters(
        status: key == 'status' ? '' : status,
        priority: key == 'priority' ? '' : priority,
        category: key == 'category' ? '' : category,
        from: key == 'from' ? null : from,
        to: key == 'to' ? null : to,
      );
}

/// IT team desk: active / resolved & closed / all, with search, filters and printing.
class AdminTicketsTab extends StatefulWidget {
  const AdminTicketsTab({super.key});

  @override
  State<AdminTicketsTab> createState() => _AdminTicketsTabState();
}

class _AdminTicketsTabState extends State<AdminTicketsTab> {
  String _tab = 'active';
  String _search = '';
  _TicketFilters _filters = const _TicketFilters();
  Map<String, int>? _counts;
  String? _printUrl;

  void _loaded(Map<String, dynamic> body) {
    final counts = body['counts'];
    setState(() {
      if (counts is Map) {
        _counts = {for (final e in counts.entries) e.key.toString(): (e.value as num?)?.toInt() ?? 0};
      }
      _printUrl = body['print_url']?.toString();
    });
  }

  Future<void> _openFilters() async {
    final picked = await showModalBottomSheet<_TicketFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _FiltersSheet(tab: _tab, initial: _filters),
    );
    if (picked != null) setState(() => _filters = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final f = _filters;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        FilterBar(
          segments: {
            'active': s.t('active'),
            'archived': s.t('tickets_resolved_closed'),
            'all': s.t('all'),
            'attention': s.t('attention'),
          },
          counts: _counts,
          selected: _tab,
          onChanged: (value) => setState(() {
            _tab = value;
            _filters = _filters.forTab(value);
          }),
        ),
        Row(
          children: [
            Expanded(child: SearchField(onChanged: (value) => setState(() => _search = value))),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: IconButton(
                tooltip: s.t('filters'),
                onPressed: _openFilters,
                icon: Badge(
                  isLabelVisible: f.count > 0,
                  label: Text('${f.count}'),
                  child: Icon(Icons.tune_rounded, color: f.count > 0 ? scheme.primary : null),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4, end: 8),
              child: IconButton(
                tooltip: s.t('print_list'),
                onPressed: _printUrl == null ? null : () => openExternal(context, _printUrl!),
                icon: const Icon(Icons.print_outlined),
              ),
            ),
          ],
        ),
        if (f.count > 0)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              children: [
                for (final chip in [
                  if (f.status.isNotEmpty) ('status', s.t(f.status)),
                  if (f.priority.isNotEmpty) ('priority', s.t(f.priority)),
                  if (f.category.isNotEmpty) ('category', s.t('cat_${f.category}')),
                  if (f.from != null) ('from', '${s.t('from_date')} ${ltr(_ymd(f.from!))}'),
                  if (f.to != null) ('to', '${s.t('to_date')} ${ltr(_ymd(f.to!))}'),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: InputChip(
                      label: Text(chip.$2, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      onDeleted: () => setState(() => _filters = _filters.without(chip.$1)),
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => setState(() => _filters = const _TicketFilters()),
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: Text(s.t('clear_filters')),
                ),
              ],
            ),
          ),
        Expanded(
          child: PagedList(
            path: '/tickets',
            query: {'tab': _tab, if (_search.isNotEmpty) 'search': _search, ...f.query},
            emptyIcon: Icons.confirmation_number_outlined,
            onLoaded: _loaded,
            itemBuilder: (context, ticket, refresh) => _TicketTile(ticket: ticket, admin: true, onChanged: refresh),
          ),
        ),
      ],
    );
  }
}

/// Status (for the current tab), priority, category and a date range.
class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.tab, required this.initial});

  final String tab;
  final _TicketFilters initial;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String _status = widget.initial.status;
  late String _priority = widget.initial.priority;
  late String _category = widget.initial.category;
  late DateTime? _from = widget.initial.from;
  late DateTime? _to = widget.initial.to;

  Future<DateTime?> _pickDate(DateTime? current) => showDatePicker(
        context: context,
        initialDate: current ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 1)),
      );

  Widget _choices(String title, String allLabel, List<String> values, String selected, String Function(String) label, ValueChanged<String> onPick) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(label: Text(allLabel), selected: selected.isEmpty, onSelected: (_) => onPick('')),
              for (final value in values)
                ChoiceChip(label: Text(label(value)), selected: selected == value, onSelected: (_) => onPick(value)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final statuses = _tabStatuses[widget.tab] ?? const <String>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.t('filters'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (statuses.isNotEmpty)
            _choices(s.t('status'), s.t('all_statuses'), statuses, _status, s.t, (v) => setState(() => _status = v)),
          _choices(s.t('priority'), s.t('all_priorities'), _priorities, _priority, s.t, (v) => setState(() => _priority = v)),
          _choices(s.t('category'), s.t('all_categories'), _categories, _category, (v) => s.t('cat_$v'), (v) => setState(() => _category = v)),
          Row(
            children: [
              Expanded(
                child: PickerField(
                  label: s.t('from_date'),
                  icon: Icons.event_outlined,
                  value: _from == null ? null : ltr(_ymd(_from!)),
                  onTap: () async {
                    final picked = await _pickDate(_from);
                    if (picked != null) setState(() => _from = picked);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PickerField(
                  label: s.t('to_date'),
                  icon: Icons.event_outlined,
                  value: _to == null ? null : ltr(_ymd(_to!)),
                  onTap: () async {
                    final picked = await _pickDate(_to);
                    if (picked != null) setState(() => _to = picked);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, const _TicketFilters()),
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: Text(s.t('clear_filters')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    // A reversed range is almost always a slip; swap it rather than showing nothing
                    var from = _from, to = _to;
                    if (from != null && to != null && from.isAfter(to)) (from, to) = (to, from);
                    Navigator.pop(context, _TicketFilters(status: _status, priority: _priority, category: _category, from: from, to: to));
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: Text(s.t('apply')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TicketDetailScreen extends StatefulWidget {
  const TicketDetailScreen({super.key, required this.id, required this.admin});

  final int id;
  final bool admin;

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  /// Signed link that prints this ticket (IT desk only).
  String? _printUrl;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final admin = widget.admin;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(admin ? 'tickets' : 'my_tickets')),
        actions: [
          if (_printUrl != null)
            IconButton(
              tooltip: s.t('print'),
              onPressed: () => openExternal(context, _printUrl!),
              icon: const Icon(Icons.print_outlined),
            ),
        ],
      ),
      body: Loader(
        load: () async {
          final body = await api.get(admin ? '/tickets/${widget.id}' : '/my/tickets/${widget.id}');
          final ticket = Map<String, dynamic>.from(body['data'] as Map);
          final printUrl = admin ? (ticket['print_url'] ?? body['print_url'])?.toString() : null;
          if (mounted && printUrl != _printUrl) setState(() => _printUrl = printUrl);
          return ticket;
        },
        builder: (context, ticket, reload) =>
            admin ? _AdminTicketBody(ticket: ticket, reload: reload) : _MyTicketBody(ticket: ticket, reload: reload),
      ),
    );
  }
}

class _TicketHeader extends StatelessWidget {
  const _TicketHeader({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return DetailHeader(
      pills: [
        Pill(ltr(ticket['ticket_no'])),
        Pill(s.t(ticket['status']?.toString() ?? ''), color: statusColor(ticket['status']?.toString())),
        Pill(s.t(ticket['priority']?.toString() ?? ''), color: priorityColor(ticket['priority']?.toString())),
      ],
      title: ticket['title']?.toString(),
      body: ticket['description']?.toString(),
      meta: shortDate(ticket['created_at']),
    );
  }
}

class _MyTicketBody extends StatelessWidget {
  const _MyTicketBody({required this.ticket, required this.reload});

  final Map<String, dynamic> ticket;
  final VoidCallback reload;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final updates = (ticket['updates'] as List? ?? []).map((u) => Map<String, dynamic>.from(u as Map)).toList();
    final hasInfo = [ticket['department_name'], ticket['assignee'], ticket['it_notes']]
        .any((v) => v != null && v.toString().isNotEmpty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _TicketHeader(ticket: ticket),
        if (ticket['can_rate'] == true) ...[
          const SizedBox(height: 12),
          _RatingCard(ticket: ticket, onSaved: reload),
        ],
        _TicketAttachments(ticket: ticket),
        if (hasInfo) ...[
          const SizedBox(height: 12),
          FieldGroup(
            title: s.t('it_team'),
            icon: Icons.support_agent_rounded,
            children: [
              InfoRow(s.t('department'), ticket['department_name'], icon: Icons.account_tree_outlined),
              InfoRow(s.t('assignee'), ticket['assignee'], icon: Icons.person_outline),
              InfoRow(s.t('it_notes'), ticket['it_notes'], icon: Icons.sticky_note_2_outlined),
            ],
          ),
        ],
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('updates'),
          icon: Icons.history_rounded,
          children: [
            if (updates.isEmpty)
              Text(s.t('no_updates'), style: TextStyle(color: scheme.onSurfaceVariant))
            else
              for (var i = 0; i < updates.length; i++)
                TimelineEntry(
                  icon: updates[i]['kind'] == 'reply' ? Icons.reply_rounded : Icons.sync_rounded,
                  color: updates[i]['kind'] == 'reply' ? scheme.primary : Tone.info,
                  title: updates[i]['title']?.toString() ?? '',
                  text: (updates[i]['reply_message'] ?? updates[i]['body'] ?? '').toString(),
                  date: relativeDate(context, updates[i]['created_at']),
                  last: i == updates.length - 1,
                ),
          ],
        ),
      ],
    );
  }
}

/// IT desk view of one ticket: what it is and who asked, then one obvious next step
/// for its state (take it → reply / resolve → reopen). Everything else (any status,
/// IT note) is under "More", so the screen stays short.
class _AdminTicketBody extends StatefulWidget {
  const _AdminTicketBody({required this.ticket, required this.reload});

  final Map<String, dynamic> ticket;
  final VoidCallback reload;

  @override
  State<_AdminTicketBody> createState() => _AdminTicketBodyState();
}

class _AdminTicketBodyState extends State<_AdminTicketBody> {
  bool _busy = false;

  int get _id => widget.ticket['id'] as int;
  String get _status => widget.ticket['status']?.toString() ?? 'open';
  String get _notes => widget.ticket['it_notes']?.toString() ?? '';

  Future<void> _run(Future<void> Function() action, String doneKey) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      toast(context, S.of(context).t(doneKey));
      widget.reload();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(String status, {String? notes}) =>
      api.patch('/tickets/$_id', {'status': status, 'it_notes': notes ?? _notes});

  /// Assign to me and start working on it, in one tap.
  void _take() => _run(() async {
        await api.post('/tickets/$_id/assign');
        await _setStatus('in_progress');
      }, 'ticket_taken');

  Future<void> _reply() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _ReplySheet(id: _id, status: _status, notes: _notes),
    );
    if (sent == true) {
      if (mounted) toast(context, S.of(context).t('reply_sent'));
      widget.reload();
    }
  }

  Future<void> _more() async {
    final s = S.of(context);
    final mine = widget.ticket['assignee'] != null && widget.ticket['assignee'] == api.user?['name'];
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.reply_rounded), title: Text(s.t('reply')), onTap: () => Navigator.pop(context, 'reply')),
            ListTile(leading: const Icon(Icons.sticky_note_2_outlined), title: Text(s.t('it_notes')), onTap: () => Navigator.pop(context, 'note')),
            if (!mine)
              ListTile(leading: const Icon(Icons.person_add_alt), title: Text(s.t('assign_me')), onTap: () => Navigator.pop(context, 'assign')),
            const Divider(height: 8),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 4),
              child: Align(alignment: AlignmentDirectional.centerStart, child: Text(s.t('change_status'), style: Theme.of(context).textTheme.labelLarge)),
            ),
            for (final status in const ['open', 'in_progress', 'resolved', 'closed'])
              ListTile(
                dense: true,
                leading: Icon(status == _status ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: statusColor(status)),
                title: Text(s.t(status)),
                onTap: () => Navigator.pop(context, 'status:$status'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'reply') return _reply();
    if (choice == 'assign') return _run(() => api.post('/tickets/$_id/assign'), 'saved');
    if (choice == 'note') return _editNote();
    final status = choice.substring('status:'.length);
    if (status != _status) _run(() => _setStatus(status), 'saved');
  }

  Future<void> _editNote() async {
    final s = S.of(context);
    final controller = TextEditingController(text: _notes);
    final save = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.t('it_notes'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(s.t('it_notes_hint'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(controller: controller, autofocus: true, minLines: 3, maxLines: 8),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('save'))),
          ],
        ),
      ),
    );
    final text = controller.text;
    controller.dispose();
    if (save == true) _run(() => _setStatus(_status, notes: text), 'saved');
  }

  Future<void> _launch(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      toast(context, S.of(context).t('cannot_open'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ticket = widget.ticket;
    final phone = ticket['requester_phone']?.toString() ?? '';
    final email = ticket['requester_email']?.toString() ?? '';
    final overdue = (ticket['overdue_minutes'] as num?)?.toInt();

    final actions = switch (_status) {
      'open' => [
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : _take,
              icon: const Icon(Icons.pan_tool_alt_outlined),
              label: Text(s.t('take_ticket')),
            ),
          ),
        ],
      'in_progress' => [
          Expanded(
            child: FilledButton.tonalIcon(onPressed: _busy ? null : _reply, icon: const Icon(Icons.reply_rounded), label: Text(s.t('reply'))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Tone.success),
              onPressed: _busy ? null : () => _run(() => _setStatus('resolved'), 'saved'),
              icon: const Icon(Icons.check_rounded),
              label: Text(s.t('mark_resolved')),
            ),
          ),
        ],
      _ => [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : () => _run(() => _setStatus('in_progress'), 'saved'),
              icon: const Icon(Icons.replay_rounded),
              label: Text(s.t('reopen')),
            ),
          ),
        ],
    };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              if (overdue != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: Tone.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.alarm_rounded, color: Tone.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(s.t('ticket_overdue_banner'), style: const TextStyle(color: Tone.danger, fontWeight: FontWeight.w600))),
                  ]),
                ),
              _TicketHeader(ticket: ticket),
              const SizedBox(height: 12),
              // Who asked, in one row, with call / email at hand
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                  child: Row(children: [
                    Avatar(name: ticket['requester_name']?.toString() ?? '', size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(ticket['requester_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                        if ((ticket['department_name'] ?? '').toString().isNotEmpty)
                          Text(ticket['department_name'].toString(),
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      ]),
                    ),
                    if (phone.isNotEmpty)
                      IconButton(
                        tooltip: s.t('call'),
                        onPressed: () => _launch(Uri(scheme: 'tel', path: phone)),
                        icon: const Icon(Icons.call_outlined, color: Tone.success),
                      ),
                    if (email.isNotEmpty)
                      IconButton(
                        tooltip: s.t('send_email'),
                        onPressed: () => _launch(Uri(scheme: 'mailto', path: email, query: 'subject=${Uri.encodeComponent(ticket['ticket_no']?.toString() ?? '')}')),
                        icon: Icon(Icons.mail_outline_rounded, color: scheme.primary),
                      ),
                  ]),
                ),
              ),
              // Only what has been filled in: assignee and IT note
              if (ticket['assignee'] != null || _notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                FieldGroup(
                  title: s.t('it_team'),
                  icon: Icons.support_agent_rounded,
                  children: [
                    InfoRow(s.t('assignee'), ticket['assignee'], icon: Icons.engineering_outlined),
                    InfoRow(s.t('it_notes'), _notes.isEmpty ? null : _notes, icon: Icons.sticky_note_2_outlined),
                  ],
                ),
              ],
              _TicketAttachments(ticket: ticket),
              if (ticket['rating'] != null) ...[
                const SizedBox(height: 12),
                FieldGroup(
                  title: s.t('requester_rating'),
                  icon: Icons.star_outline_rounded,
                  children: [
                    _Stars(value: (ticket['rating'] as num).toInt()),
                    if ((ticket['rating_comment'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(ticket['rating_comment'].toString(), style: const TextStyle(height: 1.5)),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        // The next step for this state, always in reach; the rest under "More"
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                ...actions,
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: s.t('more_actions'),
                  onPressed: _busy ? null : _more,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.more_horiz_rounded),
                ),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reply to the requester (email + app notification), optionally closing the matter.
class _ReplySheet extends StatefulWidget {
  const _ReplySheet({required this.id, required this.status, required this.notes});

  final int id;
  final String status;
  final String notes;

  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _text = TextEditingController();
  late bool _resolve = widget.status == 'in_progress';
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_text.text.trim().length < 5) {
      toast(context, S.of(context).t('required'));
      return;
    }
    setState(() => _busy = true);
    try {
      await api.post('/tickets/${widget.id}/reply', {'message': _text.text.trim()});
      if (_resolve) {
        await api.patch('/tickets/${widget.id}', {'status': 'resolved', 'it_notes': widget.notes});
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.t('reply'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            autofocus: true,
            minLines: 4,
            maxLines: 10,
            decoration: InputDecoration(hintText: s.t('reply_hint')),
          ),
          if (widget.status != 'resolved' && widget.status != 'closed')
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _resolve,
              onChanged: (v) => setState(() => _resolve = v ?? false),
              title: Text(s.t('resolve_after_reply')),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _send,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: Text(s.t('send_reply')),
          ),
        ],
      ),
    );
  }
}

/// Photos / PDFs sent with the ticket. The files are private, so images load with the token.
class _TicketAttachments extends StatelessWidget {
  const _TicketAttachments({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    final files = (ticket['attachments'] as List? ?? []).map((f) => Map<String, dynamic>.from(f as Map)).toList();
    if (files.isEmpty) return const SizedBox.shrink();
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FieldGroup(
        title: s.t('attachments'),
        icon: Icons.attach_file_rounded,
        children: [
          ColumnsWrap(
            columns: 3,
            spacing: 8,
            children: [
              for (final file in files)
                AspectRatio(
                  aspectRatio: 1,
                  child: Material(
                    color: scheme.surfaceContainerHighest,
                    clipBehavior: Clip.antiAlias,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      onTap: file['is_image'] == true
                          ? () => _open(context, file['url'].toString())
                          : file['open_url'] == null
                              ? null
                              : () => launchUrl(Uri.parse(file['open_url'].toString()), mode: LaunchMode.externalApplication),
                      child: file['is_image'] == true
                          ? Image.network(
                              file['url'].toString(),
                              headers: api.authHeaders,
                              fit: BoxFit.cover,
                              cacheWidth: 400,
                              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.picture_as_pdf_outlined, color: scheme.primary),
                                const SizedBox(height: 4),
                                const Text('PDF', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image.network(url, headers: api.authHeaders)),
        ),
      ),
    ));
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, this.onChanged, this.size = 30});

  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            GestureDetector(
              onTap: onChanged == null ? null : () => onChanged!(star),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                child: Icon(
                  star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: size,
                  color: star <= value ? const Color(0xFFF5A524) : Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown to the requester once IT resolved or closed the ticket; a saved rating can be changed.
class _RatingCard extends StatefulWidget {
  const _RatingCard({required this.ticket, required this.onSaved});

  final Map<String, dynamic> ticket;
  final VoidCallback onSaved;

  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  late int _rating = (widget.ticket['rating'] as num?)?.toInt() ?? 0;
  late final _comment = TextEditingController(text: widget.ticket['rating_comment']?.toString() ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_rating == 0) return;
    setState(() => _busy = true);
    try {
      await api.post('/my/tickets/${widget.ticket['id']}/rating', {
        'rating': _rating,
        if (_comment.text.trim().isNotEmpty) 'comment': _comment.text.trim(),
      });
      if (!mounted) return;
      toast(context, S.of(context).t('rating_saved'));
      widget.onSaved();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rated = widget.ticket['rating'] != null;
    return FieldGroup(
      title: s.t(rated ? 'your_rating' : 'rate_title'),
      hint: s.t('rate_hint'),
      icon: Icons.star_outline_rounded,
      children: [
        Center(child: _Stars(value: _rating, size: 38, onChanged: (value) => setState(() => _rating = value))),
        const SizedBox(height: 8),
        TextField(
          controller: _comment,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(hintText: s.t('rating_comment')),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy || _rating == 0 ? null : _save,
          icon: const Icon(Icons.send_rounded),
          label: Text(s.t('send_rating')),
        ),
      ],
    );
  }
}
