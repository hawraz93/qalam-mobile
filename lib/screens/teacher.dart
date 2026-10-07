import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'portfolio.dart';
import 'web_page.dart';

/// The teacher's academic profile, edited natively: photo, details, biography, CV, office hours.
/// Education, teaching and research still open the website pages (signed in).
class TeacherProfileScreen extends StatefulWidget {
  const TeacherProfileScreen({super.key});

  @override
  State<TeacherProfileScreen> createState() => _TeacherProfileScreenState();
}

class _TeacherProfileScreenState extends State<TeacherProfileScreen> {
  Map<String, dynamic>? _teacher;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final body = await api.get('/teacher');
      if (mounted) setState(() => _teacher = Map<String, dynamic>.from(body['data'] as Map));
      // The account tab shows the same photo and completion
      api.refreshProfile().catchError((_) {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _apply(dynamic body) {
    if (mounted) setState(() => _teacher = Map<String, dynamic>.from(body['data'] as Map));
    api.refreshProfile().catchError((_) {});
  }

  Future<void> _run(Future<dynamic> Function() action, {String doneKey = 'saved'}) async {
    setState(() => _busy = true);
    try {
      final body = await action();
      if (body != null) _apply(body);
      if (mounted) toast(context, S.of(context).t(doneKey));
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePhoto() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    final path = picked.firstOrNull?.path;
    if (path == null) return;
    await _run(() => api.upload('/teacher/photo', 'photo', path), doneKey: 'photo_updated');
  }

  Future<void> _removePhoto() async {
    if (!await _confirm(S.of(context).t('remove_photo'))) return;
    await _run(() => api.delete('/teacher/photo'));
  }

  Future<void> _uploadCv() async {
    final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'doc', 'docx']);
    final path = picked.firstOrNull?.path;
    if (path == null) return;
    await _run(() => api.upload('/teacher/cv', 'cv', path), doneKey: 'cv_updated');
  }

  Future<void> _removeCv() async {
    if (!await _confirm(S.of(context).t('remove_cv'))) return;
    await _run(() => api.delete('/teacher/cv'));
  }

  Future<void> _openCv() async {
    final url = _teacher?['cv_url']?.toString();
    if (url == null) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) toast(context, S.of(context).t('cannot_open'));
  }

