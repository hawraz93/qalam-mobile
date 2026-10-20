import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import 'complaints.dart';
import 'contacts.dart';
import 'tickets.dart';

/// Opens a section of the Work tab from elsewhere (e.g. the management overview).
typedef WorkShortcut = void Function(String section);

/// One tab that groups everything the user handles: the IT desk, complaints and
/// contact messages for admins, plus the tickets they opened themselves.
/// Users without any admin area see their own tickets directly.
class WorkTab extends StatefulWidget {
  const WorkTab({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<WorkTab> createState() => WorkTabState();
}

class WorkTabState extends State<WorkTab> with TickerProviderStateMixin {
  late final List<String> _sections = [
    if (api.can('it_tickets')) 'tickets',
    if (api.can('complaints')) 'complaints',
    if (api.can('contacts')) 'contacts',
    'my_tickets',
  ];
  late final TabController _controller = TabController(length: _sections.length, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Jumps to a section ('tickets', 'complaints', 'contacts', 'my_tickets') when it exists.
  void show(String section) {
    final index = _sections.indexOf(section);
    if (index >= 0) _controller.animateTo(index);
  }

  Widget _body(String section) {
    switch (section) {
      case 'tickets':
        return const AdminTicketsTab();
      case 'complaints':
        return const ComplaintsTab();
      case 'contacts':
        return const ContactsTab();
      default:
        return const MyTicketsTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (_sections.length == 1) return _body(_sections.first);

    return Column(
      children: [
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: TabBar(
            controller: _controller,
            isScrollable: _sections.length > 3,
            tabAlignment: _sections.length > 3 ? TabAlignment.start : TabAlignment.fill,
            labelStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700, fontSize: 13.5),
            unselectedLabelStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w500, fontSize: 13.5),
            labelColor: scheme.primary,
            unselectedLabelColor: scheme.onSurfaceVariant,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: scheme.outlineVariant.withValues(alpha: 0.5),
            tabs: [for (final section in _sections) Tab(text: s.t(section))],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            children: [for (final section in _sections) _body(section)],
          ),
        ),
      ],
    );
  }
}
