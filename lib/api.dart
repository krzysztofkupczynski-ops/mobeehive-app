import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const String apiBase = 'https://mobeehive.pl/wp-json/mobeehive/v1';

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0});
  final String message;
  final int status;
  @override
  String toString() => message;
}

/// Połączenie z wtyczką Mobeehive. Każde żądanie POST wysyła treść JSON
/// (filtr hostingu odrzuca pusty POST kodem 406).
class Api {
  Api._();
  static final Api instance = Api._();

  final _storage = const FlutterSecureStorage();
  String? _token;
  Map<String, dynamic>? user;

  bool get loggedIn => _token != null;

  Future<String?> token() async => _token;

  Future<void> load() async {
    _token = await _storage.read(key: 'token');
    final u = await _storage.read(key: 'user');
    if (u != null) user = jsonDecode(u) as Map<String, dynamic>;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final r = await http
        .post(Uri.parse('$apiBase$path'), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    return _decode(r);
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final r = await http.get(Uri.parse('$apiBase$path'), headers: _headers).timeout(const Duration(seconds: 30));
    return _decode(r);
  }

  Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Serwer zwrócił nieoczekiwaną odpowiedź (HTTP ${r.statusCode}).', status: r.statusCode);
    }
    if (r.statusCode >= 400) {
      throw ApiException((data['message'] ?? 'Błąd HTTP ${r.statusCode}').toString(), status: r.statusCode);
    }
    return data;
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    _token = data['token'] as String;
    user = data['user'] as Map<String, dynamic>;
    await _storage.write(key: 'token', value: _token);
    await _storage.write(key: 'user', value: jsonEncode(user));
  }

  Future<void> login(String email, String password) async =>
      _saveSession(await _post('/auth/login', {'email': email, 'password': password, 'device': 'mobeehive-app'}));

  Future<void> register(String email, String password, String name) async => _saveSession(
      await _post('/auth/register', {'email': email, 'password': password, 'name': name, 'device': 'mobeehive-app'}));

  Future<void> logout() async {
    try {
      await _post('/auth/logout', {});
    } catch (_) {}
    _token = null;
    user = null;
    await _storage.deleteAll();
  }

  Future<Map<String, dynamic>> me() => _get('/me');

  Future<Map<String, dynamic>> weather(double lat, double lon) =>
      _get('/weather?lat=${lat.toStringAsFixed(4)}&lon=${lon.toStringAsFixed(4)}');

  Future<Map<String, dynamic>> region(double lat, double lon) =>
      _get('/region?lat=${lat.toStringAsFixed(5)}&lon=${lon.toStringAsFixed(5)}');

  Future<Map<String, dynamic>> saveSettings(Map<String, dynamic> settings) => _post('/settings', settings);

  Future<Map<String, dynamic>> piw({String? teryt, String? county}) => _get(
      '/piw?teryt=${Uri.encodeQueryComponent(teryt ?? '')}&county=${Uri.encodeQueryComponent(county ?? '')}');

  Future<void> deleteAccount() => _post('/account/delete', {});

  Future<Map<String, dynamic>> sync(int since, Map<String, List<Map<String, dynamic>>> changes) =>
      _post('/sync', {'since': since, 'changes': changes});

  Future<void> updateAccount(Map<String, dynamic> account) async {
    if (user == null) return;
    user!['account'] = account;
    await _storage.write(key: 'user', value: jsonEncode(user));
  }
}
