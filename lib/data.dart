import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'drive.dart';

class Pal {
  static bool dark = false;
  static Color get canvas => dark ? const Color(0xFF0F1216) : const Color(0xFFF4F5F7);
  static Color get surf => dark ? const Color(0xFF171B21) : Colors.white;
  static Color get line => dark ? const Color(0xFF282F38) : const Color(0xFFE1E4E9);
  static Color get tx => dark ? const Color(0xFFE6E9ED) : const Color(0xFF1B1F24);
  static Color get sub => dark ? const Color(0xFF8F99A6) : const Color(0xFF5E6773);
  static Color get ac => dark ? const Color(0xFF5B9CFF) : const Color(0xFF1F5FD1);
  static Color get onAc => dark ? const Color(0xFF0A1830) : Colors.white;
  static Color get acSoft => ac.withAlpha(dark ? 46 : 28);
  static const danger = Color(0xFFD13438);
}

class Item {
  Item({required this.id, required this.name, this.folder = false, this.size = 0, required this.date, this.shared = false, this.mime = '', this.thumb, this.link});
  final String id;
  String name;
  final bool folder, shared;
  final int size;
  final DateTime date;
  final String mime;
  final String? thumb, link;
  bool get native => !folder && mime.startsWith('application/vnd.google-apps.');
  bool get isImage => mime.startsWith('image/') || const ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
  String get ext => folder || !name.contains('.') ? '' : name.split('.').last.toLowerCase();
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'size': size, 'date': date.toIso8601String(), 'shared': shared, 'mime': mime, 'link': link};
  static Item fromJson(Map<String, dynamic> j) => Item(id: j['id'], name: j['name'], size: j['size'] ?? 0, date: DateTime.parse(j['date']), shared: j['shared'] == true, mime: j['mime'] ?? '', link: j['link']);
}

String fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1048576) return '${(b / 1024).round()} KB';
  if (b < 1073741824) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(1)} GB';
}

const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String fmtDate(DateTime d) => '${d.day} ${_m[d.month - 1]} ${d.year}';
String fmtMonth(DateTime d) => '${_m[d.month - 1]} ${d.year}';

class DriveError implements Exception {
  DriveError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => message;
}

/// Provider boundary: UI only talks to this. Add other providers by implementing it.
abstract class Repo {
  bool get canOffline;
  Future<List<Item>> list(String parent);
  Future<List<Item>> recent();
  Future<List<Item>> shared();
  Future<List<Item>> photos();
  Future<List<Item>> search(String q);
  Future<void> createFolder(String parent, String name);
  Future<void> rename(Item i, String name);
  Future<void> trash(Item i);
  Future<(int, int?)> quota();
  Future<void> download(Item i, File out, void Function(double) progress);
}

Future<Directory> offlineDir() async {
  final d = Directory('${(await getApplicationSupportDirectory()).path}/offline');
  await d.create(recursive: true);
  return d;
}

enum Dest { files, recent, photos, shared, offline }
enum Sort { name, date, size }

class Crumb {
  Crumb(this.id, this.name);
  final String id, name;
}

/// Temporary diagnostics: stage log with no tokens, credentials or file names.
class Diag {
  static final log = <String>[];
  static String _last = '';
  static String _clean(String s) => s.replaceAll(RegExp(r'ya29\.[\w\-\.]+|eyJ[\w\-\.]+'), '<redacted>');
  static void add(String stage, [String detail = '']) {
    final t = DateTime.now().toIso8601String().substring(11, 23);
    final line = '$t $stage${detail.isEmpty ? '' : ' | ${_clean(detail)}'}';
    log.add(line);
    if (log.length > 300) log.removeAt(0);
    debugPrint('[CloudBox] $line');
  }

  /// Logs only when the detail changes (used from build methods).
  static void change(String stage, String detail) {
    if ('$stage$detail' == _last) return;
    _last = '$stage$detail';
    add(stage, detail);
  }
}

final messenger = GlobalKey<ScaffoldMessengerState>();
void toast(String m) => messenger.currentState?..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 4)));

