import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'api.dart';
import 'strings.dart';
import 'theme.dart';

/// Optional app lock: a 4-digit PIN kept hashed in secure storage, plus fingerprint / face
/// unlock through the phone's own biometrics. The lock shows at start and after the app has
/// been in the background for a short while.
class AppLock {
  static const _pinKey = 'lock_pin';
  static const _biometricKey = 'lock_biometric';
  static const pinLength = 4;
  static const _grace = Duration(seconds: 20);

  static bool enabled = false;
  static bool biometric = false;

  /// True while the lock screen must cover the app.
  static final ValueNotifier<bool> locked = ValueNotifier(false);

  static DateTime? _pausedAt;
  static final _auth = LocalAuthentication();

  static Future<void> load() async {
    enabled = (await api.readSetting(_pinKey)) != null;
    biometric = enabled && (await api.readSetting(_biometricKey)) == '1';
    locked.value = enabled;
  }

  static Future<void> setPin(String pin) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final saltHex = salt.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await api.writeSetting(_pinKey, '$saltHex:${_hash(saltHex, pin)}');
    enabled = true;
  }

  static Future<bool> verify(String pin) async {
    final stored = await api.readSetting(_pinKey);
    if (stored == null) return true;
    final parts = stored.split(':');
    if (parts.length != 2) return false;
    return _hash(parts[0], pin) == parts[1];
  }

  static Future<void> disable() async {
    await api.deleteSetting(_pinKey);
    await api.deleteSetting(_biometricKey);
    enabled = false;
    biometric = false;
    locked.value = false;
  }

  static Future<void> setBiometric(bool on) async {
    if (on) {
      await api.writeSetting(_biometricKey, '1');
    } else {
      await api.deleteSetting(_biometricKey);
    }
    biometric = on;
  }

  static Future<bool> biometricsAvailable() async {
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateBiometric(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }

  static void onPaused() => _pausedAt = DateTime.now();

  static void onResumed() {
    if (!enabled || _pausedAt == null) return;
    if (DateTime.now().difference(_pausedAt!) >= _grace) locked.value = true;
    _pausedAt = null;
  }

  static void unlock() => locked.value = false;

  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();
}

/// Covers [child] with the lock screen while the app is locked.
class LockGate extends StatelessWidget {
  const LockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLock.locked,
      builder: (context, locked, _) => Stack(
        children: [
          child,
          if (locked)
            const Positioned.fill(
              child: LockScreen(onUnlocked: AppLock.unlock, allowSignOut: true),
            ),
        ],
      ),
    );
  }
}

/// PIN pad with optional biometric button. Also used to confirm the PIN before changing settings.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked, this.allowSignOut = false, this.canClose = false, this.title});

  final VoidCallback onUnlocked;
  final bool allowSignOut;
  final bool canClose;
  final String? title;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with SingleTickerProviderStateMixin {
  String _entered = '';
  int _failures = 0;
  DateTime? _blockedUntil;
  bool _checking = false;
  bool _biometricsReady = false;
  Timer? _tick;
  late final _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void initState() {
    super.initState();
    _prepareBiometrics();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _shake.dispose();
    super.dispose();
  }

  Future<void> _prepareBiometrics() async {
    if (!AppLock.biometric) return;
    final ready = await AppLock.biometricsAvailable();
    if (!mounted) return;
    setState(() => _biometricsReady = ready);
    if (ready) _biometric();
  }

  Future<void> _biometric() async {
    final ok = await AppLock.authenticateBiometric(S.of(context).t('biometric_reason'));
    if (ok && mounted) widget.onUnlocked();
  }

  void _press(String digit) {
    if (_checking || _blocked) return;
    if (_entered.length >= AppLock.pinLength) return;
    setState(() => _entered += digit);
    if (_entered.length == AppLock.pinLength) _submit();
  }

  bool get _blocked => _blockedUntil != null && DateTime.now().isBefore(_blockedUntil!);

  Future<void> _submit() async {
    setState(() => _checking = true);
    final ok = await AppLock.verify(_entered);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    _failures++;
    _shake.forward(from: 0);
    setState(() {
      _entered = '';
      _checking = false;
      if (_failures >= 5) {
        _blockedUntil = DateTime.now().add(const Duration(seconds: 30));
        _failures = 0;
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          setState(() {});
          if (!_blocked) t.cancel();
        });
      }
    });
  }

  Future<void> _signOut() async {
    final s = S.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.t('forgot_pin_hint')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.t('logout'))),
        ],
      ),
    );
    if (sure != true) return;
    await AppLock.disable();
    await api.logout();
    api.onSignedOut?.call();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final remaining = _blocked ? _blockedUntil!.difference(DateTime.now()).inSeconds + 1 : 0;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            if (widget.canClose)
              Align(
                alignment: AlignmentDirectional.topStart,
                child: IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
              ),
            const Spacer(),
            Image.asset('assets/logo.png', height: 72),
            const SizedBox(height: 16),
            Text(widget.title ?? s.t('enter_pin'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                final offset = sin(_shake.value * pi * 4) * 10 * (1 - _shake.value);
                return Transform.translate(offset: Offset(offset, 0), child: child);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < AppLock.pinLength; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _entered.length ? scheme.primary : Colors.transparent,
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 22,
              child: Text(
                _blocked
                    ? '${s.t('too_many_attempts')} ($remaining)'
                    : _failures > 0
                        ? s.t('wrong_pin')
                        : '',
                style: TextStyle(color: scheme.error, fontSize: 13),
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                childAspectRatio: 1.35,
                children: [
                  for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) _key(context, d),
                  _biometricsReady
                      ? _iconKey(context, Icons.fingerprint, _biometric)
                      : const SizedBox.shrink(),
                  _key(context, '0'),
                  _iconKey(context, Icons.backspace_outlined, () {
                    if (_entered.isNotEmpty) setState(() => _entered = _entered.substring(0, _entered.length - 1));
                  }),
                ],
              ),
            ),
            const Spacer(),
            if (widget.allowSignOut)
              TextButton(onPressed: _signOut, child: Text(s.t('forgot_pin'))),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _key(BuildContext context, String digit) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _press(digit),
          child: Center(child: Text(digit, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
        ),
      ),
    );
  }

  Widget _iconKey(BuildContext context, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Center(child: Icon(icon, size: 28, color: brandColor)),
      ),
    );
  }
}

