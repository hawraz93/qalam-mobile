import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  String _status = 'unread';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'unread', label: Text(s.t('unread'))),
              ButtonSegment(value: 'all', label: Text(s.t('all'))),
            ],
            selected: {_status},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => setState(() => _status = selection.first),
          ),
        ),
        Expanded(
          child: PagedList(
            path: '/contacts',
            query: {'status': _status},
            itemBuilder: (context, contact, refresh) {
              final unread = contact['is_read'] != true;
              return ListTile(
                leading: Icon(
                  unread ? Icons.mark_email_unread : Icons.mail_outline,
                  color: unread ? brandColor : Colors.grey,
                ),
                title: Text(
                  contact['name']?.toString() ?? '',
                  style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500),
                ),
                subtitle: Text(
                  '${contact['excerpt']}\n${contact['subject_display'] ?? ''} · ${shortDate(contact['created_at'])}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ContactDetailScreen(id: contact['id'] as int),
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

class ContactDetailScreen extends StatelessWidget {
  const ContactDetailScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.t('contacts'))),
      body: Loader(
        load: () async {
          final body = await api.get('/contacts/$id');
          return Map<String, dynamic>.from(body['data'] as Map);
        },
        builder: (context, contact, reload) {
          final replied = contact['replied_at'] != null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(contact['name']?.toString() ?? '', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(spacing: 6, children: [
                Pill(contact['subject_display']?.toString() ?? ''),
                Pill(shortDate(contact['created_at'])),
                if (replied) Pill(s.t('mark_replied'), color: Colors.green.shade700),
              ]),
              const SizedBox(height: 12),
              InfoRow(s.t('email'), contact['email']),
              InfoRow(s.t('phone'), contact['phone']),
              const Divider(height: 32),
              SelectableText(contact['message']?.toString() ?? '', style: const TextStyle(fontSize: 15, height: 1.6)),
              const SizedBox(height: 24),
              if (!replied)
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await api.post('/contacts/$id/replied');
                      reload();
                    } catch (e) {
                      if (context.mounted) toast(context, errorText(context, e));
                    }
                  },
                  icon: const Icon(Icons.done_all),
                  label: Text(s.t('mark_replied')),
                ),
            ],
          );
        },
      ),
    );
  }
}
