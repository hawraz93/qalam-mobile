import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'crash.dart';
import 'lock.dart';
import 'push.dart';
import 'screens/account.dart';
import 'screens/home.dart';
import 'screens/inbox.dart';
import 'screens/ticket_form.dart';
import 'screens/work.dart';
import 'strings.dart';
import 'theme.dart';
import 'update.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final saved = await api.readSetting('lang');
  if (saved != null && S.supported.contains(saved)) {
    S.current = saved;
  } else {
    S.useDeviceLanguage(PlatformDispatcher.instance.locale.languageCode);
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await AppLock.load();
  await Push.init();
  await CrashReports.init();
  CrashReports.setUser(api.user);
  runApp(const QalamApp());
}

class QalamApp extends StatefulWidget {
  const QalamApp({super.key});

  /// Rebuilds the whole app after the language changes on the account page.
  static void relaunch(BuildContext context) => context.findAncestorStateOfType<_QalamAppState>()?._bump();

  @override
  State<QalamApp> createState() => _QalamAppState();
}

class _QalamAppState extends State<QalamApp> {
  int _generation = 0;

  void _bump() => setState(() => _generation++);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: ValueKey(_generation),
      title: 'Al-Qalam',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
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
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo.png', height: 96),
              const SizedBox(height: 24),
              const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(body: ErrorView(error: _error!, onRetry: _restore));
    }
    if (!api.isSignedIn) {
      return LoginScreen(onSignedIn: () => setState(() {}));
    }
    return LockGate(child: HomeScreen(onSignedOut: () => setState(() {})));
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
  bool _show = false;
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: brandGradient(context),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
            ),
            padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 40, 24, 36),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                  child: Image.asset('assets/logo.png', height: 84),
                ),
                const SizedBox(height: 18),
                Text(s.t('app'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(s.t('login_subtitle'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _login,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: s.t('login_field'), prefixIcon: const Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      textDirection: TextDirection.ltr,
                      obscureText: !_show,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: s.t('password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                          onPressed: () => setState(() => _show = !_show),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
                        child: Row(children: [
                          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: TextStyle(color: scheme.onErrorContainer, fontSize: 13))),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(s.t('login')),
                    ),
                    if (_guestTickets) ...[
                      const SizedBox(height: 28),
                      Row(children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(s.t('or'), style: TextStyle(color: scheme.outline, fontSize: 12)),
                        ),
                        const Expanded(child: Divider()),
                      ]),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const TicketFormScreen()),
                        ),
                        icon: const Icon(Icons.support_agent),
                        label: Text(s.t('guest_ticket'), textAlign: TextAlign.center),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
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
      PushProblem.silent => (s.t('push_silent'), Icons.volume_off_outlined, const Color(0xFFFFE9C6), const Color(0xFF7A4100)),
      PushProblem.phoneMuted => (s.t('push_phone_muted'), Icons.vibration, const Color(0xFFFFE9C6), const Color(0xFF7A4100)),
      PushProblem.battery => (s.t('push_battery'), Icons.battery_alert_outlined, const Color(0xFFFFF4CC), const Color(0xFF5D4300)),
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
      child: SafeArea(
        bottom: false,
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
                  Expanded(child: Text(text, style: TextStyle(color: foreground, height: 1.4, fontSize: 13.5))),
                ],
              ),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _home = GlobalKey<HomeTabState>();
  final _inbox = GlobalKey<InboxTabState>();
  final _work = GlobalKey<WorkTabState>();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Map<String, dynamic> _summary = {};
  int _index = 0;
  PushHealth _health = const PushHealth(PushProblem.none);
  UpdateInfo? _update;

  /// The battery warning is advice, not a blocker: once skipped it stays hidden this session.
  static bool _batteryWarningSkipped = false;

  static const _tabs = ['home', 'inbox', 'work', 'account'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    Push.registerDevice().then((_) => _checkPushHealth());
    _subscriptions.add(Push.foreground.stream.listen((message) {
      _refreshAll();
      if (mounted) {
        toast(context, message.notification?.title ?? S.of(context).t('new_push'));
      }
    }));
    _subscriptions.add(Push.opened.stream.listen(_openTarget));
    Push.initialTarget().then((target) {
      if (target != null) _openTarget(target);
    });

    _loadSummary();
    _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    final info = await AppUpdate.check();
    if (info == null || !mounted) return;
    if (info.required) {
      showRequiredUpdateDialog(context, info);
      return;
    }
    if (await AppUpdate.wasDismissed(info.version)) return;
    if (mounted) setState(() => _update = info);
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
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      AppLock.onPaused();
    }
    if (state == AppLifecycleState.resumed) {
      AppLock.onResumed();
      _refreshAll();
      // The user may just have come back from the settings page the warning opened
      _checkPushHealth();
    }
  }

  void _refreshAll() {
    _loadSummary();
    _inbox.currentState?.refresh();
    _home.currentState?.refresh();
  }

  Future<void> _checkPushHealth() async {
    final health = await Push.health();
    if (mounted) setState(() => _health = health);
  }

  Future<void> _openTarget(PushTarget target) async {
    if (!mounted) return;
    await openTarget(context, target);
    _refreshAll();
  }

  Future<void> _loadSummary() async {
    try {
      final body = await api.get('/summary');
      if (mounted) setState(() => _summary = Map<String, dynamic>.from(body as Map));
    } catch (_) {
      // Badges are a nicety; the lists report their own errors
    }
  }

  void _openTab(String key, {String? section}) {
    setState(() => _index = _tabs.indexOf(key));
    if (section != null) {
      // The work tab may not be built yet when the home screen asks for a section
      WidgetsBinding.instance.addPostFrameCallback((_) => _work.currentState?.show(section));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final hasWorkAreas = api.can('it_tickets') || api.can('complaints') || api.can('contacts');
    final workBadge = hasWorkAreas
        ? [(_summary['it_tickets'] as int?) ?? 0, (_summary['complaints'] as int?) ?? 0, (_summary['contacts'] as int?) ?? 0]
            .fold(0, (a, b) => a + b)
        : (_summary['my_open_tickets'] as int?) ?? 0;

    final showWarning = _health.problem != PushProblem.none && !(_health.problem == PushProblem.battery && _batteryWarningSkipped);

    final pages = [
      HomeTab(key: _home, summary: _summary, onRefresh: _loadSummary, onOpenTab: _openTab),
      InboxTab(key: _inbox, onChanged: _loadSummary),
      WorkTab(key: _work, onChanged: _loadSummary),
      AccountTab(
        onSignedOut: widget.onSignedOut,
        onLanguageChanged: () => QalamApp.relaunch(context),
      ),
    ];

    // Home and account draw their own gradient headers; the other tabs use a plain app bar
    final plainBar = _index == 1 || _index == 2;

    return Scaffold(
      appBar: plainBar
          ? AppBar(title: Text(s.t(_index == 2 && !hasWorkAreas ? 'my_tickets' : _tabs[_index])))
          : null,
      body: Column(
        children: [
          if (_update != null)
            UpdateBanner(
              info: _update!,
              onDismiss: () {
                AppUpdate.dismiss(_update!.version);
                setState(() => _update = null);
              },
            ),
          if (showWarning)
            PushWarning(
              health: _health,
              onSkip: _health.problem == PushProblem.battery ? () => setState(() => _batteryWarningSkipped = true) : null,
            ),
          Expanded(child: IndexedStack(index: _index, children: pages)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          setState(() => _index = value);
          _loadSummary();
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: s.t('home')),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: ((_summary['unread_notifications'] as int?) ?? 0) > 0,
              label: Text('${_summary['unread_notifications'] ?? 0}'),
              child: const Icon(Icons.notifications_none),
            ),
            selectedIcon: const Icon(Icons.notifications),
            label: s.t('inbox'),
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: workBadge > 0,
              label: Text('$workBadge'),
              child: Icon(hasWorkAreas ? Icons.work_outline : Icons.confirmation_number_outlined),
            ),
            selectedIcon: Icon(hasWorkAreas ? Icons.work : Icons.confirmation_number),
            label: s.t(hasWorkAreas ? 'work' : 'my_tickets'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: s.t('account'),
          ),
        ],
      ),
    );
  }
}