class Store extends ChangeNotifier {
  late Repo repo;
  final auth = DriveAuth();
  bool ready = false, signedIn = false, signingIn = false, loading = false, grid = false, searching = false;
  String? authError, err;
  ThemeMode mode = ThemeMode.system;
  Dest dest = Dest.files;
  Sort sort = Sort.name;
  bool asc = true;
  String query = '';
  final path = <Crumb>[Crumb('root', 'My Drive')];
  List<Item> items = [];
  final selected = <String>{};
  final saved = <Item>[];
  final pending = <String, Item>{};
  final downloads = <String, double>{};
  (int, int?)? quota;
  int _gen = 0;
  Future<void>? _refreshing;

  void set(VoidCallback f) {
    f();
    notifyListeners();
  }

  bool isSaved(String id) => saved.any((s) => s.id == id);
  bool get canBack => selected.isNotEmpty || searching || (dest == Dest.files && path.length > 1) || dest != Dest.files;

  Future<void> init() async {
    Diag.add('init:start');
    try {
      final f = File('${(await offlineDir()).path}/index.json');
      if (await f.exists()) {
        for (final j in jsonDecode(await f.readAsString()) as List) {
          final it = Item.fromJson(j as Map<String, dynamic>);
          if (await File('${f.parent.path}/${it.id}').exists()) saved.add(it);
        }
      }
    } catch (_) {}
    final restored = await auth.silent();
    Diag.add('init:session-restored', 'user=$restored');
    if (restored) {
      repo = DriveRepo(auth);
      signedIn = true;
      _afterSignIn();
    }
    ready = true;
    Diag.add('init:ready', 'signedIn=$signedIn');
    notifyListeners();
  }

  void _afterSignIn() {
    refresh();
  }

  Future<void> _loadQuota() async {
    try {
      quota = await repo.quota();
    } catch (_) {
      // File browsing remains usable if the optional quota request fails.
    }
  }

  Future<void> refresh() {
    final active = _refreshing;
    if (active != null) return active;
    final request = Future.wait<void>([
      load(),
      _loadQuota(),
    ]).then((_) {
      notifyListeners();
    });
    _refreshing = request.whenComplete(() => _refreshing = null);
    return _refreshing!;
  }

  Future<void> signIn() async {
    set(() {
      signingIn = true;
      authError = null;
    });
    try {
      await auth.signIn();
      repo = DriveRepo(auth);
      signedIn = true;
      _afterSignIn();
    } catch (e) {
      authError = _authMsg(e);
    }
    set(() => signingIn = false);
  }

  Future<void> signOut() async {
    await auth.signOut();
    try {
      final d = await offlineDir();
      await d.delete(recursive: true);
    } catch (_) {}
    set(() {
      signedIn = false;
      items = [];
      saved.clear();
      selected.clear();
      path..clear()..add(Crumb('root', 'My Drive'));
      dest = Dest.files;
      query = '';
      searching = false;
      quota = null;
    });
  }

  String _authMsg(Object e) {
    final s = '$e';
    if (s.contains('sign_in_canceled')) return 'Sign-in was cancelled.';
    if (s.contains('network_error')) return 'No network connection.';
    if (e is AuthException) return e.message;
    if (e is FirebaseAuthException) {
      return switch (e.code) {
        'account-exists-with-different-credential' => 'This Google account is already linked to another sign-in method.',
        'network-request-failed' => 'No network connection. Check your connection and try again.',
        'invalid-credential' => 'Google authentication was rejected. Sign in again.',
        _ => e.message ?? 'Firebase authentication failed (${e.code}).',
      };
    }
    if (s.contains('ApiException: 10') || s.contains('12500') || s.contains('sign_in_failed')) {
      return 'Google rejected this build. Create an Android OAuth client for package com.cloudbox.cloud_box with this build\'s SHA-1, add your account as a test user, and enable the Drive API. Details: $s';
    }
    return s;
  }

  String _msg(Object e) => switch (e) {
        SocketException() => 'No network connection.',
        TimeoutException() => 'The Google Drive request timed out. Check your connection and try again.',
        DriveError() => e.message,
        AuthException() => e.message,
        _ => '$e',
      };

