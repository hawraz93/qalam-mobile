import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Talks to the Laravel API under /api/v1.
/// Point it somewhere else with: flutter run --dart-define=API_BASE=http://10.0.2.2:8000/api/v1
class Api {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://alqalam.edu.iq/api/v1',
  );

  static const _tokenKey = 'api_token';
  final _storage = const FlutterSecureStorage();

  String? _token;
  Map<String, dynamic>? user;

  /// Called when the server says the token is no longer valid.
  void Function()? onSignedOut;

  bool get isSignedIn => _token != null && user != null;

  /// For widgets that fetch protected files themselves (Image.network).
  Map<String, String> get authHeaders => {
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  bool can(String area) => (user?['can'] as Map?)?[area] == true;

  bool get isAdmin => user?['is_admin'] == true;
  bool get isTeacher => user?['is_teacher'] == true;

  /// Small per-phone settings (language) kept next to the token.
  Future<String?> readSetting(String key) async {
    try {
      return await _storage.read(key: 'setting_$key');
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSetting(String key, String value) async {
    try {
      await _storage.write(key: 'setting_$key', value: value);
    } catch (_) {
      // A lost preference is not worth an error
    }
  }

  Future<void> deleteSetting(String key) async {
    try {
      await _storage.delete(key: 'setting_$key');
    } catch (_) {
      // Already gone
    }
  }

  /// Saves the account edits made in the app and refreshes the cached profile.
  Future<void> updateProfile(Map<String, dynamic> fields) async {
    final body = await patch('/me', fields);
    user = Map<String, dynamic>.from(body['user'] as Map);
  }

  Future<void> refreshProfile() async {
    final body = await get('/me');
    user = Map<String, dynamic>.from(body['user'] as Map);
  }

  /// Website pages this user may open inside the app: [{key, path}, ...].
  List<Map<String, dynamic>> get webLinks => [
        for (final link in (user?['web_links'] as List? ?? []))
          Map<String, dynamic>.from(link as Map),
      ];

  /// True when an admin requires signing in before a ticket can be opened.
  /// Asked from the server each time; if it cannot be reached the form is still
  /// offered and the server has the final say.
  Future<bool> ticketsRequireLogin() async {
    try {
      final body = await get('/config');
      return body['tickets_require_login'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Restores a saved session. Returns false when the user must sign in.
  Future<bool> restore() async {
    _token = await _storage.read(key: _tokenKey);
    if (_token == null) return false;

    try {
      final body = await get('/me');
      user = Map<String, dynamic>.from(body['user'] as Map);
      return true;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _clear();
        return false;
      }
      rethrow;
    }
  }

  Future<void> login(String login, String password, String deviceName) async {
    final body = await post('/auth/login', {
      'login': login,
      'password': password,
      'device_name': deviceName,
    });

    _token = body['token'] as String;
    user = Map<String, dynamic>.from(body['user'] as Map);
    await _storage.write(key: _tokenKey, value: _token);
  }

  Future<void> logout({String? deviceToken}) async {
    try {
      await post('/auth/logout', {if (deviceToken != null) 'device_token': deviceToken});
    } catch (_) {
      // Signing out locally must work even when the server is unreachable
    }
    await _clear();
  }

  Future<void> _clear() async {
    _token = null;
    user = null;
    await _storage.delete(key: _tokenKey);
  }

  Future<dynamic> get(String path, [Map<String, String>? query]) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) =>
      _send('POST', path, body: body);

  Future<dynamic> patch(String path, Map<String, dynamic> body) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path, [Map<String, dynamic>? body]) =>
      _send('DELETE', path, body: body);

  Future<dynamic> put(String path, Map<String, dynamic> body) => _send('PUT', path, body: body);

  /// Multipart upload of one file (photo, CV) with optional text fields.
  Future<dynamic> upload(String path, String field, String filePath, {Map<String, String> fields = const {}}) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
      ..headers['Accept'] = 'application/json'
      ..fields.addAll(fields);
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.files.add(await http.MultipartFile.fromPath(field, filePath));

    final http.Response response;
    try {
      response = await http.Response.fromStream(await request.send().timeout(const Duration(seconds: 90)));
    } catch (_) {
      throw ApiException(0, 'network');
    }
    return _handle(response);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );

    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'application/json';

    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 20)),
      );
    } catch (_) {
      throw ApiException(0, 'network');
    }

    return _handle(response);
  }

  Future<dynamic> _handle(http.Response response) async {
    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (response.statusCode == 401 && _token != null) {
      await _clear();
      onSignedOut?.call();
    }

    String message = 'HTTP ${response.statusCode}';
    if (decoded is Map) {
      final errors = decoded['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        message = first is List && first.isNotEmpty ? first.first.toString() : first.toString();
      } else if (decoded['message'] != null) {
        message = decoded['message'].toString();
      }
    }

    throw ApiException(response.statusCode, message);
  }
}

final api = Api();
