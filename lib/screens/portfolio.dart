import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../strings.dart';
import '../widgets.dart';

/// Which portfolio list a screen shows.
enum PortfolioKind { education, teaching, research }

extension on PortfolioKind {
  String get path => switch (this) {
        PortfolioKind.education => '/teacher/educations',
        PortfolioKind.teaching => '/teacher/teachings',
        PortfolioKind.research => '/teacher/researches',
      };

  String get titleKey => switch (this) {
        PortfolioKind.education => 'education',
        PortfolioKind.teaching => 'teaching',
        PortfolioKind.research => 'research',
      };

  IconData get icon => switch (this) {
        PortfolioKind.education => Icons.school_outlined,
        PortfolioKind.teaching => Icons.menu_book_outlined,
        PortfolioKind.research => Icons.science_outlined,
      };
}

/// Dropdown values (degrees, semesters, departments...) fetched once per app run.
class PortfolioOptions {
  static Map<String, dynamic>? _cache;

  static Future<Map<String, dynamic>> get() async {
    if (_cache != null) return _cache!;
    final body = await api.get('/teacher/options');
    return _cache = Map<String, dynamic>.from(body['data'] as Map);
  }
}

String teacherName(Map<String, dynamic> row) =>
    (S.current == 'en' ? row['name_en'] : row['name_ar'])?.toString() ?? row['name_en']?.toString() ?? '';

/// Education, teaching or research list of the signed-in teacher with search, add, edit and delete.
class PortfolioListScreen extends StatefulWidget {
  const PortfolioListScreen({super.key, required this.kind});

  final PortfolioKind kind;

  @override
  State<PortfolioListScreen> createState() => _PortfolioListScreenState();
}

class _PortfolioListScreenState extends State<PortfolioListScreen> {
  final _list = GlobalKey<PagedListState>();
  String _search = '';

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    final s = S.of(context);
    final titleKey = item == null ? 'add_${widget.kind.titleKey}' : 'edit';
    final changed = await showFormSheet<bool>(
      context,
      title: s.t(titleKey),
      child: switch (widget.kind) {
        PortfolioKind.education => EducationForm(item: item),
        PortfolioKind.teaching => TeachingForm(item: item),
        PortfolioKind.research => ResearchForm(item: item),
      },
    );
    if (changed == true) {
      _list.currentState?.refresh();
      // The account/profile completion changes too
      api.refreshProfile().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(s.t(widget.kind.titleKey))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: Text(s.t('add')),
      ),
      body: Column(
        children: [
          SearchField(onChanged: (value) => setState(() => _search = value)),
          Expanded(
            child: PagedList(
              key: _list,
              path: widget.kind.path,
              query: {if (_search.isNotEmpty) 'search': _search},
              emptyIcon: widget.kind.icon,
              itemBuilder: (context, item, refresh) => _tile(context, item),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> item) {
    final s = S.of(context);
    switch (widget.kind) {
      case PortfolioKind.education:
        return ItemCard(
          icon: Icons.school_outlined,
          title: '${item['degree']} · ${item['field_of_study']}',
          subtitle: [item['university'], item['speciality']].where((v) => v != null && v.toString().isNotEmpty).join(' · '),
          trailing: '${item['graduation_year'] ?? ''}',
          chips: [Pill(item['degree']?.toString() ?? '')],
          onTap: () => _openForm(item),
        );
      case PortfolioKind.teaching:
        return ItemCard(
          icon: Icons.menu_book_outlined,
          title: item['subject']?.toString() ?? '',
          subtitle: [item['course_code'], item['department'], item['stage']].where((v) => v != null && v.toString().isNotEmpty).join(' · '),
          trailing: item['year']?.toString(),
          chips: [
            if (item['semester'] != null) Pill('${s.t('semester')} ${item['semester']}'),
            if (item['credit_hours'] != null) Pill('${item['credit_hours']} ${s.t('credit_hours_short')}'),
            if (item['course_book'] != null) Pill(s.t('course_book'), icon: Icons.picture_as_pdf_outlined, color: statusColor('resolved')),
          ],
          onTap: () => _openForm(item),
        );
      case PortfolioKind.research:
        final status = item['status']?.toString();
        return ItemCard(
          icon: Icons.science_outlined,
          title: item['title']?.toString() ?? '',
          subtitle: item['field']?.toString(),
          trailing: relativeDate(context, item['created_at']),
          chips: [
            if (status != null) Pill(s.t('research_$status'), color: status == 'published' ? statusColor('resolved') : priorityColor('medium')),
            if (item['type_journal'] != null) Pill(s.t('journal_${item['type_journal']}')),
            if ((item['co_authors'] as List? ?? []).isNotEmpty) Pill('${(item['co_authors'] as List).length} ${s.t('co_authors_short')}', icon: Icons.group_outlined),
          ],
          onTap: () => _openForm(item),
        );
    }
  }
}

/// Shared save / delete plumbing for the three forms.
mixin _PortfolioFormState<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;

  Map<String, dynamic>? get item;
  String get basePath;

  Future<void> submit(Map<String, dynamic> body) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (item == null) {
        await api.post(basePath, body);
      } else {
        await api.patch('$basePath/${item!['id']}', body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = errorText(context, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    final s = S.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.t('confirm_delete')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.t('delete')),
          ),
        ],
      ),
    );
    if (sure != true) return;

