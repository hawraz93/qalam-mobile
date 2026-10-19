import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

class ComplaintsTab extends StatefulWidget {
  const ComplaintsTab({super.key});

  @override
  State<ComplaintsTab> createState() => _ComplaintsTabState();
}

class _ComplaintsTabState extends State<ComplaintsTab> {
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
            path: '/complaints',
            query: {'tab': _tab, if (_search.isNotEmpty) 'search': _search},
            emptyIcon: Icons.campaign_outlined,
            itemBuilder: (context, complaint, refresh) {
              final unread = complaint['is_read'] != true;
              final resolved = complaint['is_resolved'] == true;
              return ItemCard(
                icon: unread ? Icons.mark_email_unread_outlined : Icons.campaign_outlined,
                title: complaint['excerpt']?.toString() ?? '',
                subtitle: '${complaint['reference']} · ${complaint['name'] ?? s.t('anonymous')}',
                trailing: relativeDate(context, complaint['created_at']),
                unread: unread,
                chips: [
                  Pill(s.t(complaint['priority']?.toString() ?? ''), color: priorityColor(complaint['priority']?.toString())),
                  if (resolved) Pill(s.t('resolved'), color: statusColor('resolved'), icon: Icons.check),
                ],
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ComplaintDetailScreen(id: complaint['id'] as int),
                  ));
                  refresh();
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class ComplaintDetailScreen extends StatelessWidget {
  const ComplaintDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).t('complaints'))),
      body: Loader(
        load: () async {
          final body = await api.get('/complaints/$id');
          return Map<String, dynamic>.from(body['data'] as Map);
        },
        builder: (context, complaint, reload) => _ComplaintBody(complaint: complaint, reload: reload),
      ),
    );
  }
}

class _ComplaintBody extends StatefulWidget {
  const _ComplaintBody({required this.complaint, required this.reload});

  final Map<String, dynamic> complaint;
  final VoidCallback reload;

  @override
  State<_ComplaintBody> createState() => _ComplaintBodyState();
}

class _ComplaintBodyState extends State<_ComplaintBody> {
  late final _notes = TextEditingController(text: widget.complaint['admin_notes']?.toString() ?? '');
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
    final scheme = Theme.of(context).colorScheme;
    final complaint = widget.complaint;
    final id = complaint['id'];
    final resolved = complaint['is_resolved'] == true;
    final canReply = complaint['can_reply_by_email'] == true;
    final evidence = (complaint['evidence'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        DetailHeader(
          pills: [
            Pill(complaint['reference']?.toString() ?? ''),
            Pill(s.t(complaint['priority']?.toString() ?? ''), color: priorityColor(complaint['priority']?.toString())),
            Pill(s.t(resolved ? 'resolved' : 'open'), color: statusColor(resolved ? 'resolved' : 'open')),
          ],
          body: complaint['description']?.toString(),
          meta: shortDate(complaint['created_at']),
        ),
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('requester'),
          icon: Icons.person_outline_rounded,
          children: [
            InfoRow(s.t('name'), complaint['name'] ?? s.t('anonymous'), icon: Icons.badge_outlined),
            InfoRow(s.t('phone'), complaint['phone'], icon: Icons.phone_outlined),
            InfoRow(s.t('email'), complaint['email'], icon: Icons.alternate_email),
          ],
        ),
        if (evidence.isNotEmpty) ...[
          const SizedBox(height: 12),
          FieldGroup(
            title: s.t('attachments'),
            icon: Icons.attach_file_rounded,
            children: [
              for (final file in evidence)
                file['is_image'] == true
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            file['url'].toString(),
                            headers: api.authHeaders,
                            errorBuilder: (_, __, ___) => Text(file['filename'].toString()),
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          Icon(Icons.description_outlined, size: 18, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(child: Text(file['filename'].toString(), style: const TextStyle(fontSize: 13))),
                        ]),
                      ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('follow_up'),
          icon: Icons.fact_check_outlined,
          children: [
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(labelText: s.t('admin_notes'), alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : () => _run(() => api.patch('/complaints/$id', {'admin_notes': _notes.text}), 'saved'),
              child: Text(s.t('save')),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : () => _run(() => api.patch('/complaints/$id', {'is_resolved': !resolved}), 'saved'),
              icon: Icon(resolved ? Icons.replay_rounded : Icons.check_rounded),
              label: Text(s.t(resolved ? 'reopen' : 'resolve')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FieldGroup(
          title: s.t('reply'),
          icon: Icons.reply_rounded,
          children: [
            if (!canReply)
              Text(s.t('no_email'), style: TextStyle(color: scheme.onSurfaceVariant))
            else ...[
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
                        _run(() => api.post('/complaints/$id/reply', {'message': _reply.text.trim()}), 'reply_sent');
                      },
                icon: const Icon(Icons.send_rounded),
                label: Text(s.t('send_reply')),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