/// Two-step "choose a PIN, repeat it" screen. Pops with the PIN or null.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  String _first = '';
  String _entered = '';
  bool _mismatch = false;

  void _press(String d) {
    if (_entered.length >= AppLock.pinLength) return;
    setState(() {
      _entered += d;
      _mismatch = false;
    });
    if (_entered.length < AppLock.pinLength) return;

    if (_first.isEmpty) {
      setState(() {
        _first = _entered;
        _entered = '';
      });
    } else if (_entered == _first) {
      Navigator.of(context).pop(_entered);
    } else {
      setState(() {
        _first = '';
        _entered = '';
        _mismatch = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('app_lock'))),
      body: Column(
        children: [
          const Spacer(),
          Icon(Icons.lock_outline, size: 48, color: scheme.primary),
          const SizedBox(height: 16),
          Text(_first.isEmpty ? s.t('set_pin') : s.t('confirm_pin'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < AppLock.pinLength; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _entered.length ? scheme.primary : Colors.transparent,
                    border: Border.all(color: scheme.primary, width: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 22, child: Text(_mismatch ? s.t('pin_mismatch') : '', style: TextStyle(color: scheme.error, fontSize: 13))),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              childAspectRatio: 1.35,
              children: [
                for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9']) _key(d),
                const SizedBox.shrink(),
                _key('0'),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      if (_entered.isNotEmpty) setState(() => _entered = _entered.substring(0, _entered.length - 1));
                    },
                    child: const Center(child: Icon(Icons.backspace_outlined, size: 28, color: brandColor)),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _key(String digit) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _press(digit),
          child: Center(child: Text(digit, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600))),
        ),
      ),
    );
  }
}

/// Account page section: turn the lock on/off, change the PIN, toggle biometrics.
class LockSettingsSheet extends StatefulWidget {
  const LockSettingsSheet({super.key});

  @override
  State<LockSettingsSheet> createState() => _LockSettingsSheetState();
}

class _LockSettingsSheetState extends State<LockSettingsSheet> {
  bool _biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    AppLock.biometricsAvailable().then((v) {
      if (mounted) setState(() => _biometricsAvailable = v);
    });
  }

  /// Asks for the current PIN before a sensitive change. Resolves true when confirmed.
  Future<bool> _confirmPin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => LockScreen(
          canClose: true,
          title: S.of(context).t('confirm_current_pin'),
          onUnlocked: () => Navigator.of(context).pop(true),
        ),
      ),
    );
    return ok == true;
  }

  Future<void> _toggle(bool on) async {
    if (on) {
      final pin = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const PinSetupScreen()));
      if (pin == null) return;
      await AppLock.setPin(pin);
    } else {
      if (!await _confirmPin()) return;
      await AppLock.disable();
    }
    if (mounted) setState(() {});
  }

  Future<void> _changePin() async {
    if (!await _confirmPin()) return;
    if (!mounted) return;
    final pin = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const PinSetupScreen()));
    if (pin == null) return;
    await AppLock.setPin(pin);
    if (mounted) setState(() {});
  }

  Future<void> _toggleBiometric(bool on) async {
    if (on) {
      final ok = await AppLock.authenticateBiometric(S.of(context).t('biometric_reason'));
      if (!ok) return;
    }
    await AppLock.setBiometric(on);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.t('app_lock_hint'), style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(s.t('app_lock')),
          secondary: const Icon(Icons.lock_outline),
          value: AppLock.enabled,
          onChanged: _toggle,
        ),
        if (AppLock.enabled) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.t('biometric_unlock')),
            subtitle: _biometricsAvailable ? null : Text(s.t('biometric_unavailable'), style: const TextStyle(fontSize: 12)),
            secondary: const Icon(Icons.fingerprint),
            value: AppLock.biometric,
            onChanged: _biometricsAvailable ? _toggleBiometric : null,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.pin_outlined),
            title: Text(s.t('change_pin')),
            trailing: const Icon(Icons.chevron_right),
            onTap: _changePin,
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
