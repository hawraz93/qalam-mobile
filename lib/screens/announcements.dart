import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

/// Official announcements (تعاميم): what was sent to me, and for senders what they sent
/// with a read report.
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _received = GlobalKey<PagedListState>();
  final _sent = GlobalKey<PagedListState>();

  Future<void> _compose() async {
    final sent = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const ComposeAnnouncementScreen()));
    if (sent == true) _sent.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final canSend = api.can('announcements');

    final received = PagedList(
      key: _received,
      path: '/announcements',
      emptyIcon: Icons.campaign_outlined,
      itemBuilder: (context, item, refresh) => _AnnouncementCard(item: item, onClosed: refresh),
    );

    if (!canSend) {
      return Scaffold(appBar: AppBar(title: Text(s.t('announcements'))), body: received);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('announcements')),
          bottom: TabBar(tabs: [Tab(text: s.t('ann_received')), Tab(text: s.t('ann_sent'))]),
        ),
        body: TabBarView(
          children: [
            received,
            PagedList(
              key: _sent,
              path: '/announcements/sent',
              emptyIcon: Icons.outbox_outlined,
              itemBuilder: (context, item, refresh) => _AnnouncementCard(item: item, onClosed: refresh, showReads: true),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _compose,
          icon: const Icon(Icons.edit_outlined),
          label: Text(s.t('new_announcement')),
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.item, required this.onClosed, this.showReads = false});

  final Map<String, dynamic> item;
  final VoidCallback onClosed;
  final bool showReads;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final important = item['priority'] == 'important';
    final unread = !showReads && item['read_at'] == null;
    final total = (item['recipients_count'] as num?)?.toInt() ?? 0;
    final read = (item['read_count'] as num?)?.toInt() ?? 0;

    return ItemCard(
      icon: important ? Icons.priority_high_rounded : Icons.campaign_outlined,
      accent: important ? Tone.danger : null,
      title: item['title']?.toString() ?? '',
      subtitle: item['excerpt']?.toString(),
      trailing: relativeDate(context, item['created_at']),
      unread: unread,
      chips: [
        if (important) Pill(s.t('ann_important'), color: Tone.danger),
        if (item['has_attachment'] == true) Pill(s.t('attachments'), icon: Icons.attach_file_rounded),
        if (showReads)
          Pill(
            s.t('read_by').replaceAll('{r}', '$read').replaceAll('{t}', '$total'),
            color: total > 0 && read == total ? Tone.success : Tone.info,
            icon: Icons.done_all_rounded,
          )
        else if (item['sender'] != null)
          Pill(item['sender'].toString()),
      ],
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AnnouncementDetailScreen(id: item['id'] as int)),
        );
        onClosed();
      },
    );
  }
}

class AnnouncementDetailScreen extends StatelessWidget {
  const AnnouncementDetailScreen({super.key, required this.id});

  final int id;

  Future<void> _openAttachment(BuildContext context, Map attachment) async {
    final url = attachment['open_url']?.toString();
    if (url == null) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) toast(context, S.of(context).t('cannot_open'));
  }

  Future<void> _withdraw(BuildContext context) async {
    final s = S.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.t('withdraw_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('withdraw'))),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    try {
      await api.delete('/announcements/$id');
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) toast(context, errorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('announcements'))),
      body: Loader(
        load: () async {
          final body = await api.get('/announcements/$id');
          return Map<String, dynamic>.from(body['data'] as Map);
        },
        builder: (context, item, reload) {
          final important = item['priority'] == 'important';
          final attachment = item['attachment'] as Map?;
          final canReport = item['can_see_report'] == true;
          final total = (item['recipients_count'] as num?)?.toInt() ?? 0;
          final read = (item['read_count'] as num?)?.toInt() ?? 0;
          final mine = item['sender'] != null && item['sender'] == api.user?['name'];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              DetailHeader(
                pills: [
                  if (important) Pill(s.t('ann_important'), color: Tone.danger, icon: Icons.priority_high_rounded),
                  if (item['sender'] != null) Pill(s.t('from_sender').replaceAll('{name}', item['sender'].toString())),
                ],
                title: item['title']?.toString(),
                body: item['body']?.toString(),
                meta: shortDate(item['created_at']),
              ),
              if (attachment != null) ...[
                const SizedBox(height: 12),
                FieldGroup(
                  title: s.t('attachments'),
                  icon: Icons.attach_file_rounded,
                  children: [
                    if (attachment['is_image'] == true)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          attachment['url'].toString(),
                          headers: api.authHeaders,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _openAttachment(context, attachment),
                      icon: Icon(attachment['is_image'] == true ? Icons.open_in_new_rounded : Icons.picture_as_pdf_outlined),
                      label: Text(s.t('open_attachment')),
                    ),
                  ],
                ),
              ],
              if (canReport) ...[
                const SizedBox(height: 12),
                FieldGroup(
                  title: s.t('read_report'),
                  icon: Icons.done_all_rounded,
                  children: [
                    Text(s.t('read_by').replaceAll('{r}', '$read').replaceAll('{t}', '$total'),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : read / total,
                        minHeight: 8,
                        color: Tone.success,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => _ReadersScreen(id: id)))
                          .then((_) => reload()),
                      icon: const Icon(Icons.people_outline_rounded),
                      label: Text(s.t('read_report')),
                    ),
                    if (mine || (api.user?['roles'] as List? ?? []).any((r) => ['admin', 'Admin', 'Super Admin'].contains(r))) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () => _withdraw(context),
                        style: TextButton.styleFrom(foregroundColor: Tone.danger),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(s.t('withdraw')),
                      ),
                    ],
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

