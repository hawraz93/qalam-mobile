import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'push.dart';
import 'screens/complaints.dart';
import 'screens/contacts.dart';
import 'screens/inbox.dart';
import 'screens/ticket_form.dart';
import 'screens/tickets.dart';
import 'screens/web_page.dart';
import 'strings.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  S.useDeviceLanguage(PlatformDispatcher.instance.locale.languageCode);
  await Push.init();
  runApp(const QalamApp());
}

class QalamApp extends StatelessWidget {
  const QalamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Al-Qalam Alerts',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brandColor),
      ),
      // Kurdish uses the Arabic Material locale (right-to-left); the app's own texts come from S.
      locale: S.isRtl ? const Locale('ar') : const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const Gate(),
    );
  }
}

/// Decides between the sign-in screen and the app.
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  bool _checking = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    api.onSignedOut = () {
      if (mounted) setState(() {});
    };
    _restore();
  }

  Future<void> _restore() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await api.restore();
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(body: ErrorView(error: _error!, onRetry: _restore));
    }
    if (!api.isSignedIn) {
      return LoginScreen(onSignedIn: () => setState(() {}));
    }
    return HomeScreen(onSignedOut: () => setState(() {}));
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _guestTickets = false;

  @override
  void initState() {
    super.initState();
    // Offer "ticket without signing in" only while the admin allows it
    api.ticketsRequireLogin().then((required) {
      if (mounted) setState(() => _guestTickets = !required);
    });
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_login.text.trim().isEmpty || _password.text.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await api.login(_login.text.trim(), _password.text, 'Al-Qalam app');
      widget.onSignedIn();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Image.asset('assets/logo.png', height: 120),
                  const SizedBox(height: 12),
                  Text(s.t('app'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _login,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: s.t('login_field'), border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    textDirection: TextDirection.ltr,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(labelText: s.t('password'), border: const OutlineInputBorder()),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(s.t('login')),
                    ),
                  ),
                  if (_guestTickets) ...[
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TicketFormScreen()),
                      ),
                      icon: const Icon(Icons.support_agent),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(s.t('guest_ticket'), textAlign: TextAlign.center),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Explains why pushes would not show (or stay silent) on this phone, with a button to the fix.
class PushWarning extends StatelessWidget {
  const PushWarning({super.key, required this.health, this.onSkip});

  final PushHealth health;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    final (String text, IconData icon, Color background, Color foreground) = switch (health.problem) {
      PushProblem.blocked => (s.t('push_blocked'), Icons.notifications_off_outlined, scheme.errorContainer, scheme.onErrorContainer),
      PushProblem.silent => (s.t('push_silent'), Icons.volume_off_outlined, Colors.orange.shade100, Colors.orange.shade900),
      PushProblem.phoneMuted => (s.t('push_phone_muted'), Icons.vibration, Colors.orange.shade100, Colors.orange.shade900),
      PushProblem.battery => (s.t('push_battery'), Icons.battery_alert_outlined, Colors.amber.shade100, Colors.brown.shade800),
      _ => (s.t('push_unavailable'), Icons.cloud_off_outlined, scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    final actions = <Widget>[
      switch (health.problem) {
        PushProblem.blocked => TextButton(
            onPressed: () => Push.openNotificationSettings(),
            child: Text(s.t('open_settings')),
          ),
        PushProblem.silent => TextButton(
            onPressed: () => Push.openNotificationSettings(channel: true),
            child: Text(s.t('open_settings')),
          ),
        PushProblem.phoneMuted => TextButton(
            onPressed: Push.openSoundSettings,
            child: Text(s.t('open_settings')),
          ),
        PushProblem.battery => TextButton(
            onPressed: Push.allowBackground,
            child: Text(s.t('allow_background')),
          ),
        _ => const SizedBox.shrink(),
      },
      if (health.problem == PushProblem.battery && health.hasAutostartPage)
        TextButton(onPressed: Push.openAutostartSettings, child: Text(s.t('autostart'))),
      if (onSkip != null) TextButton(onPressed: onSkip, child: Text(s.t('later'))),
    ];

    return Material(
      color: background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: TextStyle(color: foreground, height: 1.4))),
              ],
            ),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ),
      ),
    );
  }
}

class _Section {
  _Section(this.key, this.icon, this.body, {this.badge});

