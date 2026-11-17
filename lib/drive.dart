import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'data.dart';

/// Google sign-in via the Android OAuth client (package + SHA-1). No client secret is used or stored.
class DriveAuth {
  static const _serverClientId = '1008694107333-5rac3hpubmu3rdvbp81s6j7thku4vf6o.apps.googleusercontent.com';
  static const driveScope = 'https://www.googleapis.com/auth/drive';
  final _g = GoogleSignIn(
    serverClientId: _serverClientId,
    scopes: [driveScope],
  );
  GoogleSignInAccount? user;
  FirebaseAuth get _firebase => FirebaseAuth.instance;
  static const _authTimeout = Duration(seconds: 20);

  void _trace(String message) => debugPrint('[CloudBox][auth] $message');

  Future<void> _linkFirebase(GoogleSignInAccount account) async {
    _trace('linking Google identity to Firebase');
    final auth = await account.authentication.timeout(_authTimeout);
    if (auth.idToken == null && auth.accessToken == null) {
      throw const AuthException('missing_google_tokens', 'Google did not return authentication tokens.');
    }
    final credential = GoogleAuthProvider.credential(
      idToken: auth.idToken,
      accessToken: auth.accessToken,
    );
    await _firebase.signInWithCredential(credential).timeout(_authTimeout);
    _trace('Firebase authentication completed');
  }

  Future<bool> silent() async {
    try {
      _trace('restoring Google session');
      user = await _g.signInSilently().timeout(_authTimeout);
      Diag.add('auth:google-silent', 'user=${user != null}');
      if (user != null) {
        await _linkFirebase(user!);
      }
      Diag.add('auth:firebase-linked');
    } catch (e) {
      Diag.add('auth:silent-failed', '${e.runtimeType}: $e');
      user = null;
    }
    return user != null;
  }

  Future<void> signIn() async {
    user = await _g.signIn();
    if (user == null) throw 'sign_in_canceled';
    try {
      await _linkFirebase(user!);
    } catch (_) {
      user = null;
      rethrow;
    }
  }

  Future<Map<String, String>> headers() async {
    final account = user;
    if (account == null) throw const AuthException('not_signed_in', 'Google Drive is not connected.');
    _trace('requesting Drive access headers');
    final headers = await account.authHeaders.timeout(_authTimeout);
    bool hasAuthorization(Map<String, String> value) => value.entries.any((entry) {
          final key = entry.key.toLowerCase();
          final token = entry.value.trim();
          return key == 'authorization' && token.startsWith('Bearer ') && token.length > 'Bearer '.length;
        });
    Diag.add('auth:drive-headers', 'authorization=${hasAuthorization(headers)}');
    if (!hasAuthorization(headers)) {
      await account.clearAuthCache();
      final refreshed = await account.authHeaders.timeout(_authTimeout);
      if (!hasAuthorization(refreshed)) {
        throw const AuthException('missing_drive_token', 'Google did not provide a Drive access token.');
      }
      return refreshed;
    }
    return headers;
  }
  Future<void> refresh() => user!.clearAuthCache().timeout(_authTimeout);
  Future<void> signOut() async {
    try {
      await _g.signOut();
    } catch (_) {}
    try {
      await _firebase.signOut();
    } catch (_) {}
    user = null;
  }
}

class AuthException implements Exception {
  const AuthException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

const _folder = 'application/vnd.google-apps.folder';

class DriveRepo implements Repo {
  DriveRepo(this._a);
  final DriveAuth _a;
  final _c = http.Client();
  static const _requestTimeout = Duration(seconds: 30);
  static const _fields = 'nextPageToken,files(id,name,mimeType,size,modifiedTime,shared,thumbnailLink,webViewLink,parents,capabilities)';

  @override
  bool get canOffline => true;

  void _trace(String message) => debugPrint('[CloudBox][drive] $message');

  Future<http.Response> _execute(http.Request request) async {
    final stream = await _c.send(request).timeout(_requestTimeout);
    return http.Response.fromStream(stream).timeout(_requestTimeout);
  }

