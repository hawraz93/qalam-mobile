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
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              DetailHeader(
                pills: [
                  if ((contact['subject_display'] ?? '').toString().isNotEmpty) Pill(contact['subject_display'].toString()),
                  if (replied) Pill(s.t('mark_replied'), color: Tone.success, icon: Icons.done_all),
                ],
                title: contact['name']?.toString(),
                body: contact['message']?.toString(),
                meta: shortDate(contact['created_at']),
              ),
              const SizedBox(height: 12),
              FieldGroup(
                title: s.t('contact_details'),
                icon: Icons.contact_mail_outlined,
                children: [
                  InfoRow(s.t('email'), contact['email'], icon: Icons.alternate_email),
                  InfoRow(s.t('phone'), contact['phone'], icon: Icons.phone_outlined),
                ],
              ),
              if (!replied) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
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
            ],
          );
        },
      ),
    );
  }
}
