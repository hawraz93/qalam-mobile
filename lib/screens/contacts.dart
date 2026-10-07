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
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Column(
      children: [
        FilterBar(
          segments: {'unread': s.t('unread'), 'all': s.t('all')},
          selected: _status,
          onChanged: (value) => setState(() => _status = value),
        ),
        SearchField(onChanged: (value) => setState(() => _search = value)),
        Expanded(
          child: PagedList(
            path: '/contacts',
            query: {'status': _status, if (_search.isNotEmpty) 'search': _search},
            emptyIcon: Icons.mail_outline,
            itemBuilder: (context, contact, refresh) {
              final unread = contact['is_read'] != true;
              return ItemCard(
                icon: unread ? Icons.mark_email_unread_outlined : Icons.mail_outline,
                title: contact['name']?.toString() ?? '',
                subtitle: contact['excerpt']?.toString(),
                trailing: relativeDate(context, contact['created_at']),
                unread: unread,
                chips: [
                  if ((contact['subject_display'] ?? '').toString().isNotEmpty) Pill(contact['subject_display'].toString()),
                ],
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
