import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

/// Opens a new IT ticket in short steps: where (department), what (category),
/// how urgent, details. Guests also say who they are; signed-in users do not.
class TicketFormScreen extends StatefulWidget {
  const TicketFormScreen({super.key});

  @override
  State<TicketFormScreen> createState() => _TicketFormScreenState();
}

class _TicketFormScreenState extends State<TicketFormScreen> {
  static const _categories = {
    'hardware': Icons.computer_rounded,
    'software': Icons.apps_rounded,
    'network': Icons.wifi_rounded,
    'account': Icons.manage_accounts_rounded,
    'printer': Icons.print_rounded,
    'other': Icons.help_outline_rounded,
  };

  static const _priorities = ['low', 'medium', 'high', 'urgent'];
  static const _maxPhotos = 3;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _category = 'other';
  String _priority = 'medium';
  bool _busy = false;
  String? _sentTicketNo;

  /// Local paths of the photos to send, already scaled down by the picker.
  final List<String> _photos = [];

  List<Map<String, dynamic>> _departments = [];
  Map<String, dynamic>? _department;
  bool _departmentsLoading = true;
  bool _departmentsFailed = false;
  bool _departmentMissing = false;

  bool get _guest => !api.isSignedIn;

  @override
  void initState() {
    super.initState();
    _phone.text = api.user?['phone']?.toString() ?? '';
    _loadDepartments();
  }

