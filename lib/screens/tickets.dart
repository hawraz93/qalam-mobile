import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';
import 'ticket_form.dart';

Color _statusColor(String? status) {
  switch (status) {
    case 'open':
      return Colors.red.shade700;
    case 'in_progress':
      return Colors.orange.shade800;
    case 'resolved':
      return Colors.green.shade700;
    default:
      return Colors.grey.shade600;
  }
}

class _TicketTile extends StatelessWidget {
  const _TicketTile({required this.ticket, required this.admin, required this.onChanged});

  final Map<String, dynamic> ticket;
  final bool admin;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final attention = admin && ticket['needs_attention'] == true;

    return ListTile(
      leading: Icon(
        attention ? Icons.mark_email_unread : Icons.confirmation_number_outlined,
        color: attention ? brandColor : Colors.grey,
      ),
      title: Text(
        ticket['title']?.toString() ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: attention ? FontWeight.w800 : FontWeight.w500),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Pill(s.t(ticket['status']?.toString() ?? ''), color: _statusColor(ticket['status']?.toString())),
            Pill(s.t(ticket['priority']?.toString() ?? ''), color: priorityColor(ticket['priority']?.toString())),
            Text(
              '${ticket['ticket_no']} · ${admin ? '${ticket['requester_name']} · ' : ''}${shortDate(ticket['created_at'])}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PagedList(
          key: _list,
          path: '/my/tickets',
          itemBuilder: (context, ticket, refresh) => _TicketTile(ticket: ticket, admin: false, onChanged: refresh),
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

/// IT team desk.
class AdminTicketsTab extends StatefulWidget {
  const AdminTicketsTab({super.key});

  @override
  State<AdminTicketsTab> createState() => _AdminTicketsTabState();
}

class _AdminTicketsTabState extends State<AdminTicketsTab> {
  String _tab = 'attention';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'attention', label: Text(s.t('attention'))),
              ButtonSegment(value: 'active', label: Text(s.t('active'))),
              ButtonSegment(value: 'archived', label: Text(s.t('archived'))),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => setState(() => _tab = selection.first),
          ),
        ),
        Expanded(
          child: PagedList(
            path: '/tickets',
            query: {'tab': _tab},
            itemBuilder: (context, ticket, refresh) => _TicketTile(ticket: ticket, admin: true, onChanged: refresh),
          ),
        ),
      ],
    );
  }
}

class TicketDetailScreen extends StatelessWidget {
  const TicketDetailScreen({super.key, required this.id, required this.admin});

  final int id;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).t(admin ? 'tickets' : 'my_tickets'))),
      body: Loader(
        load: () async {
          final body = await api.get(admin ? '/tickets/$id' : '/my/tickets/$id');
          return Map<String, dynamic>.from(body['data'] as Map);
        },
        builder: (context, ticket, reload) =>
            admin ? _AdminTicketBody(ticket: ticket, reload: reload) : _MyTicketBody(ticket: ticket),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(ticket['title']?.toString() ?? '', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          Pill(ticket['ticket_no']?.toString() ?? ''),
          Pill(s.t(ticket['status']?.toString() ?? ''), color: _statusColor(ticket['status']?.toString())),
          Pill(s.t(ticket['priority']?.toString() ?? ''), color: priorityColor(ticket['priority']?.toString())),
        ]),
        const SizedBox(height: 12),
        SelectableText(ticket['description']?.toString() ?? '', style: const TextStyle(fontSize: 15, height: 1.6)),
        const Divider(height: 32),
      ],
    );
  }
}

class _MyTicketBody extends StatelessWidget {
  const _MyTicketBody({required this.ticket});

  final Map<String, dynamic> ticket;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final updates = (ticket['updates'] as List? ?? []).map((u) => Map<String, dynamic>.from(u as Map)).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TicketHeader(ticket: ticket),
        InfoRow(s.t('assignee'), ticket['assignee']),
        InfoRow(s.t('it_notes'), ticket['it_notes']),
        const SizedBox(height: 16),
        Text(s.t('updates'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (updates.isEmpty) Text(s.t('no_updates'), style: TextStyle(color: Colors.grey.shade600)),
        for (final update in updates)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(update['kind'] == 'reply' ? Icons.reply : Icons.sync, size: 16, color: brandColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(update['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  SelectableText((update['reply_message'] ?? update['body'] ?? '').toString(),
                      style: const TextStyle(height: 1.5)),
                  const SizedBox(height: 6),
                  Text(shortDate(update['created_at']), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminTicketBody extends StatefulWidget {
  const _AdminTicketBody({required this.ticket, required this.reload});

  final Map<String, dynamic> ticket;
  final VoidCallback reload;

  @override
  State<_AdminTicketBody> createState() => _AdminTicketBodyState();
}

class _AdminTicketBodyState extends State<_AdminTicketBody> {
  late String _status = widget.ticket['status']?.toString() ?? 'open';
  late final _notes = TextEditingController(text: widget.ticket['it_notes']?.toString() ?? '');
  final _reply = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    _reply.dispose();
    super.dispose();
  }

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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final ticket = widget.ticket;
    final id = ticket['id'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _TicketHeader(ticket: ticket),
        InfoRow(s.t('requester'), ticket['requester_name']),
        InfoRow(s.t('department'), ticket['department_name']),
        InfoRow(s.t('email'), ticket['requester_email']),
        InfoRow(s.t('phone'), ticket['requester_phone']),
        InfoRow(s.t('assignee'), ticket['assignee']),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _busy ? null : () => _run(() => api.post('/tickets/$id/assign'), 'saved'),
            icon: const Icon(Icons.person_add_alt),
            label: Text(s.t('assign_me')),
          ),
        ),
        const Divider(height: 32),
        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: InputDecoration(labelText: s.t('status'), border: const OutlineInputBorder()),
          items: [
            for (final status in const ['open', 'in_progress', 'resolved', 'closed'])
              DropdownMenuItem(value: status, child: Text(s.t(status))),
          ],
          onChanged: (value) => setState(() => _status = value ?? _status),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          minLines: 2,
          maxLines: 5,
          decoration: InputDecoration(labelText: s.t('it_notes'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                    () => api.patch('/tickets/$id', {'status': _status, 'it_notes': _notes.text}),
                    'saved',
                  ),
          child: Text(s.t('save')),
        ),
        const Divider(height: 32),
        TextField(
          controller: _reply,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
            labelText: s.t('reply'),
            hintText: s.t('reply_hint'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () {
                  if (_reply.text.trim().length < 5) return;
                  _run(() => api.post('/tickets/$id/reply', {'message': _reply.text.trim()}), 'reply_sent');
                },
          icon: const Icon(Icons.send),
          label: Text(s.t('send_reply')),
        ),
      ],
    );
  }
}
