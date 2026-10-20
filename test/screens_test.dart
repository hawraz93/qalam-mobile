// Screenshots of the main screens with sample data, for design review.
//
//   flutter test test/screens_test.dart --update-goldens --dart-define=SCREENSHOTS=true
//
// writes PNGs to test/screenshots/ (git-ignored). Without the define the tests
// are skipped, so `flutter test` and CI stay independent of font rendering.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qalam_notify/api.dart';
import 'package:qalam_notify/main.dart';
import 'package:qalam_notify/screens/account.dart';
import 'package:qalam_notify/screens/complaints.dart';
import 'package:qalam_notify/screens/contacts.dart';
import 'package:qalam_notify/screens/home.dart';
import 'package:qalam_notify/screens/inbox.dart';
import 'package:qalam_notify/screens/ticket_form.dart';
import 'package:qalam_notify/screens/tickets.dart';
import 'package:qalam_notify/strings.dart';
import 'package:qalam_notify/theme.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

final _now = DateTime.now();
String _ago(Duration d) => _now.subtract(d).toIso8601String();

final Map<String, dynamic> _user = {
  'id': 7,
  'name': 'هاوڕاز نەوزاد',
  'email': 'hawraz@alqalam.edu.iq',
  'phone': '07701234567',
  'username': 'hawraz',
  'roles': ['Admin', 'IT'],
  'is_teacher': true,
  'is_admin': true,
  'department': 'قسم تقنيات المعلومات',
  'department_id': 85,
  'created_at': '2024-02-11T09:00:00+03:00',
  'can': {'it_tickets': true, 'complaints': true, 'contacts': true},
  'teacher': {
    'name_ar': 'هاوراز نوزاد',
    'name_en': 'Hawraz Nawzad',
    'academic_title': 'مدرس مساعد',
    'degree': 'ماجستير',
    'specialty': 'هندسة البرمجيات',
    'completion': 72,
  },
  'web_links': [
    {'key': 'dashboard', 'path': '/dashboard'},
    {'key': 'research', 'path': '/research'},
    {'key': 'education', 'path': '/education'},
    {'key': 'teaching', 'path': '/teaching'},
    {'key': 'notification_settings', 'path': '/admin/notifications/telegram'},
  ],
};

final _notifications = [
  {'id': 1, 'category': 'it_tickets', 'entity_id': 12, 'title': 'تیکێتی نوێ: پرینتەری نهۆمی دووەم کار ناکات', 'body': 'قسم الشؤون المالية · گرنگ', 'read_at': null, 'created_at': _ago(const Duration(minutes: 4))},
  {'id': 2, 'category': 'complaints', 'entity_id': 5, 'title': 'سکاڵای نوێ لە قوتابییەک', 'body': 'دواکەوتنی ئەنجامی تاقیکردنەوە', 'read_at': null, 'created_at': _ago(const Duration(hours: 2))},
  {'id': 3, 'category': 'ticket_updates', 'entity_id': 9, 'title': 'وەڵام بۆ تیکێتەکەت درایەوە', 'body': 'هێڵی ئینتەرنێتی هۆڵی ٣ چاک کرا', 'read_at': '2026-10-18', 'created_at': _ago(const Duration(hours: 20))},
  {'id': 4, 'category': 'contacts', 'entity_id': 3, 'title': 'نامەی نوێ لە پەڕەی پەیوەندی', 'body': 'پرسیار دەربارەی وەرگرتن', 'read_at': '2026-10-17', 'created_at': _ago(const Duration(days: 2))},
];