  Future<http.Response> _send(String method, String path, {Map<String, String>? q, Object? body}) async {
    for (var a = 0;; a++) {
      final uri = Uri.https('www.googleapis.com', '/drive/v3/$path', q);
      _trace('$method ${uri.path} (attempt ${a + 1})');
      final req = http.Request(method, uri)..headers.addAll(await _a.headers().timeout(_requestTimeout));
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final r = await _execute(req);
      _trace('response ${r.statusCode} for ${uri.path}');
      Diag.add('http:status', '${r.statusCode} $method ${uri.path} bytes=${r.bodyBytes.length}');
      if (r.statusCode == 401 && a == 0) {
        await _a.refresh();
        continue;
      }
      if (r.statusCode >= 300) {
        String m = switch (r.statusCode) {
          401 => 'Google Drive authorization expired. Sign in again.',
          403 => 'Google Drive denied this request. Check Drive permissions for this account.',
          404 => 'The requested Drive item no longer exists.',
          _ => 'Google Drive returned ${r.statusCode}.',
        };
        try {
          m = (jsonDecode(r.body)['error']['message'] as String?) ?? m;
        } catch (_) {}
        throw DriveError(r.statusCode, m);
      }
      return r;
    }
  }

  Item _p(Map<String, dynamic> j) => Item(
        id: j['id'],
        name: j['name'],
        folder: j['mimeType'] == _folder,
        size: int.tryParse('${j['size'] ?? 0}') ?? 0,
        date: DateTime.tryParse(j['modifiedTime'] ?? '')?.toLocal() ?? DateTime.now(),
        shared: j['shared'] == true,
        mime: j['mimeType'] ?? '',
        thumb: j['thumbnailLink'],
        link: j['webViewLink'],
      );

  Future<List<Item>> _q(String q, {String? order, int pages = 5, int size = 200}) async {
    final out = <Item>[];
    String? tok;
    var n = 0;
    do {
      final p = {
        'q': q,
        'fields': _fields,
        'pageSize': '$size',
        'spaces': 'drive',
        'corpora': 'user',
        'includeItemsFromAllDrives': 'true',
        'supportsAllDrives': 'true',
      };
      if (order != null) p['orderBy'] = order;
      if (tok != null) p['pageToken'] = tok;
      final j = jsonDecode((await _send('GET', 'files', q: p)).body) as Map<String, dynamic>;
      final files = (j['files'] as List<dynamic>?) ?? const <dynamic>[];
      out.addAll(files.map((e) => _p(e as Map<String, dynamic>)));
      tok = j['nextPageToken'] as String?;
      Diag.add('parse:page', 'files=${files.length} total=${out.length} more=${tok != null}');
    } while (tok != null && ++n < pages);
    return out;
  }

  String _esc(String s) => s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

  @override
  Future<List<Item>> list(String parent) => _q("'$parent' in parents and trashed=false");
  @override
  Future<List<Item>> recent() => _q("trashed=false and mimeType!='$_folder'", order: 'modifiedTime desc', pages: 1, size: 50);
  @override
  Future<List<Item>> shared() => _q('sharedWithMe=true and trashed=false');
  @override
  Future<List<Item>> photos() => _q("mimeType contains 'image/' and trashed=false", order: 'modifiedTime desc', pages: 3);
  @override
  Future<List<Item>> search(String q) => _q("name contains '${_esc(q)}' and trashed=false", pages: 2);
  @override
  Future<void> createFolder(String parent, String name) => _send('POST', 'files', body: {'name': name, 'mimeType': _folder, 'parents': [parent]});
  @override
  Future<void> rename(Item i, String name) => _send('PATCH', 'files/${i.id}', body: {'name': name});
  @override
  Future<void> trash(Item i) => _send('PATCH', 'files/${i.id}', body: {'trashed': true});

  @override
  Future<(int, int?)> quota() async {
    final j = jsonDecode((await _send('GET', 'about', q: {'fields': 'storageQuota(limit,usage)'})).body);
    final s = j['storageQuota'] as Map<String, dynamic>;
    return (int.parse('${s['usage']}'), s['limit'] == null ? null : int.parse('${s['limit']}'));
  }

  @override
  Future<void> download(Item i, File out, void Function(double) progress) async {
    final req = http.Request('GET', Uri.https('www.googleapis.com', '/drive/v3/files/${i.id}', {'alt': 'media'}))..headers.addAll(await _a.headers().timeout(_requestTimeout));
    final res = await _c.send(req).timeout(_requestTimeout);
    if (res.statusCode != 200) throw DriveError(res.statusCode, 'Download failed (${res.statusCode}).');
    final total = res.contentLength ?? i.size;
    var got = 0;
    final sink = out.openWrite();
    try {
      await for (final b in res.stream.timeout(_requestTimeout)) {
        sink.add(b);
        got += b.length;
        if (total > 0) progress(got / total);
      }
    } finally {
      await sink.close();
    }
  }
}