  Future<void> load() async {
    final g = ++_gen;
    Diag.add('store:load-start', 'gen=$g dest=${dest.name}');
    loading = true;
    err = null;
    selected.clear();
    notifyListeners();
    try {
      final r = switch (dest) {
        Dest.files => query.isNotEmpty ? await repo.search(query) : await repo.list(path.last.id),
        Dest.recent => await repo.recent(),
        Dest.photos => await repo.photos(),
        Dest.shared => await repo.shared(),
        Dest.offline => <Item>[],
      };
      if (g == _gen) {
        items = r;
        Diag.add('store:load-success', 'gen=$g items=${r.length}');
      }
    } catch (e) {
      if (g == _gen) {
        err = _msg(e);
        items = [];
        Diag.add('store:load-failed', 'gen=$g ${e.runtimeType}: ${_msg(e)}');
      }
    } finally {
      Diag.add('store:load-cleanup', 'gen=$g current=${g == _gen}');
      if (g == _gen) {
        loading = false;
        notifyListeners();
        Diag.add('store:notified', 'loading=false items=${items.length}');
      }
    }
  }

  void go(Dest d) {
    dest = d;
    query = '';
    searching = false;
    load();
  }

  void open(Item f) {
    if (dest != Dest.files || query.isNotEmpty) path..clear()..add(Crumb('root', 'My Drive'));
    path.add(Crumb(f.id, f.name));
    dest = Dest.files;
    query = '';
    searching = false;
    load();
  }

  void crumbTo(int i) {
    path.removeRange(i + 1, path.length);
    load();
  }

  void search(String q) {
    query = q.trim();
    dest = Dest.files;
    load();
  }

  void endSearch() {
    final had = query.isNotEmpty;
    searching = false;
    query = '';
    if (had) {
      load();
    } else {
      notifyListeners();
    }
  }

  void back() {
    if (selected.isNotEmpty) {
      set(selected.clear);
    } else if (searching) {
      endSearch();
    } else if (dest == Dest.files && path.length > 1) {
      path.removeLast();
      load();
    } else if (dest != Dest.files) {
      go(Dest.files);
    }
  }

  void toggleSel(String id) => set(() => selected.contains(id) ? selected.remove(id) : selected.add(id));

  Future<void> _do(Future<void> Function() f, String fail) async {
    try {
      await f();
    } catch (e) {
      toast('$fail ${_msg(e)}');
    }
    await load();
  }

  Future<void> newFolder(String n) => _do(() => repo.createFolder(path.last.id, n), 'Couldn\'t create folder.');
  Future<void> rename(Item i, String n) => _do(() => repo.rename(i, n), 'Couldn\'t rename.');
  Future<void> trash(Iterable<Item> l) => _do(() async {
        for (final i in l.toList()) {
          await repo.trash(i);
          if (isSaved(i.id)) await removeOffline(i);
        }
      }, 'Couldn\'t move to bin.');

  List<Item> get shown {
    if (dest == Dest.offline) return [...pending.values, ...saved];
    final l = items.toList();
    if (dest == Dest.recent || dest == Dest.photos) return l;
    l.sort((a, b) {
      if (a.folder != b.folder) return a.folder ? -1 : 1;
      final c = switch (sort) {
        Sort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        Sort.date => a.date.compareTo(b.date),
        Sort.size => a.size.compareTo(b.size),
      };
      return asc ? c : -c;
    });
    return l;
  }

  Future<void> _persist() async {
    final d = await offlineDir();
    await File('${d.path}/index.json').writeAsString(jsonEncode(saved.map((e) => e.toJson()).toList()));
  }

  Future<void> saveOffline(Item i) async {
    if (!repo.canOffline || i.folder || i.native || isSaved(i.id) || downloads.containsKey(i.id)) return;
    set(() {
      downloads[i.id] = 0;
      pending[i.id] = i;
    });
    final out = File('${(await offlineDir()).path}/${i.id}');
    try {
      await repo.download(i, out, (p) {
        if (p - (downloads[i.id] ?? 0) > .02) set(() => downloads[i.id] = p);
      });
      saved.add(i);
      await _persist();
      toast('“${i.name}” is available offline.');
    } catch (e) {
      try {
        await out.delete();
      } catch (_) {}
      toast('Download failed. ${_msg(e)}');
    }
    set(() {
      downloads.remove(i.id);
      pending.remove(i.id);
    });
  }

  Future<void> removeOffline(Item i) async {
    try {
      await File('${(await offlineDir()).path}/${i.id}').delete();
    } catch (_) {}
    saved.removeWhere((s) => s.id == i.id);
    await _persist();
    notifyListeners();
  }

  GoogleSignInAccount? get user => auth.user;
}

final store = Store();
