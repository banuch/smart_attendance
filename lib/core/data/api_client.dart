import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  /// HTTP status; 0 when the server could not be reached.
  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Signed-in identity, restored from storage without a network round trip.
class AuthSession {
  const AuthSession(this.uid);

  final String uid;
}

/// JSON over HTTPS to the Smart Attendance API, with the login token.
class ApiClient {
  ApiClient({Uri? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? defaultBaseUrl(),
      _http = client ?? http.Client();

  /// `--dart-define=API_URL=https://…`. The web admin panel defaults to the
  /// site it is served from; debug Android builds to the emulator's host.
  static Uri defaultBaseUrl() {
    const configured = String.fromEnvironment('API_URL');
    if (configured.isNotEmpty) return Uri.parse(configured);
    if (kIsWeb) return Uri.parse(Uri.base.origin);
    if (kDebugMode) return Uri.parse('http://10.0.2.2:8080');
    throw StateError('Build with --dart-define=API_URL=https://your-server');
  }

  static const _tokenKey = 'auth_token';
  static const _uidKey = 'auth_uid';
  static const _timeout = Duration(seconds: 30);

  final Uri baseUrl;
  final http.Client _http;
  String? _token;

  /// Called when the server rejects the stored token.
  void Function()? onUnauthorized;

  final _changes = StreamController<void>.broadcast();

  /// Fires after every successful write, so lists can refresh at once.
  Stream<void> get changes => _changes.stream;

  Future<AuthSession?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    final uid = prefs.getString(_uidKey);
    return _token == null || uid == null ? null : AuthSession(uid);
  }

  Future<void> saveSession(String token, String uid) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_uidKey, uid);
  }

  Future<void> clearSession() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_uidKey);
  }

  Uri _uri(String path, [Map<String, String>? query]) => baseUrl.replace(
    path: '${baseUrl.path.replaceAll(RegExp(r'/+$'), '')}$path',
    queryParameters: query,
  );

  Map<String, String> get _authHeader => {
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send(http.Request('GET', _uri(path, query)));

  Future<dynamic> post(String path, [Object? body]) =>
      _send(_json('POST', path, body));

  Future<dynamic> put(String path, Object body) =>
      _send(_json('PUT', path, body));

  Future<dynamic> delete(String path) =>
      _send(http.Request('DELETE', _uri(path)));

  /// POST with a JPEG in the `photo` field plus form [fields].
  Future<dynamic> postPhoto(
    String path, {
    required Uint8List jpeg,
    required Map<String, String> fields,
  }) {
    final req = http.MultipartRequest('POST', _uri(path))
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes('photo', jpeg, filename: 'photo.jpg'),
      );
    return _send(req);
  }

  http.Request _json(String method, String path, Object? body) {
    final req = http.Request(method, _uri(path));
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    return req;
  }

  Future<dynamic> _send(http.BaseRequest req) async {
    req.headers.addAll(_authHeader);
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _http.send(req).timeout(_timeout),
      );
    } on TimeoutException {
      throw const ApiException(0, 'The server took too long to respond.');
    } catch (_) {
      throw const ApiException(
        0,
        'Could not reach the server. Check your internet connection.',
      );
    }

    final body = res.body.isEmpty ? null : _decode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (req.method != 'GET') _changes.add(null);
      return body;
    }
    if (res.statusCode == 401 && _token != null) onUnauthorized?.call();
    final message = body is Map && body['error'] is String
        ? body['error'] as String
        : 'Request failed (${res.statusCode}).';
    throw ApiException(res.statusCode, message);
  }

  static dynamic _decode(String s) {
    try {
      return jsonDecode(s);
    } on FormatException {
      return null;
    }
  }
}

/// Emits [fetch]'s result now, every [every], and right after any write
/// through [api]. Replaces Firestore's live snapshots.
Stream<T> poll<T>(
  ApiClient api,
  Future<T> Function() fetch, {
  Duration every = const Duration(seconds: 30),
}) {
  late final StreamController<T> controller;
  Timer? timer;
  StreamSubscription<void>? writes;
  var running = false;
  var again = false;

  Future<void> tick() async {
    if (running) {
      again = true;
      return;
    }
    running = true;
    try {
      do {
        again = false;
        try {
          final value = await fetch();
          if (!controller.isClosed) controller.add(value);
        } catch (e, s) {
          if (!controller.isClosed) controller.addError(e, s);
        }
      } while (again && !controller.isClosed);
    } finally {
      running = false;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      tick();
      timer = Timer.periodic(every, (_) => tick());
      writes = api.changes.listen((_) => tick());
    },
    onCancel: () {
      timer?.cancel();
      writes?.cancel();
    },
  );
  return controller.stream;
}
