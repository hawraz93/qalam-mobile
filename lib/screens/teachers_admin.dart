import 'package:flutter/material.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';
import 'web_page.dart';

/// Teacher control (teachers.manage): newly registered ones waiting for approval,
/// active ones, and those who left — with the date and reason kept.
Color teacherStatusColor(String? status) => switch (status) {
      'active' => Tone.success,
      'pending' => Tone.warning,
      'left' => Tone.danger,
      _ => Tone.neutral,
    };

class TeachersAdminScreen extends StatefulWidget {
  const TeachersAdminScreen({super.key});

  @override
  State<TeachersAdminScreen> createState() => _TeachersAdminScreenState();
}

class _TeachersAdminScreenState extends State<TeachersAdminScreen> {
  String _status = 'pending';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('teachers_admin'))),
      body: Column(
        children: [
          FilterBar(
            segments: {
              'pending': s.t('teacher_pending'),
              'active': s.t('teacher_active'),
              'left': s.t('teacher_left'),
              'all': s.t('users_all'),
            },
            selected: _status,
            onChanged: (value) => setState(() => _status = value),
          ),
          if (_status == 'pending')
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(s.t('teacher_pending_hint'), style: const TextStyle(fontSize: 12.5, color: Tone.warning)),
            ),
          SearchField(onChanged: (value) => setState(() => _search = value)),
          Expanded(
            child: PagedList(
              path: '/admin/teachers',
              query: {if (_status != 'all') 'status': _status, if (_search.isNotEmpty) 'search': _search},
              emptyIcon: Icons.school_outlined,
              itemBuilder: (context, teacher, refresh) {
                final status = teacher['status']?.toString();
                return ItemCard(
                  icon: Icons.school_outlined,
                  accent: teacherStatusColor(status),
                  title: teacher['name']?.toString() ?? '',
                  subtitle: [teacher['title'], teacher['department']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                  unread: status == 'pending',
                  trailing: status == 'left' ? teacher['left_at']?.toString() : relativeDate(context, teacher['created_at']),
                  chips: [
                    Pill(s.t('teacher_$status'), color: teacherStatusColor(status)),
                    if (status == 'left' && (teacher['left_reason'] ?? '').toString().isNotEmpty)
                      Pill(teacher['left_reason'].toString()),
                  ],
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeacherAdminDetailScreen(id: teacher['id'] as int)));
                    refresh();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class TeacherAdminDetailScreen extends StatelessWidget {
  const TeacherAdminDetailScreen({super.key, required this.id});

  final int id;

  /// What the server allows for this teacher now; older servers send no list,
  /// so it falls back to the status.
  List<String> _actionsOf(Map<String, dynamic> teacher) {
    final list = teacher['actions'];
    if (list is List) return list.map((a) => a.toString()).toList();
    return switch (teacher['status']) {
      'active' => ['mark_left'],
      'left' => ['return'],
      _ => ['activate'],
    };
  }

  Future<bool> _ask(BuildContext context, String text, String action, {bool danger = false}) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(S.of(context).t('cancel'))),
          FilledButton(
            style: danger ? FilledButton.styleFrom(backgroundColor: Tone.danger) : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _call(BuildContext context, Future<dynamic> Function() request, VoidCallback reload) async {
    final s = S.of(context);
    try {
      await request();
      if (context.mounted) toast(context, s.t('saved'));
      reload();
    } catch (e) {
      if (context.mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _run(BuildContext context, String action, Map<String, dynamic> teacher, VoidCallback reload) async {
    final s = S.of(context);
    final name = teacher['name']?.toString() ?? '';

    switch (action) {
      case 'activate' || 'return':
        final returning = action == 'return';
        final yes = await _ask(
          context,
          s.t(returning ? 'teacher_return_confirm' : 'teacher_activate_confirm').replaceAll('{name}', name),
          s.t(returning ? 'teacher_return' : 'activate'),
        );
        if (!yes || !context.mounted) return;
        return _call(context, () => api.post('/admin/teachers/$id/activate'), reload);

      case 'mark_left':
        final saved = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _LeftSheet(id: id, name: name),
        );
        if (saved == true) {
          if (context.mounted) toast(context, s.t('saved'));
          reload();
        }

      case 'deactivate':
        final hasAccount = teacher['account'] != null;
        var alsoAccount = false;
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialog) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.t('teacher_deactivate_confirm').replaceAll('{name}', name)),
                  if (hasAccount)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: alsoAccount,
                      onChanged: (v) => setDialog(() => alsoAccount = v ?? false),
                      title: Text(s.t('left_deactivate_account')),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Tone.warning),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(s.t('teacher_deactivate')),
                ),
              ],
            ),
          ),
        );
        if (yes != true || !context.mounted) return;
        return _call(context, () => api.post('/admin/teachers/$id/deactivate', {'deactivate_account': alsoAccount}), reload);

      case 'account_on':
        return _call(context, () => api.put('/admin/teachers/$id/account', {'active': true}), reload);

      case 'account_off':
        final yes = await _ask(context, s.t('deactivate_confirm').replaceAll('{name}', name), s.t('account_off_action'), danger: true);
        if (!yes || !context.mounted) return;
        return _call(context, () => api.put('/admin/teachers/$id/account', {'active': false}), reload);

      case 'delete':
        final deleted = await deleteWithLinks(
          context,
          path: '/admin/teachers/$id',
          name: name,
          confirmText: s.t('teacher_delete_confirm'),
          deleteLabel: s.t('delete'),
          linksHint: s.t('teacher_links_hint'),
          forceLabel: s.t('teacher_delete_with_records'),
          forceConfirm: s.t('teacher_delete_with_records_confirm'),
          forceBody: {'with_records': true},
        );
        if (deleted && context.mounted) Navigator.of(context).pop();
    }
  }

  /// One button per allowed action.
  Widget _actionButton(BuildContext context, String action, Map<String, dynamic> teacher, VoidCallback reload) {
    final s = S.of(context);
    void run() => _run(context, action, teacher, reload);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: switch (action) {
        'activate' => FilledButton.icon(onPressed: run, icon: const Icon(Icons.how_to_reg_outlined), label: Text(s.t('activate'))),
        'return' => FilledButton.icon(onPressed: run, icon: const Icon(Icons.replay_rounded), label: Text(s.t('teacher_return'))),
        'mark_left' => OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Tone.danger),
            onPressed: run,
            icon: const Icon(Icons.logout_rounded),
            label: Text(s.t('teacher_mark_left')),
          ),
        'deactivate' => OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Tone.warning),
            onPressed: run,
            icon: const Icon(Icons.visibility_off_outlined),
            label: Text(s.t('teacher_deactivate')),
          ),
        'account_on' => FilledButton.tonalIcon(onPressed: run, icon: const Icon(Icons.key_outlined), label: Text(s.t('account_on_action'))),
        'account_off' => FilledButton.tonalIcon(onPressed: run, icon: const Icon(Icons.key_off_outlined), label: Text(s.t('account_off_action'))),
        'delete' => TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Tone.danger),
            onPressed: run,
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(s.t('teacher_delete')),
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('teachers_admin'))),
      body: Loader(
        load: () async {
          final body = await api.get('/admin/teachers/$id');
          return Map<String, dynamic>.from(body['data'] as Map);
        },
        builder: (context, teacher, reload) {
          final status = teacher['status']?.toString();
          final account = teacher['account'] as Map?;
          final history = (teacher['history'] as List? ?? []).map((h) => Map<String, dynamic>.from(h as Map)).toList();
          final actions = _actionsOf(teacher);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Avatar(name: teacher['name']?.toString() ?? '', url: teacher['avatar']?.toString(), size: 58),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(teacher['name']?.toString() ?? '', style: Theme.of(context).textTheme.titleMedium),
                        if ((teacher['name_en'] ?? '').toString().isNotEmpty)
                          Text(teacher['name_en'].toString(), style: const TextStyle(fontSize: 12.5)),
                        const SizedBox(height: 6),
                        Pill(s.t('teacher_$status'), color: teacherStatusColor(status)),
                      ]),
                    ),
                  ]),
                ),
              ),
              if (status == 'left') ...[
                const SizedBox(height: 12),
                FieldGroup(
                  title: s.t('teacher_left'),
                  icon: Icons.logout_rounded,
                  children: [
                    InfoRow(s.t('left_date'), teacher['left_at'], icon: Icons.event_outlined),
                    InfoRow(s.t('left_reason'), teacher['left_reason'], icon: Icons.notes_rounded),
                    InfoRow(s.t('done_by'), teacher['left_by'], icon: Icons.person_outline),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              FieldGroup(
                title: s.t('details'),
                icon: Icons.badge_outlined,
                children: [
                  InfoRow(s.t('department'), teacher['department'], icon: Icons.account_tree_outlined),
                  InfoRow(s.t('qualification'), [teacher['degree'], teacher['title']].where((v) => v != null).join(' · '), icon: Icons.workspace_premium_outlined),
                  InfoRow(s.t('specialty'), teacher['specialty'], icon: Icons.menu_book_outlined),
                  InfoRow(s.t('phone'), teacher['phone'], icon: Icons.phone_outlined),
                  InfoRow(s.t('email'), account?['email'] ?? teacher['email'], icon: Icons.alternate_email),
                  if (account != null)
                    InfoRow(s.t('active_account'), s.t(account['is_active'] == true ? 'users_active' : 'account_off'), icon: Icons.key_outlined),
                ],
              ),
              const SizedBox(height: 16),
              // The main step first, delete last
              for (final action in const ['activate', 'return', 'account_on', 'mark_left', 'deactivate', 'account_off', 'delete'])
                if (actions.contains(action)) _actionButton(context, action, teacher, reload),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => WebPageScreen(path: teacher['web_path'].toString(), title: teacher['name']?.toString() ?? ''),
                )),
                icon: const Icon(Icons.open_in_browser_rounded),
                label: Text(s.t('open_on_website')),
              ),
              if (history.isNotEmpty) ...[
                const SizedBox(height: 12),
                FieldGroup(
                  title: s.t('recent_activity'),
                  icon: Icons.history_rounded,
                  children: [
                    for (var i = 0; i < history.length; i++)
                      TimelineEntry(
                        icon: Icons.circle,
                        color: history[i]['event'] == 'teacher_left' ? Tone.danger : Tone.success,
                        title: s.t('ev_${history[i]['event']}'),
                        text: [history[i]['by'], history[i]['reason']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
                        date: relativeDate(context, history[i]['created_at']),
                        last: i == history.length - 1,
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Date, reason and whether to switch the sign-in account off too.
class _LeftSheet extends StatefulWidget {
  const _LeftSheet({required this.id, required this.name});

  final int id;
  final String name;

  @override
  State<_LeftSheet> createState() => _LeftSheetState();
}

class _LeftSheetState extends State<_LeftSheet> {
  final _reason = TextEditingController();
  DateTime _date = DateTime.now();
  bool _deactivate = true;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_reason.text.trim().length < 3) {
      toast(context, S.of(context).t('required'));
      return;
    }
    setState(() => _busy = true);
    try {
      await api.post('/admin/teachers/${widget.id}/left', {
        'reason': _reason.text.trim(),
        'date': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
        'deactivate_account': _deactivate,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${s.t('teacher_mark_left')} · ${widget.name}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          PickerField(
            label: s.t('left_date'),
            icon: Icons.event_outlined,
            value: '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: s.t('left_reason'), hintText: s.t('left_reason_hint'), alignLabelWithHint: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _deactivate,
            onChanged: (v) => setState(() => _deactivate = v),
            title: Text(s.t('left_deactivate_account')),
          ),
          Text(s.t('left_hint'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Tone.danger),
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.logout_rounded),
            label: Text(s.t('teacher_mark_left')),
          ),
        ],
      ),
    );
  }
}