class _ReadersScreen extends StatelessWidget {
  const _ReadersScreen({required this.id});

  final int id;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Loader(
      load: () async => Map<String, dynamic>.from(await api.get('/announcements/$id/readers') as Map),
      builder: (context, body, reload) {
        final rows = (body['data'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
        final read = rows.where((r) => r['read_at'] != null).toList();
        final unread = rows.where((r) => r['read_at'] == null).toList();

        Widget list(List<Map<String, dynamic>> people) => people.isEmpty
            ? const EmptyState(icon: Icons.people_outline_rounded)
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: people.length,
                itemBuilder: (context, i) => ListTile(
                  leading: Avatar(name: people[i]['name']?.toString() ?? '', size: 40),
                  title: Text(people[i]['name']?.toString() ?? ''),
                  subtitle: people[i]['department'] == null ? null : Text(people[i]['department'].toString()),
                  trailing: people[i]['read_at'] == null
                      ? null
                      : Text(relativeDate(context, people[i]['read_at']), style: const TextStyle(fontSize: 12)),
                ),
              );

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(s.t('read_report')),
              bottom: TabBar(tabs: [
                Tab(text: '${s.t('readers_read')} (${read.length})'),
                Tab(text: '${s.t('readers_unread')} (${unread.length})'),
              ]),
            ),
            body: TabBarView(children: [list(read), list(unread)]),
          ),
        );
      },
    );
  }
}

/// Writing an announcement: text, importance, audience (with a live head count), letter.
class ComposeAnnouncementScreen extends StatefulWidget {
  const ComposeAnnouncementScreen({super.key});

  @override
  State<ComposeAnnouncementScreen> createState() => _ComposeAnnouncementScreenState();
}