  final String key;
  final IconData icon;
  final Widget body;
  final int? badge;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _inbox = GlobalKey<InboxTabState>();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Map<String, dynamic> _summary = {};
  int _index = 0;
  PushHealth _health = const PushHealth(PushProblem.none);

  /// The battery warning is advice, not a blocker: once skipped it stays hidden this session.
  static bool _batteryWarningSkipped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Push.registerDevice().then((_) => _checkPushHealth());
    _subscriptions.add(Push.foreground.stream.listen((message) {
      _loadSummary();
      _inbox.currentState?.refresh();
      if (mounted) {
        toast(context, message.notification?.title ?? S.of(context).t('new_push'));
      }
    }));
    _subscriptions.add(Push.opened.stream.listen(_openTarget));
    Push.initialTarget().then((target) {
      if (target != null) _openTarget(target);
    });

    _loadSummary();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSummary();
      _inbox.currentState?.refresh();
      // The user may just have come back from the settings page the warning opened
      _checkPushHealth();
    }
  }

  Future<void> _checkPushHealth() async {
    final health = await Push.health();
    if (mounted) setState(() => _health = health);
  }

  Future<void> _openTarget(PushTarget target) async {
    if (!mounted) return;
    await openTarget(context, target);
    _loadSummary();
    _inbox.currentState?.refresh();
  }

  Future<void> _loadSummary() async {
    try {
      final body = await api.get('/summary');
      if (mounted) setState(() => _summary = Map<String, dynamic>.from(body as Map));
    } catch (_) {
      // Badges are a nicety; the lists report their own errors
    }
  }

  Future<void> _logout() async {
    await api.logout(deviceToken: Push.deviceToken);
    widget.onSignedOut();
  }

  /// Raw phone-side notification state plus a local test notification, for troubleshooting sound.
  Future<void> _showPushCheck() async {
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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    final sections = <_Section>[
      _Section('inbox', Icons.notifications_none, InboxTab(key: _inbox, onChanged: _loadSummary),
          badge: _summary['unread_notifications'] as int?),
      if (api.can('it_tickets'))
        _Section('tickets', Icons.confirmation_number_outlined, const AdminTicketsTab(),
            badge: _summary['it_tickets'] as int?),
      if (api.can('complaints'))
        _Section('complaints', Icons.campaign_outlined, const ComplaintsTab(), badge: _summary['complaints'] as int?),
      if (api.can('contacts'))
        _Section('contacts', Icons.mail_outline, const ContactsTab(), badge: _summary['contacts'] as int?),
      _Section('my_tickets', Icons.person_outline, const MyTicketsTab(),
          badge: _summary['my_open_tickets'] as int?),
    ];

    final index = _index.clamp(0, sections.length - 1).toInt();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.t(sections[index].key)),
        actions: [
          PopupMenuButton<String>(
            tooltip: s.t('menu'),
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
                return;
              }
              if (value == 'push_check') {
                _showPushCheck();
                return;
              }
              final link = api.webLinks.firstWhere((link) => link['path'] == value);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => WebPageScreen(path: value, title: s.t(link['key'].toString())),
              ));
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Text(api.user?['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const PopupMenuDivider(),
              // Teacher portfolio pages and the account page, opened from the website signed in
              for (final link in api.webLinks)
                PopupMenuItem<String>(value: link['path'].toString(), child: Text(s.t(link['key'].toString()))),
              const PopupMenuDivider(),
              PopupMenuItem<String>(value: 'push_check', child: Text(s.t('push_check'))),
              PopupMenuItem<String>(value: 'logout', child: Text(s.t('logout'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_health.problem != PushProblem.none &&
              !(_health.problem == PushProblem.battery && _batteryWarningSkipped))
            PushWarning(
              health: _health,
              onSkip: _health.problem == PushProblem.battery
                  ? () => setState(() => _batteryWarningSkipped = true)
                  : null,
            ),
          Expanded(
            child: IndexedStack(
              index: index,
              children: [for (final section in sections) section.body],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          _loadSummary();
        },
        destinations: [
          for (final section in sections)
            NavigationDestination(
              icon: Badge(
                isLabelVisible: (section.badge ?? 0) > 0,
                label: Text('${section.badge ?? 0}'),
                child: Icon(section.icon),
              ),
              label: s.t(section.key),
            ),
        ],
      ),
    );
  }
}
