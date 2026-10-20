import 'package:flutter/material.dart';

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
      subtitle: '${ticket['ticket_no']}${admin ? ' · ${ticket['requester_name']}' : ''}',
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

/// IT team desk.
class AdminTicketsTab extends StatefulWidget {
  const AdminTicketsTab({super.key});

  @override
  State<AdminTicketsTab> createState() => _AdminTicketsTabState();
}

class _AdminTicketsTabState extends State<AdminTicketsTab> {
  String _tab = 'attention';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Column(
      children: [
        FilterBar(
          segments: {'attention': s.t('attention'), 'active': s.t('active'), 'archived': s.t('archived')},
          selected: _tab,
          onChanged: (value) => setState(() => _tab = value),
        ),
        SearchField(onChanged: (value) => setState(() => _search = value)),
        Expanded(
          child: PagedList(
            path: '/tickets',
            query: {'tab': _tab, if (_search.isNotEmpty) 'search': _search},
            emptyIcon: Icons.confirmation_number_outlined,
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
        Pill(ticket['ticket_no']?.toString() ?? ''),
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _TicketHeader(ticket: ticket),
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
        _TicketAttachments(ticket: ticket),
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('requester'),
          icon: Icons.person_outline_rounded,
          children: [
            InfoRow(s.t('name'), ticket['requester_name'], icon: Icons.badge_outlined),
            InfoRow(s.t('department'), ticket['department_name'], icon: Icons.account_tree_outlined),
            InfoRow(s.t('email'), ticket['requester_email'], icon: Icons.alternate_email),
            InfoRow(s.t('phone'), ticket['requester_phone'], icon: Icons.phone_outlined),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(child: InfoRow(s.t('assignee'), ticket['assignee'] ?? '—', icon: Icons.engineering_outlined)),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: _busy ? null : () => _run(() => api.post('/tickets/$id/assign'), 'saved'),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: Text(s.t('assign_me')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('status'),
          icon: Icons.flag_outlined,
          children: [
            ColumnsWrap(
              columns: 2,
              spacing: 8,
              children: [
                for (final status in const ['open', 'in_progress', 'resolved', 'closed'])
                  ChoiceTile(
                    label: s.t(status),
                    color: statusColor(status),
                    selected: _status == status,
                    onTap: () => setState(() => _status = status),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: s.t('it_notes'), alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => api.patch('/tickets/$id', {'status': _status, 'it_notes': _notes.text}), 'saved'),
              child: Text(s.t('save')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('reply'),
          icon: Icons.reply_rounded,
          children: [
            TextField(
              controller: _reply,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(hintText: s.t('reply_hint')),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      if (_reply.text.trim().length < 5) return;
                      _run(() => api.post('/tickets/$id/reply', {'message': _reply.text.trim()}), 'reply_sent');
                    },
              icon: const Icon(Icons.send_rounded),
              label: Text(s.t('send_reply')),
            ),
          ],
        ),
      ],
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
                      onTap: file['is_image'] == true ? () => _open(context, file['url'].toString()) : null,
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
