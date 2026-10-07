import 'package:flutter/material.dart';

import '../api.dart';
import '../push.dart';
import '../strings.dart';
import '../widgets.dart';
import 'complaints.dart';
import 'contacts.dart';
import 'tickets.dart';

IconData categoryIcon(String? category) {
  switch (category) {
    case 'it_tickets':
      return Icons.confirmation_number_outlined;
    case 'ticket_updates':
      return Icons.reply;
    case 'complaints':
      return Icons.campaign_outlined;
    case 'contacts':
      return Icons.mail_outline;
    case 'careers':
      return Icons.work_outline;
    default:
      return Icons.notifications_none;
  }
}

/// Opens the screen a notification points at. Returns false when there is none
/// (or the user is not allowed to manage that area).
Future<bool> openTarget(BuildContext context, PushTarget target) async {
  final id = target.entityId;
  if (id == null) return false;

  Widget? screen;
  switch (target.category) {
    case 'it_tickets':
      if (api.can('it_tickets')) screen = TicketDetailScreen(id: id, admin: true);
      break;
    case 'ticket_updates':
      screen = TicketDetailScreen(id: id, admin: false);
      break;
    case 'complaints':
      if (api.can('complaints')) screen = ComplaintDetailScreen(id: id);
      break;
    case 'contacts':
      if (api.can('contacts')) screen = ContactDetailScreen(id: id);
      break;
  }

  if (screen == null) return false;
  final destination = screen;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination));
  return true;
}

/// One notification row; marks it read and opens what it points at. Shared by the inbox and the home screen.
class NotificationCard extends StatelessWidget {
  const NotificationCard({super.key, required this.item, required this.onChanged});

  final Map<String, dynamic> item;
  final VoidCallback onChanged;

  Future<void> _open(BuildContext context) async {
    if (item['read_at'] == null) {
      try {
        await api.post('/notifications/${item['id']}/read');
      } catch (_) {
        // Opening the item matters more than the read flag
      }
    }
    if (!context.mounted) return;

    final opened = await openTarget(
      context,
      PushTarget(item['category']?.toString() ?? '', item['entity_id'] as int?),
    );

    if (!opened && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item['title']?.toString() ?? ''),
          content: SelectableText(item['body']?.toString() ?? ''),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(S.of(context).t('close'))),
          ],
        ),
      );
    }

    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final unread = item['read_at'] == null;
    return ItemCard(
      icon: categoryIcon(item['category']?.toString()),
      title: item['title']?.toString() ?? '',
      subtitle: item['body']?.toString(),
      trailing: relativeDate(context, item['created_at']),
      unread: unread,
      onTap: () => _open(context),
    );
  }
}

class InboxTab extends StatefulWidget {
  const InboxTab({super.key, required this.onChanged});

  /// Lets the home screen refresh its unread badge.
  final VoidCallback onChanged;

  @override
  State<InboxTab> createState() => InboxTabState();
}

class InboxTabState extends State<InboxTab> {
  final _list = GlobalKey<PagedListState>();
  String _filter = 'all';
  String _search = '';

  void refresh() => _list.currentState?.refresh();

  Future<void> _markAll() async {
    try {
      await api.post('/notifications/read-all');
      refresh();
      widget.onChanged();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilterBar(
                segments: {'all': s.t('all'), 'unread': s.t('unread')},
                selected: _filter,
                onChanged: (value) => setState(() => _filter = value),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10, top: 6),
              child: IconButton.filledTonal(
                tooltip: s.t('mark_all'),
                onPressed: _markAll,
                icon: const Icon(Icons.done_all),
              ),
            ),
          ],
        ),
        SearchField(onChanged: (value) => setState(() => _search = value)),
        Expanded(
          child: PagedList(
            key: _list,
            path: '/notifications',
            query: {if (_filter == 'unread') 'unread': '1', if (_search.isNotEmpty) 'search': _search},
            emptyIcon: Icons.notifications_none,
            itemBuilder: (context, item, refreshList) => NotificationCard(
              item: item,
              onChanged: () {
                refreshList();
                widget.onChanged();
              },
            ),
          ),
        ),
      ],
    );
  }
}