  Future<bool> _confirm(String question) async {
    final s = S.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            content: Text(question),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.t('cancel'))),
              FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.t('yes'))),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _editDetails() async {
    final body = await showFormSheet<dynamic>(context, title: S.of(context).t('edit_details'), child: _DetailsForm(teacher: _teacher!));
    if (body != null) {
      _apply(body);
      if (mounted) toast(context, S.of(context).t('saved'));
    }
  }

  Future<void> _editLinks() async {
    final body = await showFormSheet<dynamic>(context, title: S.of(context).t('research_links'), child: _LinksForm(teacher: _teacher!));
    if (body != null) {
      _apply(body);
      if (mounted) toast(context, S.of(context).t('saved'));
    }
  }

  Future<void> _editBiography() async {
    final body = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(builder: (_) => _BiographyScreen(initial: _teacher?['biography']?.toString() ?? '')),
    );
    if (body != null) {
      _apply(body);
      if (mounted) toast(context, S.of(context).t('saved'));
    }
  }

  Future<void> _editOfficeHours() async {
    final body = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(builder: (_) => _OfficeHoursScreen(teacher: _teacher!)),
    );
    if (body != null) {
      _apply(body);
      if (mounted) toast(context, S.of(context).t('saved'));
    }
  }

  void _openList(PortfolioKind kind) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PortfolioListScreen(kind: kind)))
        .then((_) => _load());
  }

  void _openWeb(String path, String titleKey) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => WebPageScreen(path: path, title: S.of(context).t(titleKey))))
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final t = _teacher;

    if (t == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.t('academic_profile'))),
        body: _error != null ? ErrorView(error: _error!, onRetry: _load) : const SkeletonList(rows: 5),
      );
    }

    final checklist = Map<String, dynamic>.from(t['checklist'] as Map? ?? {});
    final counts = Map<String, dynamic>.from(t['counts'] as Map? ?? {});
    final completion = (t['completion'] as int?) ?? 0;
    final hours = (t['office_hours'] as List? ?? []).map((h) => Map<String, dynamic>.from(h as Map)).toList();
    final name = (S.current == 'en' ? t['name_en'] : t['name_ar'])?.toString() ?? '';

    // Checklist rows: what the university asks every teacher to fill in
    final steps = <(String key, String label, IconData icon, VoidCallback action)>[
      ('basic_info', s.t('step_basic_info'), Icons.badge_outlined, _editDetails),
      ('academic_info', s.t('step_academic_info'), Icons.workspace_premium_outlined, _editDetails),
      ('specialty', s.t('step_specialty'), Icons.psychology_outlined, _editDetails),
      ('profile_picture', s.t('step_photo'), Icons.photo_camera_outlined, _changePhoto),
      ('biography', s.t('step_biography'), Icons.article_outlined, _editBiography),
      ('cv', s.t('step_cv'), Icons.picture_as_pdf_outlined, _uploadCv),
      ('educations', s.t('education'), Icons.school_outlined, () => _openList(PortfolioKind.education)),
      ('teachings', s.t('teaching'), Icons.menu_book_outlined, () => _openList(PortfolioKind.teaching)),
      ('researches', s.t('research'), Icons.science_outlined, () => _openList(PortfolioKind.research)),
      ('social_links', s.t('research_links'), Icons.link, _editLinks),
    ];
    final missing = steps.where((step) => checklist[step.$1] != true).toList();

    return Scaffold(
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  expandedHeight: 250,
                  backgroundColor: brandColor,
                  foregroundColor: Colors.white,
                  title: Text(s.t('academic_profile'), style: const TextStyle(color: Colors.white)),
                  actions: [
                    IconButton(
                      tooltip: s.t('open_on_website'),
                      onPressed: () => _openWeb('/teacher-profile', 'academic_profile'),
                      icon: const Icon(Icons.open_in_browser),
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(gradient: brandGradient(context)),
                      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 56, 20, 20),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              Avatar(name: name, url: t['avatar']?.toString(), size: 96, onBrand: true),
                              PositionedDirectional(
                                end: 0,
                                bottom: 0,
                                child: Material(
                                  color: Colors.white,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _busy ? null : _changePhoto,
                                    child: const Padding(
                                      padding: EdgeInsets.all(7),
                                      child: Icon(Icons.photo_camera, size: 18, color: brandColor),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(
                                  [t['academic_title'], t['department']].where((v) => v != null && v.toString().isNotEmpty && v != 'No Title').join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                                ),
                                const SizedBox(height: 10),
                                Row(children: [
                                  _HeaderStat(icon: Icons.visibility_outlined, value: '${t['views'] ?? 0}'),
                                  const SizedBox(width: 12),
                                  _HeaderStat(icon: Icons.download_outlined, value: '${t['cv_downloads'] ?? 0}'),
                                ]),
                                if (t['avatar'] != null)
                                  TextButton(
                                    onPressed: _busy ? null : _removePhoto,
                                    style: TextButton.styleFrom(foregroundColor: Colors.white70, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                                    child: Text(s.t('remove_photo_short'), style: const TextStyle(fontSize: 11.5)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Completion
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(s.t('profile_completion'), style: Theme.of(context).textTheme.titleMedium)),
                                Text('$completion%', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: completion == 100 ? statusColor('resolved') : scheme.primary)),
                              ]),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(value: completion / 100, minHeight: 10),
                              ),
                              const SizedBox(height: 12),
                              if (missing.isEmpty)
                                Row(children: [
                                  Icon(Icons.verified, color: statusColor('resolved')),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(s.t('profile_complete'), style: const TextStyle(fontWeight: FontWeight.w600))),
                                ])
                              else ...[
                                Text(s.t('still_missing'), style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                                const SizedBox(height: 6),
                                for (final step in missing)
                                  InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: _busy ? null : step.$4,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                                      child: Row(children: [
                                        Icon(Icons.radio_button_unchecked, size: 20, color: scheme.outline),
                                        const SizedBox(width: 10),
                                        Icon(step.$3, size: 18, color: scheme.primary),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(step.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
                                        Icon(Icons.chevron_right, size: 18, color: scheme.outline, textDirection: textDirectionFor(context)),
                                      ]),
                                    ),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Details
                      SectionTitle(s.t('academic_info'), action: s.t('edit'), onAction: _busy ? null : _editDetails),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Column(children: [
                            InfoRow(s.t('name_ar'), t['name_ar'], icon: Icons.translate),
                            InfoRow(s.t('name_en'), t['name_en'], icon: Icons.translate),
                            InfoRow(s.t('gender'), t['gender'] == null ? null : s.t(t['gender'].toString()), icon: Icons.wc),
                            InfoRow(s.t('phone'), t['phone'], icon: Icons.phone_outlined),
                            InfoRow(s.t('address'), t['address'], icon: Icons.place_outlined),
                            InfoRow(s.t('department'), t['department'], icon: Icons.account_tree_outlined),
                            InfoRow(s.t('academic_title'), t['academic_title'], icon: Icons.workspace_premium_outlined),
                            InfoRow(s.t('degree'), t['degree'], icon: Icons.school_outlined),
                            InfoRow(s.t('specialty'), t['general_specialty'], icon: Icons.psychology_outlined),
                            InfoRow(s.t('specific_specialty'), t['specific_specialty'], icon: Icons.psychology_alt_outlined),
                          ]),
                        ),
                      ),

                      // Biography
                      SectionTitle(s.t('biography'), action: s.t('edit'), onAction: _busy ? null : _editBiography),
                      Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: _busy ? null : _editBiography,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: (t['biography']?.toString() ?? '').trim().isEmpty
                                ? Text(s.t('biography_empty'), style: TextStyle(color: scheme.onSurfaceVariant))
                                : Text(t['biography'].toString(), maxLines: 8, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.6)),
                          ),
                        ),
                      ),

                      // CV
                      SectionTitle(s.t('cv')),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                                  child: Icon(t['cv_url'] == null ? Icons.upload_file_outlined : Icons.picture_as_pdf_outlined, color: scheme.primary),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    t['cv_url'] == null ? s.t('cv_empty') : t['cv_name'].toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textDirection: t['cv_url'] == null ? null : TextDirection.ltr,
                                    style: TextStyle(fontWeight: FontWeight.w600, color: t['cv_url'] == null ? scheme.onSurfaceVariant : null),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 12),
                              Row(children: [
                                if (t['cv_url'] != null) ...[
                                  Expanded(child: OutlinedButton.icon(onPressed: _openCv, icon: const Icon(Icons.open_in_new, size: 18), label: Text(s.t('open_page')))),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _busy ? null : _uploadCv,
                                    icon: const Icon(Icons.upload, size: 18),
                                    label: Text(s.t(t['cv_url'] == null ? 'upload_cv' : 'replace_cv')),
                                  ),
                                ),
                                if (t['cv_url'] != null)
                                  IconButton(onPressed: _busy ? null : _removeCv, icon: Icon(Icons.delete_outline, color: scheme.error)),
                              ]),
                            ],
                          ),
                        ),
                      ),

                      // Office hours
                      SectionTitle(s.t('office_hours'), action: s.t('edit'), onAction: _busy ? null : _editOfficeHours),
                      Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: _busy ? null : _editOfficeHours,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: hours.isEmpty
                                ? Text(s.t('office_hours_empty'), style: TextStyle(color: scheme.onSurfaceVariant))
                                : Column(children: [
                                    for (final slot in hours)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 5),
                                        child: Row(children: [
                                          Icon(Icons.schedule, size: 18, color: scheme.primary),
                                          const SizedBox(width: 10),
                                          SizedBox(width: 80, child: Text(dayLabel(s, slot['day']?.toString()), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
                                          Expanded(
                                            child: Text('${slot['from']} – ${slot['to']}${(slot['location'] ?? '').toString().isNotEmpty ? ' · ${slot['location']}' : ''}',
                                                style: const TextStyle(fontSize: 13)),
                                          ),
                                        ]),
                                      ),
                                  ]),
                          ),
                        ),
                      ),

                      // Portfolio lists on the website
                      SectionTitle(s.t('portfolio')),
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(children: [
                          MenuRow(icon: Icons.school_outlined, title: s.t('education'), value: '${counts['educations'] ?? 0}', onTap: () => _openList(PortfolioKind.education)),
                          const Divider(indent: 52),
                          MenuRow(icon: Icons.menu_book_outlined, title: s.t('teaching'), value: '${counts['teachings'] ?? 0}', onTap: () => _openList(PortfolioKind.teaching)),
                          const Divider(indent: 52),
                          MenuRow(icon: Icons.science_outlined, title: s.t('research'), value: '${counts['researches'] ?? 0}', onTap: () => _openList(PortfolioKind.research)),
                          const Divider(indent: 52),
                          MenuRow(icon: Icons.link, title: s.t('research_links'), value: _linksSummary(t), onTap: _busy ? null : _editLinks),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.25),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  String _linksSummary(Map<String, dynamic> t) {
    final n = ['orcid_id', 'google_scholar_url', 'researchgate_url'].where((k) => (t[k] ?? '').toString().isNotEmpty).length;
    return '$n/3';
  }
}

