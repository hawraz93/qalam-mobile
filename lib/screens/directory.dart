import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

/// Staff phone book: search by name, narrow to a department (its units included),
/// call or email in one tap.
class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});

  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  String _search = '';
  Map<String, dynamic>? _department;
  List<Map<String, dynamic>>? _departments;

  Future<void> _pickDepartment() async {
    final s = S.of(context);
    try {
      _departments ??= await api.departments();
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
      return;
    }
    if (!mounted) return;
    final picked = await showPickerSheet(
      context,
      title: s.t('all_departments'),
      load: (search) async {
        final q = search.trim();
        return [
          {'id': 0, 'name': s.t('all_departments'), 'description': ''},
          ..._departments!.where((d) => q.isEmpty || '${d['name']} ${d['description']}'.contains(q)),
        ];
      },
      label: (row) => row['name']?.toString() ?? '',
      sublabel: (row) => row['description']?.toString() ?? '',
    );
    if (picked != null) setState(() => _department = picked['id'] == 0 ? null : picked);
  }

  Future<void> _privacy() async {
    final s = S.of(context);
    var hidden = api.user?['directory_hide_phone'] == true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: SwitchListTile(
              value: hidden,
              title: Text(s.t('hide_my_phone'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(s.t('hide_my_phone_hint')),
              secondary: const Icon(Icons.phone_disabled_outlined),
              onChanged: (value) async {
                setSheet(() => hidden = value);
                try {
                  await api.put('/me/directory', {'hide_phone': value});
                  api.user?['directory_hide_phone'] = value;
                } catch (e) {
                  setSheet(() => hidden = !value);
                  if (context.mounted) toast(context, errorText(context, e));
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('directory')),
        actions: [IconButton(onPressed: _privacy, icon: const Icon(Icons.privacy_tip_outlined), tooltip: s.t('hide_my_phone'))],
      ),
      body: Column(
        children: [
          SearchField(onChanged: (value) => setState(() => _search = value)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: PickerField(
              label: s.t('all_departments'),
              icon: Icons.account_tree_outlined,
              value: _department?['name']?.toString(),
              detail: _department?['description']?.toString(),
              onTap: _pickDepartment,
            ),
          ),
          Expanded(
            child: PagedList(
              path: '/directory',
              query: {
                if (_search.isNotEmpty) 'search': _search,
                if (_department != null) 'department_id': '${_department!['id']}',
              },
              emptyIcon: Icons.person_search_outlined,
              itemBuilder: (context, person, refresh) => _PersonTile(person: person),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person});

  final Map<String, dynamic> person;

  Future<void> _launch(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) toast(context, S.of(context).t('cannot_open'));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final phone = person['phone']?.toString();
    final email = person['email']?.toString();
    final subtitle = [person['title'], person['department']].where((v) => v != null && '$v'.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Row(
            children: [
              Avatar(name: person['name']?.toString() ?? '', url: person['avatar']?.toString(), size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(person['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4)),
                  ],
                ),
              ),
              if (phone != null && phone.isNotEmpty)
                IconButton(
                  tooltip: s.t('call'),
                  onPressed: () => _launch(context, Uri(scheme: 'tel', path: phone)),

                  icon: const Icon(Icons.call_outlined, color: Tone.success),
                ),
              if (email != null && email.isNotEmpty)
                GestureDetector(
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: email));
                    toast(context, s.t('copied'));
                  },
                  child: IconButton(
                    tooltip: s.t('send_email'),
                    onPressed: () => _launch(context, Uri(scheme: 'mailto', path: email)),
                    icon: Icon(Icons.mail_outline_rounded, color: scheme.primary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