final _tickets = [
  {'id': 12, 'ticket_no': 'IT-2026-0412', 'title': 'پرینتەری نهۆمی دووەم کار ناکات', 'status': 'open', 'priority': 'high', 'requester_name': 'سارا ئەحمەد', 'needs_attention': true, 'created_at': _ago(const Duration(minutes: 40))},
  {'id': 11, 'ticket_no': 'IT-2026-0409', 'title': 'نەتوانینی چوونەژوورەوە بۆ سیستەمی نمرەکان', 'status': 'in_progress', 'priority': 'urgent', 'requester_name': 'د. کاوە', 'needs_attention': false, 'created_at': _ago(const Duration(hours: 5))},
  {'id': 9, 'ticket_no': 'IT-2026-0398', 'title': 'هێڵی ئینتەرنێتی هۆڵی ٣', 'status': 'resolved', 'priority': 'medium', 'requester_name': 'ئاراس', 'needs_attention': false, 'created_at': _ago(const Duration(days: 3))},
  {'id': 8, 'ticket_no': 'IT-2026-0391', 'title': 'دانانی Office لەسەر کۆمپیوتەری تاقیگە', 'status': 'closed', 'priority': 'low', 'requester_name': 'نەسرین', 'needs_attention': false, 'created_at': _ago(const Duration(days: 8))},
];

final _departments = [
  {'id': 85, 'name': 'قسم تقنيات المعلومات', 'description': 'مجلس الجامعة › رئيس الجامعة › مساعد رئيس الجامعة للشؤون الادارية والمالية'},
  {'id': 608, 'name': 'شعبة الرواتب', 'description': 'مجلس الجامعة › رئيس الجامعة › مساعد رئيس الجامعة للشؤون الادارية والمالية › قسم الشؤون المالية'},
  {'id': 25, 'name': 'كلية التربية', 'description': 'مجلس الجامعة › رئيس الجامعة › الكليات'},
  {'id': 1, 'name': 'اللغة الانكليزية', 'description': 'مجلس الجامعة › رئيس الجامعة › الكليات › كلية التربية'},
];

final Map<String, dynamic> _ticketDetail = {
  ..._tickets.first,
  'description': 'پرینتەرەکەی ژووری ٢٠٤ لە بەیانییەوە هیچ چاپ ناکات و چرای سوور دادەگیرسێت. کاغەزیش تێدایە.',
  'department_name': 'قسم الشؤون المالية',
  'requester_email': 'sara@alqalam.edu.iq',
  'requester_phone': '07501112233',
  'assignee': null,
  'it_notes': '',
  'updates': [],
  'attachments': [
    {'url': 'https://example.com/a.pdf', 'filename': 'error-report.pdf', 'is_image': false},
  ],
  'rating': null,
};

final Map<String, dynamic> _myTicketDetail = {
  ..._tickets[2],
  'description': 'ئینتەرنێتی هۆڵی ٣ لە کاتی وانەدا دەپچڕێت.',
  'department_name': 'كلية التربية',
  'assignee': 'ئاراس عومەر',
  'it_notes': 'ڕاوتەرەکە گۆڕدرا.',
  'can_rate': true,
  'rating': null,
  'updates': [
    {'kind': 'status', 'title': 'دۆخ گۆڕا بۆ: لە کاردایە', 'body': '', 'created_at': _ago(const Duration(days: 2))},
    {'kind': 'reply', 'title': 'وەڵامی تیمی IT', 'reply_message': 'هێڵەکە چاک کرا، تکایە تاقی بکەرەوە.', 'created_at': _ago(const Duration(hours: 20))},
  ],
};

final Map<String, dynamic> _complaint = {
  'id': 5,
  'reference': 'CMP-2026-0057',
  'priority': 'high',
  'is_resolved': false,
  'can_reply_by_email': true,
  'name': 'ڕێبین سەعید',
  'phone': '07709998877',
  'email': 'rebin@example.com',
  'description': 'ئەنجامی تاقیکردنەوەی کۆتایی وەرز دوو هەفتەیە دوا کەوتووە و هیچ ڕوونکردنەوەیەک نەدراوە.',
  'admin_notes': '',
  'evidence': [
    {'is_image': false, 'filename': 'screenshot-results.pdf', 'url': 'https://example.com/a.pdf'},
  ],
  'created_at': _ago(const Duration(hours: 2)),
};

final Map<String, dynamic> _contact = {
  'id': 3,
  'name': 'لانە کەریم',
  'email': 'lana@example.com',
  'phone': '07501231234',
  'subject_display': 'وەرگرتن',
  'message': 'سڵاو، دەمەوێت بزانم کەی وەرگرتن بۆ ساڵی نوێ دەست پێ دەکات و چ بەڵگەنامەیەک پێویستە.',
  'replied_at': null,
  'created_at': _ago(const Duration(days: 2)),
};