/// Days are stored in Arabic (the website prints them as-is); shown in the app language.
String dayLabel(S s, String? day) {
  const keys = {
    'السبت': 'sat', 'الأحد': 'sun', 'الاثنين': 'mon', 'الثلاثاء': 'tue', 'الأربعاء': 'wed', 'الخميس': 'thu', 'الجمعة': 'fri',
  };
  final key = keys[day];
  return key == null ? (day ?? '') : s.t('day_$key');
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 15, color: Colors.white70),
      const SizedBox(width: 4),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// Name, contact, title, degree, specialty.
class _DetailsForm extends StatefulWidget {
  const _DetailsForm({required this.teacher});

  final Map<String, dynamic> teacher;

  @override
  State<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends State<_DetailsForm> {
  final _form = GlobalKey<FormState>();
  late final _nameAr = TextEditingController(text: widget.teacher['name_ar']?.toString() ?? '');
  late final _nameEn = TextEditingController(text: widget.teacher['name_en']?.toString() ?? '');
  late final _phone = TextEditingController(text: widget.teacher['phone']?.toString() ?? '');
  late final _address = TextEditingController(text: widget.teacher['address']?.toString() ?? '');
  late final _general = TextEditingController(text: widget.teacher['general_specialty']?.toString() ?? '');
  late final _specific = TextEditingController(text: widget.teacher['specific_specialty']?.toString() ?? '');
  late String? _gender = widget.teacher['gender']?.toString();
  late String? _title = widget.teacher['academic_title']?.toString();
  late String? _degree = widget.teacher['degree']?.toString();
  bool _busy = false;
  String? _error;

  List<String> _options(String key) => (widget.teacher['options']?[key] as List? ?? []).map((v) => v.toString()).toList();

  @override
  void dispose() {
    for (final c in [_nameAr, _nameEn, _phone, _address, _general, _specific]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await api.patch('/teacher', {
        'name_ar': _nameAr.text.trim(),
        'name_en': _nameEn.text.trim(),
        'gender': _gender,
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'academic_title': _title,
        'degree': _degree,
        'general_specialty': _general.text.trim(),
        'specific_specialty': _specific.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(body);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final titles = _options('titles');
    final degrees = _options('degrees');

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameAr,
            decoration: InputDecoration(labelText: s.t('name_ar'), prefixIcon: const Icon(Icons.translate)),
            validator: (v) => (v ?? '').trim().length < 2 ? s.t('required') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameEn,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: s.t('name_en'), prefixIcon: const Icon(Icons.translate)),
            validator: (v) => (v ?? '').trim().length < 2 ? s.t('required') : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _gender,
            decoration: InputDecoration(labelText: s.t('gender'), prefixIcon: const Icon(Icons.wc)),
            items: [for (final g in const ['male', 'female']) DropdownMenuItem(value: g, child: Text(s.t(g)))],
            onChanged: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: s.t('phone'), prefixIcon: const Icon(Icons.phone_outlined)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _address,
            decoration: InputDecoration(labelText: s.t('address'), prefixIcon: const Icon(Icons.place_outlined)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: titles.contains(_title) ? _title : null,
            decoration: InputDecoration(labelText: s.t('academic_title'), prefixIcon: const Icon(Icons.workspace_premium_outlined)),
            items: [for (final t in titles) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _title = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: degrees.contains(_degree) ? _degree : null,
            decoration: InputDecoration(labelText: s.t('degree'), prefixIcon: const Icon(Icons.school_outlined)),
            items: [for (final d in degrees) DropdownMenuItem(value: d, child: Text(d))],
            onChanged: (v) => setState(() => _degree = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _general,
            decoration: InputDecoration(labelText: s.t('specialty'), prefixIcon: const Icon(Icons.psychology_outlined)),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _specific,
            decoration: InputDecoration(labelText: s.t('specific_specialty'), prefixIcon: const Icon(Icons.psychology_alt_outlined)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('save')),
          ),
        ],
      ),
    );
  }
}

/// ORCID, Google Scholar, ResearchGate.
class _LinksForm extends StatefulWidget {
  const _LinksForm({required this.teacher});

  final Map<String, dynamic> teacher;

  @override
  State<_LinksForm> createState() => _LinksFormState();
}

class _LinksFormState extends State<_LinksForm> {
  late final _orcid = TextEditingController(text: widget.teacher['orcid_id']?.toString() ?? '');
  late final _scholar = TextEditingController(text: widget.teacher['google_scholar_url']?.toString() ?? '');
  late final _gate = TextEditingController(text: widget.teacher['researchgate_url']?.toString() ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_orcid, _scholar, _gate]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await api.patch('/teacher', {
        'orcid_id': _orcid.text.trim(),
        'google_scholar_url': _scholar.text.trim(),
        'researchgate_url': _gate.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(body);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _orcid,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'ORCID iD', hintText: '0000-0000-0000-0000', prefixIcon: Icon(Icons.fingerprint)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _scholar,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Google Scholar', hintText: 'https://scholar.google.com/…', prefixIcon: Icon(Icons.school_outlined)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _gate,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'ResearchGate', hintText: 'https://www.researchgate.net/profile/…', prefixIcon: Icon(Icons.hub_outlined)),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(s.t('save')),
        ),
      ],
    );
  }
}