  @override
  void dispose() {
    for (final controller in [_name, _email, _phone, _title, _description]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDepartments() async {
    setState(() {
      _departmentsLoading = true;
      _departmentsFailed = false;
    });
    try {
      final rows = await api.departments();
      if (!mounted) return;
      final own = api.user?['department_id'];
      setState(() {
        _departments = rows;
        // Most tickets are about the sender's own department: start there.
        _department ??= rows.where((d) => d['id'] == own).firstOrNull;
      });
    } catch (_) {
      if (mounted) setState(() => _departmentsFailed = true);
    } finally {
      if (mounted) setState(() => _departmentsLoading = false);
    }
  }

  Future<void> _pickDepartment() async {
    if (_departmentsFailed) return _loadDepartments();
    final s = S.of(context);
    final picked = await showPickerSheet(
      context,
      title: s.t('choose_department'),
      load: (search) async {
        final q = _normalize(search.trim());
        if (q.isEmpty) return _departments;
        return _departments.where((d) => _normalize('${d['name']} ${d['description']}').contains(q)).toList();
      },
      label: (row) => row['name']?.toString() ?? '',
      sublabel: (row) => row['description']?.toString() ?? '',
    );
    if (picked != null) {
      setState(() {
        _department = picked;
        _departmentMissing = false;
      });
    }
  }

  /// Department names are written in Arabic; Kurdish keyboards type ک / ی / ە.
  /// Folding the letter variants lets either spelling find the department.
  static String _normalize(String text) {
    const folds = {'ك': 'ک', 'ي': 'ی', 'ى': 'ی', 'ة': 'ه', 'ە': 'ه', 'أ': 'ا', 'إ': 'ا', 'آ': 'ا', 'ؤ': 'و'};
    final buffer = StringBuffer();
    for (final char in text.toLowerCase().characters) {
      buffer.write(folds[char] ?? char);
    }
    return buffer.toString();
  }

  Future<void> _submit() async {
    final fieldsOk = _form.currentState!.validate();
    setState(() => _departmentMissing = _department == null);
    if (!fieldsOk || _department == null) return;

    setState(() => _busy = true);
    try {
      final fields = {
        if (_guest) 'requester_name': _name.text.trim(),
        if (_guest) 'requester_email': _email.text.trim(),
        if (_phone.text.trim().isNotEmpty) 'requester_phone': _phone.text.trim(),
        'department_id': '${_department!['id']}',
        'category': _category,
        'priority': _priority,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
      };
      final body = _photos.isEmpty
          ? await api.post('/tickets/submit', fields)
          : await api.postFiles('/tickets/submit', fields, _photos);
      if (mounted) setState(() => _sentTicketNo = body['data']['ticket_no']?.toString() ?? '');
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto() async {
    final s = S.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(s.t('camera')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.t('gallery')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    // Phone photos are 4–8 MB; 1600 px at 80% keeps them sharp enough and well under the limit
    final picker = ImagePicker();
    try {
      final picked = source == ImageSource.camera
          ? [await picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80)]
          : await picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 80, limit: _maxPhotos - _photos.length);
      final paths = picked.whereType<XFile>().map((file) => file.path);
      if (mounted) setState(() => _photos.addAll(paths.take(_maxPhotos - _photos.length)));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  String? _required(String? value, {int min = 1}) {
    return (value ?? '').trim().length < min ? S.of(context).t('required') : null;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    if (_sentTicketNo != null) {
      return _SentScreen(ticketNo: _sentTicketNo!, guest: _guest);
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.t('new_ticket'))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (_guest) ...[
              FieldGroup(
                title: s.t('your_details'),
                icon: Icons.person_outline_rounded,
                children: [
                  TextFormField(
                    controller: _name,
                    decoration:
                        InputDecoration(labelText: s.t('your_name'), prefixIcon: const Icon(Icons.badge_outlined)),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _email,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: s.t('email'), prefixIcon: const Icon(Icons.alternate_email)),
                    validator: (value) => (value ?? '').contains('@') ? null : s.t('required'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FieldGroup(
              title: s.t('ticket_where'),
              hint: s.t('ticket_where_hint'),
              icon: Icons.location_on_outlined,
              children: [
                PickerField(
                  label: _departmentsFailed ? s.t('departments_failed') : s.t('choose_department'),
                  icon: Icons.account_tree_outlined,
                  value: _department?['name']?.toString(),
                  detail: _department?['description']?.toString(),
                  loading: _departmentsLoading,
                  errorText: _departmentMissing ? s.t('required') : null,
                  onTap: _departmentsLoading ? null : _pickDepartment,
                ),
              ],
            ),
            const SizedBox(height: 12),
            FieldGroup(
              title: s.t('ticket_what'),
              icon: Icons.category_outlined,
              children: [
                ColumnsWrap(
                  columns: 3,
                  spacing: 8,
                  children: [
                    for (final entry in _categories.entries)
                      ChoiceTile(
                        icon: entry.value,
                        label: s.t('cat_${entry.key}'),
                        selected: _category == entry.key,
                        onTap: () => setState(() => _category = entry.key),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            FieldGroup(
              title: s.t('ticket_urgency'),
              icon: Icons.speed_rounded,
              children: [
                Row(
                  children: [
                    for (final priority in _priorities) ...[
                      if (priority != _priorities.first) const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceTile(
                          label: s.t(priority),
                          color: priorityColor(priority),
                          selected: _priority == priority,
                          onTap: () => setState(() => _priority = priority),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            FieldGroup(
              title: s.t('ticket_details'),
              icon: Icons.edit_note_rounded,
              children: [
                TextFormField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: s.t('ticket_title')),
                  validator: (value) => _required(value, min: 4),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _description,
                  minLines: 4,
                  maxLines: 10,
                  decoration: InputDecoration(labelText: s.t('ticket_description'), alignLabelWithHint: true),
                  validator: (value) => _required(value, min: 10),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.phone,
                  decoration:
                      InputDecoration(labelText: s.t('ticket_contact'), prefixIcon: const Icon(Icons.phone_outlined)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FieldGroup(
              title: s.t('attachments'),
              hint: s.t('photos_hint'),
              icon: Icons.photo_camera_outlined,
              children: [
                ColumnsWrap(
                  columns: 3,
                  spacing: 8,
                  children: [
                    for (final path in _photos)
                      _PhotoThumb(path: path, onRemove: () => setState(() => _photos.remove(path))),
                    if (_photos.length < _maxPhotos) _AddPhotoTile(onTap: _busy ? null : _addPhoto),
                  ],
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
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded),
            label: Text(s.t('send_ticket')),
          ),
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(File(path), fit: BoxFit.cover, cacheWidth: 300),
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 18, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: scheme.primary.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined, color: scheme.primary),
              const SizedBox(height: 6),
              Text(S.of(context).t('add_photo'),
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.primary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Confirmation after sending: the ticket number, easy to copy and quote later.
class _SentScreen extends StatelessWidget {
  const _SentScreen({required this.ticketNo, required this.guest});

  final String ticketNo;
  final bool guest;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: Tone.success.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 52, color: Tone.success),
              ),
              const SizedBox(height: 20),
              Text(s.t('ticket_sent'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
              Text(s.t('ticket_no'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              const SizedBox(height: 6),
              Material(
                color: scheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: ticketNo));
                    toast(context, s.t('copied'));
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ticketNo,
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700, color: scheme.primary, letterSpacing: 0.5),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.copy_rounded, size: 18, color: scheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
              if (guest) ...[
                const SizedBox(height: 16),
                Text(s.t('ticket_sent_guest'),
                    textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6)),
              ],
              const SizedBox(height: 28),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.t('done'))),
            ],
          ),
        ),
      ),
    );
  }
}