    setState(() => busy = true);
    try {
      await api.delete('$basePath/${item!['id']}');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = errorText(context, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget actions(BuildContext context, VoidCallback onSave) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: busy ? null : onSave,
          child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('save')),
        ),
        if (item != null) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: busy ? null : remove,
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(s.t('delete')),
          ),
        ],
      ],
    );
  }
}

/// Waits for the dropdown options, then builds the form.
class _WithOptions extends StatelessWidget {
  const _WithOptions({required this.builder});

  final Widget Function(BuildContext context, Map<String, dynamic> options) builder;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: PortfolioOptions.get(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return SizedBox(height: 200, child: ErrorView(error: snapshot.error!, onRetry: () => (context as Element).markNeedsBuild()));
        }
        if (!snapshot.hasData) {
          return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
        }
        return builder(context, snapshot.data!);
      },
    );
  }
}

List<String> _strings(Map<String, dynamic> options, String key) =>
    (options[key] as List? ?? []).map((v) => v.toString()).toList();

/* ----------------------------------------------------------------- education */

class EducationForm extends StatefulWidget {
  const EducationForm({super.key, this.item});

  final Map<String, dynamic>? item;

  @override
  State<EducationForm> createState() => _EducationFormState();
}

class _EducationFormState extends State<EducationForm> with _PortfolioFormState {
  final _form = GlobalKey<FormState>();
  late String? _degree = widget.item?['degree']?.toString();
  late final _field = TextEditingController(text: widget.item?['field_of_study']?.toString() ?? '');
  late final _speciality = TextEditingController(text: widget.item?['speciality']?.toString() ?? '');
  late final _year = TextEditingController(text: widget.item?['graduation_year']?.toString() ?? '');
  late int? _universityId = widget.item?['university_id'] as int?;
  late String? _universityName = widget.item?['university']?.toString();

  @override
  Map<String, dynamic>? get item => widget.item;

  @override
  String get basePath => '/teacher/educations';