/// Full-screen biography editor with a character counter.
class _BiographyScreen extends StatefulWidget {
  const _BiographyScreen({required this.initial});

  final String initial;

  @override
  State<_BiographyScreen> createState() => _BiographyScreenState();
}

class _BiographyScreenState extends State<_BiographyScreen> {
  late final _text = TextEditingController(text: widget.initial);
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final body = await api.patch('/teacher', {'biography': _text.text.trim()});
      if (mounted) Navigator.of(context).pop(body);
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('biography')),
        actions: [
          TextButton(onPressed: _busy ? null : _save, child: Text(s.t('save'))),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(s.t('biography_hint'), style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _text,
                maxLength: 5000,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(hintText: s.t('biography_placeholder'), alignLabelWithHint: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Weekly office hours: day, from, to, location, notes per slot.
class _OfficeHoursScreen extends StatefulWidget {
  const _OfficeHoursScreen({required this.teacher});

  final Map<String, dynamic> teacher;

  @override
  State<_OfficeHoursScreen> createState() => _OfficeHoursScreenState();
}

class _OfficeHoursScreenState extends State<_OfficeHoursScreen> {
  late final List<String> _days = (widget.teacher['options']?['days'] as List? ?? []).map((d) => d.toString()).toList();
  late final List<Map<String, dynamic>> _slots =
      (widget.teacher['office_hours'] as List? ?? []).map((h) => Map<String, dynamic>.from(h as Map)).toList();
  bool _busy = false;

  void _add() {
    setState(() => _slots.add({
          'day': _days.isNotEmpty ? _days[1 % _days.length] : '',
          'from': '10:00 AM',
          'to': '12:00 PM',
          'location': '',
          'notes': '',
        }));
  }

  Future<void> _pickTime(Map<String, dynamic> slot, String key) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parse(slot[key]?.toString()) ?? const TimeOfDay(hour: 10, minute: 0),
      initialEntryMode: TimePickerEntryMode.dialOnly,
    );
    if (picked != null) setState(() => slot[key] = _format(picked));
  }

  /// "1:30 PM" style, which the website prints as-is.
  String _format(TimeOfDay t) {
    final hour12 = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  TimeOfDay? _parse(String? text) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$', caseSensitive: false).firstMatch((text ?? '').trim());
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)?.toUpperCase();
    if (period == 'PM' && hour < 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;
    return TimeOfDay(hour: hour.clamp(0, 23), minute: minute.clamp(0, 59));
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final body = await api.put('/teacher/office-hours', {'office_hours': _slots});
      if (mounted) Navigator.of(context).pop(body);
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
      appBar: AppBar(
        title: Text(s.t('office_hours')),
        actions: [TextButton(onPressed: _busy ? null : _save, child: Text(s.t('save')))],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: Text(s.t('add_slot'))),
      body: _slots.isEmpty
          ? EmptyState(icon: Icons.schedule, text: s.t('office_hours_empty'))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: _slots.length,
              itemBuilder: (context, index) {
                final slot = _slots[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _days.contains(slot['day']) ? slot['day'].toString() : null,
                                decoration: InputDecoration(labelText: s.t('day'), isDense: true),
                                items: [for (final d in _days) DropdownMenuItem(value: d, child: Text(dayLabel(s, d)))],
                                onChanged: (v) => setState(() => slot['day'] = v),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() => _slots.removeAt(index)),
                              icon: Icon(Icons.delete_outline, color: scheme.error),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickTime(slot, 'from'),
                                icon: const Icon(Icons.schedule, size: 18),
                                label: Text(slot['from']?.toString() ?? '', textDirection: TextDirection.ltr),
                              ),
                            ),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('–')),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _pickTime(slot, 'to'),
                                icon: const Icon(Icons.schedule, size: 18),
                                label: Text(slot['to']?.toString() ?? '', textDirection: TextDirection.ltr),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: slot['location']?.toString() ?? '',
                            decoration: InputDecoration(labelText: s.t('location'), isDense: true, prefixIcon: const Icon(Icons.place_outlined)),
                            onChanged: (v) => slot['location'] = v,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            initialValue: slot['notes']?.toString() ?? '',
                            decoration: InputDecoration(labelText: s.t('notes'), isDense: true, prefixIcon: const Icon(Icons.notes)),
                            onChanged: (v) => slot['notes'] = v,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
