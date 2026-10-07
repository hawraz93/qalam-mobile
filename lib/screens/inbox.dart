import 'package:flutter/material.dart';

import '../api.dart';
import '../push.dart';
import '../strings.dart';
import '../widgets.dart';
import 'complaints.dart';
import 'contacts.dart';
import 'tickets.dart';

IconData _categoryIcon(String? category) {
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

class InboxTab extends StatefulWidget {
  const InboxTab({super.key, required this.onChanged});

  /// Lets the home screen refresh its unread badge.
  final VoidCallback onChanged;

  @override
  State<InboxTab> createState() => InboxTabState();
}

class InboxTabState extends State<InboxTab> {
  final _list = GlobalKey<PagedListState>();

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

  Future<void> _open(Map<String, dynamic> item, VoidCallback refreshList) async {
    if (item['read_at'] == null) {
      try {
        await api.post('/notifications/${item['id']}/read');
      } catch (_) {
        // Opening the item matters more than the read flag
      }
    }
    if (!mounted) return;

    final opened = await openTarget(
      context,
      PushTarget(item['category']?.toString() ?? '', item['entity_id'] as int?),
    );

    if (!opened && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item['title']?.toString() ?? ''),
          content: SelectableText(item['body']?.toString() ?? ''),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
    }

    refreshList();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return PagedList(
      key: _list,
      path: '/notifications',
      header: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: TextButton.icon(
          onPressed: _markAll,
          icon: const Icon(Icons.done_all, size: 18),
          label: Text(s.t('mark_all')),
        ),
      ),
      itemBuilder: (context, item, refreshList) {
        final unread = item['read_at'] == null;
        return ListTile(
          tileColor: unread ? brandColor.withOpacity(0.06) : null,
          leading: Icon(_categoryIcon(item['category']?.toString()), color: unread ? brandColor : Colors.grey),
          title: Text(
            item['title']?.toString() ?? '',
            style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w500),
          ),
          subtitle: Text(
            '${item['body'] ?? ''}\n${shortDate(item['created_at'])}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          onTap: () => _open(item, refreshList),
        );
      },
    );
  }
}