class _ComposeAnnouncementScreenState extends State<ComposeAnnouncementScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _important = false;
  String _audience = 'all';
  final List<Map<String, dynamic>> _departments = [];
  final Set<String> _roles = {};
  String? _attachment;

  List<Map<String, dynamic>> _departmentOptions = [];
  List<String> _roleOptions = [];
  int? _count;
  Timer? _countDebounce;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
    _refreshCount();
  }

  @override
  void dispose() {
    _countDebounce?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final body = await api.get('/announcements/audience');
      if (!mounted) return;
      setState(() {
        _departmentOptions = (body['departments'] as List).map((d) => Map<String, dynamic>.from(d as Map)).toList();
        _roleOptions = (body['roles'] as List).map((r) => r.toString()).toList();
      });
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Map<String, dynamic> get _audienceBody => {
        'audience_type': _audience,
        if (_audience == 'departments') 'department_ids': [for (final d in _departments) d['id']],
        if (_audience == 'roles') 'roles': _roles.toList(),
      };

  bool get _audienceComplete =>
      _audience == 'all' || (_audience == 'departments' && _departments.isNotEmpty) || (_audience == 'roles' && _roles.isNotEmpty);

  void _refreshCount() {
    _countDebounce?.cancel();
    if (!_audienceComplete) {
      setState(() => _count = null);
      return;
    }
    _countDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final body = await api.post('/announcements/audience-count', _audienceBody);
        if (mounted) setState(() => _count = (body['count'] as num).toInt());
      } catch (_) {
        if (mounted) setState(() => _count = null);
      }
    });
  }

  Future<void> _addDepartment() async {
    final s = S.of(context);
    final picked = await showPickerSheet(
      context,
      title: s.t('add_department'),
      load: (search) async {
        final q = search.trim();
        return _departmentOptions
            .where((d) => !_departments.any((x) => x['id'] == d['id']))
            .where((d) => q.isEmpty || '${d['name']} ${d['description']}'.contains(q))
            .toList();
      },
      label: (row) => row['name']?.toString() ?? '',
      sublabel: (row) => row['description']?.toString() ?? '',
    );
    if (picked != null) {
      setState(() => _departments.add(picked));
      _refreshCount();
    }
  }

  Future<void> _pickAttachment() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp']);
    final path = picked.firstOrNull?.path;
    if (path != null) setState(() => _attachment = path);
  }

  Future<void> _send() async {
    final s = S.of(context);
    if (!_form.currentState!.validate() || !_audienceComplete) return;

    final count = _count ?? 0;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.campaign_outlined),
        content: Text(s.t('ann_confirm').replaceAll('{n}', '$count')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.t('ann_send'))),
        ],
      ),
    );
    if (yes != true) return;

    setState(() => _busy = true);
    try {
      final fields = <String, dynamic>{
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'priority': _important ? 'important' : 'normal',
        ..._audienceBody,
      };
      if (_attachment == null) {
        await api.post('/announcements', fields);
      } else {
        // Multipart fields are flat strings; Laravel reads list[0], list[1] as an array
        final flat = <String, String>{};
        fields.forEach((key, value) {
          if (value is List) {
            for (var i = 0; i < value.length; i++) {
              flat['$key[$i]'] = '${value[i]}';
            }
          } else {
            flat[key] = '$value';
          }
        });
        await api.postFiles('/announcements', flat, [_attachment!], field: 'attachment');
      }
      if (!mounted) return;
      toast(context, s.t('ann_sent_ok'));
      Navigator.of(context).pop(true);
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

    return Scaffold(
      appBar: AppBar(title: Text(s.t('new_announcement'))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            FieldGroup(
              title: s.t('ann_body'),
              icon: Icons.edit_note_rounded,
              children: [
                TextFormField(
                  controller: _title,
                  decoration: InputDecoration(labelText: s.t('ann_title')),
                  validator: (v) => (v ?? '').trim().length < 3 ? s.t('required') : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _body,
                  minLines: 5,
                  maxLines: 14,
                  decoration: InputDecoration(labelText: s.t('ann_body'), alignLabelWithHint: true),
                  validator: (v) => (v ?? '').trim().length < 5 ? s.t('required') : null,
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _important,
                  onChanged: (v) => setState(() => _important = v),
                  title: Text(s.t('ann_important'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  secondary: Icon(Icons.priority_high_rounded, color: _important ? Tone.danger : scheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FieldGroup(
              title: s.t('ann_audience'),
              icon: Icons.groups_outlined,
              children: [
                ColumnsWrap(
                  columns: 3,
                  spacing: 8,
                  children: [
                    for (final (key, icon) in const [
                      ('all', Icons.public_rounded),
                      ('departments', Icons.account_tree_outlined),
                      ('roles', Icons.badge_outlined),
                    ])
                      ChoiceTile(
                        icon: icon,
                        label: s.t('aud_$key'),
                        selected: _audience == key,
                        onTap: () {
                          setState(() => _audience = key);
                          _refreshCount();
                        },
                      ),
                  ],
                ),
                if (_audience == 'departments') ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in _departments)
                        InputChip(
                          label: Text(d['name']?.toString() ?? ''),
                          onDeleted: () {
                            setState(() => _departments.remove(d));
                            _refreshCount();
                          },
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 18),
                        label: Text(s.t('add_department')),
                        onPressed: _departmentOptions.isEmpty ? null : _addDepartment,
                      ),
                    ],
                  ),
                ],
                if (_audience == 'roles') ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final role in _roleOptions)
                        FilterChip(
                          label: Text(role),
                          selected: _roles.contains(role),
                          onSelected: (on) {
                            setState(() => on ? _roles.add(role) : _roles.remove(role));
                            _refreshCount();
                          },
                        ),
                    ],
                  ),
                ],
                if (_count != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.people_alt_outlined, size: 18, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(s.t('reach_count').replaceAll('{n}', '$_count'),
                          style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            FieldGroup(
              title: s.t('attachments'),
              icon: Icons.attach_file_rounded,
              children: [
                if (_attachment == null)
                  OutlinedButton.icon(
                    onPressed: _pickAttachment,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(s.t('ann_attachment')),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(_attachment!.split(RegExp(r'[\\/]')).last, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _attachment = null),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _busy || !_audienceComplete || _count == 0 ? null : _send,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: Text(s.t('ann_send')),
          ),
        ),
      ),
    );
  }
}