http.Response _json(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {
      'data': rows,
      'meta': {'current_page': 1, 'last_page': 1},
    };

final _fakeServer = MockClient((request) async {
  final path = request.url.path.replaceFirst('/api/v1', '');
  return switch (path) {
    '/config' => _json({'tickets_require_login': false, 'departments': _departments, 'app': {}}),
    '/summary' => _json({'unread_notifications': 2, 'my_open_tickets': 1, 'it_tickets': 3, 'complaints': 1, 'contacts': 0}),
    '/notifications' => _json(_page(_notifications)),
    '/my/tickets' || '/tickets' => _json(_page(_tickets)),
    '/me' => _json({'user': _user}),
    '/tickets/12' => _json({'data': _ticketDetail}),
    '/my/tickets/9' => _json({'data': _myTicketDetail}),
    '/complaints/5' => _json({'data': _complaint}),
    '/contacts/3' => _json({'data': _contact}),
    _ => _json({'data': []}),
  };
});

Future<void> _loadFonts() async {
  final family = FontLoader('Vazirmatn');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    family.addFont(rootBundle.load('assets/fonts/Vazirmatn-$weight.ttf'));
  }
  await family.load();

  // Material icons ship with the Flutter SDK, not with the app's assets.
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final icons = File('$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf');
  final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
  await loader.load();
}

Widget _app(Widget child, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar'), Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: child,
  );
}

/// Lets the fake requests answer and the first frames settle (lists animate forever, so no pumpAndSettle).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _shot(WidgetTester tester, String name, Widget screen, {Brightness brightness = Brightness.light}) async {
  await tester.pumpWidget(_app(screen, brightness: brightness));
  await _settle(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
}

void main() {
  setUpAll(() async {
    S.current = 'ckb';
    api.client = _fakeServer;
    await _loadFonts();
  });

  setUp(() => api.signInForPreview(Map<String, dynamic>.from(_user)));

  void screen(String name, Widget Function() build, {Brightness brightness = Brightness.light, bool signedIn = true}) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(top: 72, bottom: 48);
      addTearDown(tester.view.reset);
      if (!signedIn) api.user = null;
      await _shot(tester, name, build(), brightness: brightness);
    }, skip: !_enabled);
  }

  screen('01_login', () => LoginScreen(onSignedIn: () {}), signedIn: false);
  screen('02_home', () => Scaffold(body: HomeTab(summary: const {'unread_notifications': 2, 'my_open_tickets': 1, 'it_tickets': 3, 'complaints': 1, 'contacts': 0}, onRefresh: () async {}, onOpenTab: (_, {section}) {})));
  screen('03_home_dark', () => Scaffold(body: HomeTab(summary: const {'unread_notifications': 2, 'my_open_tickets': 1, 'it_tickets': 3, 'complaints': 1, 'contacts': 0}, onRefresh: () async {}, onOpenTab: (_, {section}) {})), brightness: Brightness.dark);
  screen('04_inbox', () => Scaffold(appBar: AppBar(title: const Text('ئاگادارکردنەوەکان')), body: InboxTab(onChanged: () {})));
  screen('05_tickets_admin', () => Scaffold(appBar: AppBar(title: const Text('تیکێتەکان')), body: const AdminTicketsTab()));
  screen('06_ticket_form', () => const TicketFormScreen());
  screen('08_ticket_admin', () => const TicketDetailScreen(id: 12, admin: true));
  screen('09_ticket_mine', () => const TicketDetailScreen(id: 9, admin: false));
  screen('10_complaint', () => const ComplaintDetailScreen(id: 5));
  screen('11_contact', () => const ContactDetailScreen(id: 3));
  screen('12_ticket_dark', () => const TicketDetailScreen(id: 9, admin: false), brightness: Brightness.dark);
  screen('07_account', () => Scaffold(body: AccountTab(onSignedOut: () {}, onLanguageChanged: () {})));
}