  @override
  void dispose() {
    for (final c in [_field, _speciality, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickUniversity(Map<String, dynamic> options) async {
    final s = S.of(context);
    final picked = await showPickerSheet(
      context,
      title: s.t('university'),
      load: (search) async {
        final body = await api.get('/teacher/universities', {if (search.isNotEmpty) 'search': search});
        return (body['data'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
      },
      label: (row) => row['name']?.toString() ?? '',
      sublabel: (row) => row['country']?.toString() ?? '',
      createLabel: s.t('add_university'),
      onCreate: (name) => _createUniversity(name, options),
    );
    if (picked != null) {
      setState(() {
        _universityId = picked['id'] as int?;
        _universityName = picked['name']?.toString();
      });
    }
  }

  /// New university: name typed in the search box plus a country from the list.
  Future<Map<String, dynamic>?> _createUniversity(String name, Map<String, dynamic> options) async {
    final s = S.of(context);
    final countries = (options['countries'] as List? ?? []).map((c) => Map<String, dynamic>.from(c as Map)).toList();
    int? countryId;

    final go = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(s.t('add_university')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: countryId,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.t('country')),
                items: [for (final c in countries) DropdownMenuItem(value: c['id'] as int, child: Text(c['name'].toString(), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setDialog(() => countryId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.t('cancel'))),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.t('add'))),
          ],
        ),
      ),
    );
    if (go != true) return null;

    try {
      final body = await api.post('/teacher/universities', {'name': name, if (countryId != null) 'country_id': countryId});
      return Map<String, dynamic>.from(body['data'] as Map);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
      return null;
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    if (_universityId == null) {
      setState(() => error = S.of(context).t('pick_university'));
      return;
    }
    submit({
      'degree': _degree,
      'field_of_study': _field.text.trim(),
      'speciality': _speciality.text.trim(),
      'university_id': _universityId,
      'graduation_year': int.tryParse(_year.text.trim()),
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return _WithOptions(
      builder: (context, options) {
        final degrees = _strings(options, 'degrees');
        return Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: degrees.contains(_degree) ? _degree : null,
                decoration: InputDecoration(labelText: s.t('degree'), prefixIcon: const Icon(Icons.school_outlined)),
                items: [for (final d in degrees) DropdownMenuItem(value: d, child: Text(d))],
                validator: (v) => v == null ? s.t('required') : null,
                onChanged: (v) => setState(() => _degree = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _field,
                decoration: InputDecoration(labelText: s.t('field_of_study'), prefixIcon: const Icon(Icons.auto_stories_outlined)),
                validator: (v) => (v ?? '').trim().isEmpty ? s.t('required') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _speciality,
                decoration: InputDecoration(labelText: s.t('specialty'), prefixIcon: const Icon(Icons.psychology_outlined)),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _pickUniversity(options),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: s.t('university'),
                    prefixIcon: const Icon(Icons.account_balance_outlined),
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                  ),
                  child: Text(_universityName ?? s.t('pick_university'),
                      style: TextStyle(color: _universityName == null ? Theme.of(context).hintColor : null)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _year,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: s.t('graduation_year'), prefixIcon: const Icon(Icons.calendar_today_outlined)),
                validator: (v) {
                  final year = int.tryParse((v ?? '').trim());
                  if (year == null || year < 1900 || year > DateTime.now().year) return s.t('invalid_year');
                  return null;
                },
              ),
              actions(context, _save),
            ],
          ),
        );
      },
    );
  }
}

/* ------------------------------------------------------------------ teaching */

class TeachingForm extends StatefulWidget {
  const TeachingForm({super.key, this.item});

  final Map<String, dynamic>? item;

  @override
  State<TeachingForm> createState() => _TeachingFormState();
}

class _TeachingFormState extends State<TeachingForm> with _PortfolioFormState {
  final _form = GlobalKey<FormState>();
  late final _subject = TextEditingController(text: widget.item?['subject']?.toString() ?? '');
  late final _code = TextEditingController(text: widget.item?['course_code']?.toString() ?? '');
  late final _year = TextEditingController(text: widget.item?['year']?.toString() ?? '');
  late final _stage = TextEditingController(text: widget.item?['stage']?.toString() ?? '');
  late final _hours = TextEditingController(text: widget.item?['credit_hours']?.toString() ?? '');
  late final _classroom = TextEditingController(text: widget.item?['classroom']?.toString() ?? '');
  late final _drive = TextEditingController(text: widget.item?['lecture_drive_link']?.toString() ?? '');
  late final _description = TextEditingController(text: widget.item?['description']?.toString() ?? '');
  late int? _departmentId = widget.item?['department_id'] as int?;
  late String? _semester = widget.item?['semester']?.toString();
  late String? _book = widget.item?['course_book']?.toString();
  late String? _bookUrl = widget.item?['course_book_url']?.toString();

  @override
  Map<String, dynamic>? get item => widget.item;

  @override
  String get basePath => '/teacher/teachings';

