import 'package:flutter/material.dart';

import '../api.dart';
import '../lock.dart';
import '../push.dart';
import '../strings.dart';
import '../theme.dart';
import '../widgets.dart';
import 'notification_prefs.dart';
import 'portfolio.dart';
import 'teacher.dart';
import 'web_page.dart';

/// The signed-in user's account: details, editing, password, website pages, settings.
class AccountTab extends StatefulWidget {
  const AccountTab({super.key, required this.onSignedOut, required this.onLanguageChanged});

  final VoidCallback onSignedOut;
  final VoidCallback onLanguageChanged;

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  bool _busy = false;

  Future<void> _refresh() async {
    try {
      await api.refreshProfile();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) toast(context, errorText(context, e));
    }
  }

  Future<void> _edit() async {
    final saved = await showFormSheet<bool>(context, title: S.of(context).t('edit_profile'), child: const _EditProfileForm());
    if (saved == true && mounted) {
      setState(() {});
      toast(context, S.of(context).t('saved'));
    }
  }

  Future<void> _changePassword() async {
    final changed = await showFormSheet<bool>(context, title: S.of(context).t('change_password'), child: const _PasswordForm());
    if (changed == true && mounted) toast(context, S.of(context).t('password_changed'));
  }

  Future<void> _chooseLanguage() async {
    final s = S.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in const {'ckb': 'lang_ckb', 'ar': 'lang_ar', 'en': 'lang_en'}.entries)
              ListTile(
                leading: Icon(entry.key == S.current ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: Theme.of(context).colorScheme.primary),
                title: Text(s.t(entry.value)),
                onTap: () => Navigator.of(context).pop(entry.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && picked != S.current) {
      S.current = picked;
      await api.writeSetting('lang', picked);
      widget.onLanguageChanged();
    }
  }

  Future<void> _pushCheck() async {
    final s = S.of(context);
    final status = await Push.rawStatus();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('push_check')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in status.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${entry.key}: ${entry.value}',
                      textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Push.showTest(s.t('test_title'), s.t('test_body')),
            child: Text(s.t('send_test')),
          ),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.t('close'))),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final s = S.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.t('logout')),
        content: Text(s.t('confirm_logout')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.t('logout'))),
        ],
      ),
    );
    if (sure != true) return;

    setState(() => _busy = true);
    await api.logout(deviceToken: Push.deviceToken);
    widget.onSignedOut();
  }

  Future<void> _openList(PortfolioKind kind) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PortfolioListScreen(kind: kind)));
    if (mounted) setState(() {});
  }

  Future<void> _openTeacher() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TeacherProfileScreen()));
    if (mounted) setState(() {});
  }

  void _openWeb(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebPageScreen(path: path, title: title)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final user = api.user ?? {};
    final teacher = user['teacher'] as Map?;
    final roles = (user['roles'] as List? ?? []).map((r) => r.toString()).toList();
    final scheme = Theme.of(context).colorScheme;
    final links = api.webLinks;
    final adminLinks = links.where((l) => const ['dashboard', 'notification_settings', 'users'].contains(l['key'])).toList();
    final teacherLinks = links.where((l) => !const ['dashboard', 'notification_settings', 'users', 'account'].contains(l['key'])).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: brandGradient(context),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 20, 20, 24),
            child: Column(
              children: [
                Avatar(name: user['name']?.toString() ?? '', url: user['avatar']?.toString(), size: 88, onBrand: true),
                const SizedBox(height: 12),
                Text(user['name']?.toString() ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(user['email']?.toString() ?? '',
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
                if (roles.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final role in roles)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(role, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(s.t('account_info'), action: s.t('edit'), onAction: _edit),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      children: [
                        InfoRow(s.t('name'), user['name'], icon: Icons.badge_outlined),
                        InfoRow(s.t('email'), user['email'], icon: Icons.alternate_email),
                        InfoRow(s.t('phone'), user['phone'], icon: Icons.phone_outlined),
                        InfoRow(s.t('username'), user['username'], icon: Icons.person_outline),
                        InfoRow(s.t('department'), user['department'], icon: Icons.account_tree_outlined),
                        if (user['created_at'] != null)
                          InfoRow(s.t('member_since'), shortDate(user['created_at']).substring(0, 10), icon: Icons.calendar_today_outlined),
                      ],
                    ),
                  ),
                ),
                if (teacher != null) ...[
                  SectionTitle(s.t('academic_info'), action: s.t('edit'), onAction: _openTeacher),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          InfoRow(s.t('name_ar'), teacher['name_ar'], icon: Icons.translate),
                          InfoRow(s.t('name_en'), teacher['name_en'], icon: Icons.translate),
                          InfoRow(s.t('academic_title'), teacher['academic_title'], icon: Icons.workspace_premium_outlined),
                          InfoRow(s.t('degree'), teacher['degree'], icon: Icons.school_outlined),
                          InfoRow(s.t('specialty'), teacher['specialty'], icon: Icons.psychology_outlined),
                          if (teacher['completion'] != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Icon(Icons.task_alt, size: 18, color: scheme.onSurfaceVariant),
                                  const SizedBox(width: 10),
                                  SizedBox(width: 104, child: Text(s.t('profile_completion'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13))),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: LinearProgressIndicator(value: (teacher['completion'] as int) / 100, minHeight: 8),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('${teacher['completion']}%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (teacherLinks.isNotEmpty) ...[
                  SectionTitle(s.t('academic_pages')),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final link in teacherLinks)
                          MenuRow(
                            icon: switch (link['key']) {
                              'education' => Icons.school_outlined,
                              'teaching' => Icons.menu_book_outlined,
                              'research' => Icons.science_outlined,
                              'biography' => Icons.article_outlined,
                              _ => Icons.account_circle_outlined,
                            },
                            title: s.t(link['key'].toString()),
                            onTap: switch (link['key']) {
                              'academic_profile' => _openTeacher,
                              'education' => () => _openList(PortfolioKind.education),
                              'teaching' => () => _openList(PortfolioKind.teaching),
                              'research' => () => _openList(PortfolioKind.research),
                              _ => () => _openWeb(link['path'].toString(), s.t(link['key'].toString())),
                            },
                          ),
                      ],
                    ),
                  ),
                ],
                if (adminLinks.isNotEmpty) ...[
                  SectionTitle(s.t('admin_pages')),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final link in adminLinks)
                          MenuRow(
                            icon: switch (link['key']) {
                              'users' => Icons.group_outlined,
                              'notification_settings' => Icons.tune,
                              _ => Icons.space_dashboard_outlined,
                            },
                            title: s.t(link['key'].toString()),
                            onTap: () => _openWeb(link['path'].toString(), s.t(link['key'].toString())),
                          ),
                      ],
                    ),
                  ),
                ],
                SectionTitle(s.t('settings')),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      MenuRow(icon: Icons.lock_outline, title: s.t('change_password'), onTap: _changePassword),
                      const Divider(indent: 52),
                      MenuRow(
                        icon: Icons.fingerprint,
                        title: s.t('app_lock'),
                        value: AppLock.enabled ? s.t('active') : null,
                        onTap: () async {
                          await showFormSheet<void>(context, title: s.t('app_lock'), child: const LockSettingsSheet());
                          if (mounted) setState(() {});
                        },
                      ),
                      const Divider(indent: 52),
                      MenuRow(
                        icon: Icons.notifications_outlined,
                        title: s.t('notification_prefs'),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationPrefsScreen())),
                      ),
                      const Divider(indent: 52),
                      MenuRow(icon: Icons.language, title: s.t('language'), value: s.t('lang_${S.current}'), onTap: _chooseLanguage),
                      const Divider(indent: 52),
                      MenuRow(icon: Icons.notifications_active_outlined, title: s.t('push_check'), onTap: _pushCheck),
                      const Divider(indent: 52),
                      MenuRow(icon: Icons.logout, title: s.t('logout'), color: scheme.error, onTap: _busy ? null : _logout),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text('${s.t('app')} · v${S.appVersion}',
                      style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditProfileForm extends StatefulWidget {
  const _EditProfileForm();

  @override
  State<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends State<_EditProfileForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: api.user?['name']?.toString() ?? '');
  late final _email = TextEditingController(text: api.user?['email']?.toString() ?? '');
  late final _phone = TextEditingController(text: api.user?['phone']?.toString() ?? '');
  late final _username = TextEditingController(text: api.user?['username']?.toString() ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _username]) {
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
      await api.updateProfile({
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'username': _username.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: s.t('name'), prefixIcon: const Icon(Icons.badge_outlined)),
            validator: (v) => (v ?? '').trim().length < 2 ? s.t('required') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _email,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: InputDecoration(labelText: s.t('email'), prefixIcon: const Icon(Icons.alternate_email)),
            validator: (v) => (v ?? '').contains('@') ? null : s.t('required'),
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
            controller: _username,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            decoration: InputDecoration(labelText: s.t('username'), prefixIcon: const Icon(Icons.person_outline), helperText: s.t('username_hint')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(s.t('save')),
          ),
        ],
      ),
    );
  }
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm();

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _password, _confirm]) {
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
      await api.post('/me/password', {
        'current_password': _current.text,
        'password': _password.text,
        'password_confirmation': _confirm.text,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final toggle = IconButton(
      icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
      onPressed: () => setState(() => _show = !_show),
    );

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _current,
            obscureText: !_show,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: s.t('current_password'), prefixIcon: const Icon(Icons.lock_outline), suffixIcon: toggle),
            validator: (v) => (v ?? '').isEmpty ? s.t('required') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            obscureText: !_show,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: s.t('new_password'), prefixIcon: const Icon(Icons.key_outlined)),
            validator: (v) => (v ?? '').length < 8 ? s.t('password_short') : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: !_show,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: s.t('confirm_password'), prefixIcon: const Icon(Icons.key_outlined)),
            validator: (v) => v != _password.text ? s.t('passwords_differ') : null,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(s.t('save')),
          ),
        ],
      ),
    );
  }
}