  @override
  void dispose() {
    for (final c in [_subject, _code, _year, _stage, _hours, _classroom, _drive, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    submit({
      'subject': _subject.text.trim(),
      'course_code': _code.text.trim(),
      'department_id': _departmentId,
      'semester': _semester,
      'year': _year.text.trim(),
      'stage': _stage.text.trim(),
      'credit_hours': int.tryParse(_hours.text.trim()),
      'classroom': _classroom.text.trim(),
      'lecture_drive_link': _drive.text.trim(),
      'description': _description.text.trim(),
    });
  }

  Future<void> _uploadBook() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = picked.firstOrNull?.path;
    if (path == null) return;
    setState(() => busy = true);
    try {
      final body = await api.upload('$basePath/${item!['id']}/book', 'course_book', path);
      final data = Map<String, dynamic>.from(body['data'] as Map);
      setState(() {
        _book = data['course_book']?.toString();
        _bookUrl = data['course_book_url']?.toString();
      });
    } catch (e) {
      if (mounted) setState(() => error = errorText(context, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _removeBook() async {
    setState(() => busy = true);
    try {
      await api.delete('$basePath/${item!['id']}/book');
      setState(() {
        _book = null;
        _bookUrl = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = errorText(context, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? _url(String? v) => (v ?? '').trim().isEmpty || Uri.tryParse(v!.trim())?.hasAbsolutePath == true ? null : S.of(context).t('invalid_url');

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return _WithOptions(
      builder: (context, options) {
        final departments = (options['departments'] as List? ?? []).map((d) => Map<String, dynamic>.from(d as Map)).toList();
        final semesters = Map<String, dynamic>.from(options['semesters'] as Map? ?? {});
        return Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _subject,
                decoration: InputDecoration(labelText: s.t('subject'), prefixIcon: const Icon(Icons.menu_book_outlined)),
                validator: (v) => (v ?? '').trim().isEmpty ? s.t('required') : null,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _code,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: s.t('course_code')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _hours,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: s.t('credit_hours')),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: departments.any((d) => d['id'] == _departmentId) ? _departmentId : null,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.t('department'), prefixIcon: const Icon(Icons.account_tree_outlined)),
                items: [for (final d in departments) DropdownMenuItem(value: d['id'] as int, child: Text(d['name'].toString(), overflow: TextOverflow.ellipsis))],
                validator: (v) => v == null ? s.t('required') : null,
                onChanged: (v) => setState(() => _departmentId = v),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: semesters.containsKey(_semester) ? _semester : null,
                    decoration: InputDecoration(labelText: s.t('semester')),
                    items: [for (final e in semesters.entries) DropdownMenuItem(value: e.key, child: Text('${e.key} · ${e.value}'))],
                    onChanged: (v) => setState(() => _semester = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _year,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: s.t('year'), hintText: '2025-2026'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stage,
                decoration: InputDecoration(labelText: s.t('stage'), prefixIcon: const Icon(Icons.stairs_outlined)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _classroom,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: s.t('classroom_link'), prefixIcon: const Icon(Icons.link)),
                validator: _url,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _drive,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: s.t('lecture_link'), prefixIcon: const Icon(Icons.cloud_outlined)),
                validator: _url,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(labelText: s.t('description'), alignLabelWithHint: true),
              ),
              if (item != null) ...[
                const SizedBox(height: 16),
                Text(s.t('course_book'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: Text(_book ?? s.t('no_file_pdf'),
                        textDirection: _book == null ? null : TextDirection.ltr,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: _book == null ? Theme.of(context).hintColor : null)),
                  ),
                  if (_bookUrl != null)
                    IconButton(onPressed: () => launchUrl(Uri.parse(_bookUrl!), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new, size: 20)),
                  IconButton(onPressed: busy ? null : _uploadBook, icon: const Icon(Icons.upload_file, size: 20)),
                  if (_book != null) IconButton(onPressed: busy ? null : _removeBook, icon: Icon(Icons.delete_outline, size: 20, color: Theme.of(context).colorScheme.error)),
                ]),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(s.t('book_after_save'), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                ),
              actions(context, _save),
            ],
          ),
        );
      },
    );
  }
}

/* ------------------------------------------------------------------ research */

class ResearchForm extends StatefulWidget {
  const ResearchForm({super.key, this.item});

  final Map<String, dynamic>? item;

  @override
  State<ResearchForm> createState() => _ResearchFormState();
}

class _ResearchFormState extends State<ResearchForm> with _PortfolioFormState {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.item?['title']?.toString() ?? '');
  late final _field = TextEditingController(text: widget.item?['field']?.toString() ?? '');
  late final _link = TextEditingController(text: widget.item?['link']?.toString() ?? '');
  late final _doi = TextEditingController(text: widget.item?['doi']?.toString() ?? '');
  late String? _status = widget.item?['status']?.toString();
  late String? _type = widget.item?['type_journal']?.toString();
  late final List<Map<String, dynamic>> _coAuthors =
      (widget.item?['co_authors'] as List? ?? []).map((c) => Map<String, dynamic>.from(c as Map)).toList();
  late String? _acceptance = widget.item?['acceptance_document_url']?.toString();
  late String? _approval = widget.item?['dept_approval_document_url']?.toString();

  @override
  Map<String, dynamic>? get item => widget.item;

  @override
  String get basePath => '/teacher/researches';

  @override
  void dispose() {
    for (final c in [_title, _field, _link, _doi]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    submit({
      'title': _title.text.trim(),
      'field': _field.text.trim(),
      'link': _link.text.trim(),
      'doi': _doi.text.trim(),
      'status': _status,
      'type_journal': _type,
      'co_authors_teacher_ids': [for (final c in _coAuthors) c['id']],
    });
  }

  Future<void> _addCoAuthor() async {
    final picked = await showPickerSheet(
      context,
      title: S.of(context).t('co_authors'),
      load: (search) async {
        final body = await api.get('/teacher/colleagues', {if (search.isNotEmpty) 'search': search});
        return (body['data'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .where((r) => !_coAuthors.any((c) => c['id'] == r['id']))
            .toList();
      },
      label: teacherName,
      sublabel: (row) => row['department']?.toString() ?? '',
    );
    if (picked != null) setState(() => _coAuthors.add(picked));
  }

  Future<void> _uploadDocument(String kind) async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = picked.firstOrNull?.path;
    if (path == null) return;
    setState(() => busy = true);
    try {
      final body = await api.upload('$basePath/${item!['id']}/document', 'document', path, fields: {'kind': kind});
      _applyDocs(body);
    } catch (e) {
      if (mounted) setState(() => error = errorText(context, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _removeDocument(String kind) async {
    setState(() => busy = true);
    try {
      final body = await api.delete('$basePath/${item!['id']}/document', {'kind': kind});
      _applyDocs(body);
    } catch (e) {
      if (mounted) setState(() => error = errorText(context, e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _applyDocs(dynamic body) {
    final data = Map<String, dynamic>.from(body['data'] as Map);
    setState(() {
      _acceptance = data['acceptance_document_url']?.toString();
      _approval = data['dept_approval_document_url']?.toString();
    });
  }

  String? _url(String? v) => (v ?? '').trim().isEmpty || Uri.tryParse(v!.trim())?.hasAbsolutePath == true ? null : S.of(context).t('invalid_url');

  Widget _document(BuildContext context, String kind, String label, String? url) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(url == null ? Icons.upload_file_outlined : Icons.picture_as_pdf_outlined, size: 20, color: url == null ? scheme.outline : scheme.primary),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
      if (url != null) IconButton(onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new, size: 20)),
      IconButton(tooltip: s.t('upload_cv'), onPressed: busy ? null : () => _uploadDocument(kind), icon: const Icon(Icons.upload_file, size: 20)),
      if (url != null) IconButton(onPressed: busy ? null : () => _removeDocument(kind), icon: Icon(Icons.delete_outline, size: 20, color: scheme.error)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return _WithOptions(
      builder: (context, options) {
        final statuses = _strings(options, 'research_statuses');
        final types = _strings(options, 'journal_types');
        return Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _title,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: s.t('research_title'), prefixIcon: const Icon(Icons.science_outlined)),
                validator: (v) => (v ?? '').trim().isEmpty ? s.t('required') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _field,
                decoration: InputDecoration(labelText: s.t('research_field'), prefixIcon: const Icon(Icons.category_outlined)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: statuses.contains(_status) ? _status : null,
                    decoration: InputDecoration(labelText: s.t('status')),
                    items: [for (final v in statuses) DropdownMenuItem(value: v, child: Text(s.t('research_$v')))],
                    onChanged: (v) => setState(() => _status = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: types.contains(_type) ? _type : null,
                    decoration: InputDecoration(labelText: s.t('journal_type')),
                    items: [for (final v in types) DropdownMenuItem(value: v, child: Text(s.t('journal_$v')))],
                    onChanged: (v) => setState(() => _type = v),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _link,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: s.t('research_link'), prefixIcon: const Icon(Icons.link)),
                validator: _url,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _doi,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'DOI', hintText: 'https://doi.org/…', prefixIcon: Icon(Icons.fingerprint)),
                validator: _url,
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Text(s.t('co_authors'), style: Theme.of(context).textTheme.titleSmall)),
                TextButton.icon(onPressed: _addCoAuthor, icon: const Icon(Icons.person_add_alt, size: 18), label: Text(s.t('add'))),
              ]),
              if (_coAuthors.isEmpty)
                Text(s.t('no_co_authors'), style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in _coAuthors)
                      InputChip(
                        label: Text(teacherName(c)),
                        onDeleted: () => setState(() => _coAuthors.remove(c)),
                      ),
                  ],
                ),
              if (item != null) ...[
                const SizedBox(height: 16),
                Text(s.t('documents'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                _document(context, 'acceptance', s.t('acceptance_document'), _acceptance),
                _document(context, 'dept_approval', s.t('dept_approval_document'), _approval),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(s.t('docs_after_save'), style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                ),
              actions(context, _save),
            ],
          ),
        );
      },
    );
  }
}
