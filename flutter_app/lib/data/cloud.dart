import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Casri POS — cloud sync, ported 1:1 from the web app's cloud.js so both
/// versions share ONE Firebase backend and the same documents.
///
///   auth  → identitytoolkit.googleapis.com   (email + password)
///   data  → firestore.googleapis.com/v1      (Bearer idToken)
///
/// One Firestore document per storage key, under the signed-in user:
///   casripos/{uid}/keys/{pos_prod | pos_sales | …}
/// Each doc holds the same JSON string kept on-device, plus a ms timestamp.
/// Newest timestamp wins — one shop edits at a time, so last-writer-wins is safe.

// Public web API key + project id. Safe to ship: they identify the project, they
// do not grant access. Access is Firebase Auth + Firestore rules scoped to uid.
const _apiKey = 'AIzaSyCEZxp9W7_h2Nu1qs_wiQdrbXARVb5yvg8';
const _projectId = 'isguul-togdheer';

/// The MareegTech super-admin. Signs in through the normal workspace login and
/// gets the Workspaces approval console instead of a till.
const kMasterEmail = 'admin@mareegtech.com';

const cloudKeys = [
  'pos_biz_list', 'pos_current_biz', 'pos_prod', 'pos_sales',
  'pos_inv', 'pos_acc', 'pos_fx', 'pos_recovery_email',
];

/// The MPQ plan tiers, matching the web app.
class Plan {
  final String id;
  final String label;
  final int maxProducts;
  final int registers;
  const Plan(this.id, this.label, this.maxProducts, this.registers);
}

const plans = <String, Plan>{
  'MPQ50': Plan('MPQ50', 'MPQ50 — 50 products, 1 register', 50, 1),
  'MPQ100': Plan('MPQ100', 'MPQ100 — 100 products, 2 registers', 100, 2),
  'MPQ200': Plan('MPQ200', 'MPQ200 — 200 products, 3 registers', 200, 3),
};

/// Result of inspecting either side before choosing a sync direction.
class SyncInfo {
  final bool has;
  final int businesses, products, sales;
  const SyncInfo(
      {this.has = false, this.businesses = 0, this.products = 0, this.sales = 0});
}

/// A workspace row in the approval registry.
class Workspace {
  final String uid, email, name, plan;
  final bool approved;
  final int createdAt;
  const Workspace({
    required this.uid,
    this.email = '',
    this.name = '',
    this.plan = '',
    this.approved = false,
    this.createdAt = 0,
  });
}

class Cloud extends ChangeNotifier {
  SharedPreferences? _sp;

  String email = '';
  String uid = '';
  String _idToken = '';
  String _refreshToken = '';
  int _tokenAt = 0;
  bool on = false;
  bool busy = false;
  int lastSync = 0;
  String lastError = '';

  // 'off' | 'sync' | 'ok' | 'err'
  String status = 'off';

  final Map<String, bool> _pending = {};
  Timer? _timer;

  bool get master =>
      on && email.trim().toLowerCase() == kMasterEmail.trim().toLowerCase();

  void _paint(String s) {
    status = s;
    notifyListeners();
  }

  // ── session persistence (shares the web app's `pos_cloud` shape) ──────────
  Future<void> load() async {
    _sp ??= await SharedPreferences.getInstance();
    try {
      final raw = _sp!.getString('pos_cloud');
      if (raw != null && raw.isNotEmpty) {
        final s = Map<String, dynamic>.from(jsonDecode(raw));
        email = (s['email'] ?? '').toString();
        uid = (s['uid'] ?? '').toString();
        _refreshToken = (s['refreshToken'] ?? '').toString();
        lastSync = (s['lastSync'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    _sp ??= await SharedPreferences.getInstance();
    await _sp!.setString(
        'pos_cloud',
        jsonEncode({
          'email': email,
          'uid': uid,
          'refreshToken': _refreshToken,
          'lastSync': lastSync,
        }));
  }

  // ── auth ──────────────────────────────────────────────────────────────────
  Uri _authUrl(String method) => Uri.parse(
      'https://identitytoolkit.googleapis.com/v1/accounts:$method?key=$_apiKey');

  Future<Map<String, dynamic>> _auth(
      String method, String em, String pw) async {
    final r = await http.post(_authUrl(method),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
            {'email': em, 'password': pw, 'returnSecureToken': true}));
    final j = Map<String, dynamic>.from(jsonDecode(r.body));
    if (r.statusCode >= 400) {
      final code = (j['error']?['message'] ?? 'AUTH_FAILED').toString();
      throw CloudError(code);
    }
    return j;
  }

  Future<void> _applySession(Map<String, dynamic> j) async {
    _idToken = (j['idToken'] ?? '').toString();
    _refreshToken = (j['refreshToken'] ?? '').toString();
    uid = (j['localId'] ?? '').toString();
    _tokenAt = DateTime.now().millisecondsSinceEpoch;
    on = true;
    await _save();
  }

  // idTokens last an hour; refresh a little early.
  Future<String> _freshToken() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_idToken.isNotEmpty && (now - _tokenAt) < 50 * 60 * 1000) {
      return _idToken;
    }
    if (_refreshToken.isEmpty) throw CloudError('NO_SESSION');
    final r = await http.post(
        Uri.parse('https://securetoken.googleapis.com/v1/token?key=$_apiKey'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body:
            'grant_type=refresh_token&refresh_token=${Uri.encodeComponent(_refreshToken)}');
    final j = Map<String, dynamic>.from(jsonDecode(r.body));
    if (j['id_token'] == null) throw CloudError('REFRESH_FAILED');
    _idToken = j['id_token'].toString();
    _refreshToken = (j['refresh_token'] ?? _refreshToken).toString();
    _tokenAt = DateTime.now().millisecondsSinceEpoch;
    await _save();
    return _idToken;
  }

  // ── firestore per-key docs ─────────────────────────────────────────────────
  Uri _docUrl(String key) => Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/casripos/$uid/keys/$key');

  Future<bool> _putKey(String key, String token) async {
    _sp ??= await SharedPreferences.getInstance();
    final raw = _sp!.getString(key);
    if (raw == null) return false;
    final body = jsonEncode({
      'fields': {
        'v': {'stringValue': raw},
        'ts': {
          'integerValue': DateTime.now().millisecondsSinceEpoch.toString()
        },
      }
    });
    final r = await http.patch(_docUrl(key),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: body);
    if (r.statusCode >= 400) throw CloudError(_httpErr(r));
    return true;
  }

  /// Returns {v, ts} or null when nothing is in the cloud yet.
  Future<Map<String, dynamic>?> _getKey(String key, String token) async {
    final r =
        await http.get(_docUrl(key), headers: {'Authorization': 'Bearer $token'});
    if (r.statusCode == 404) return null;
    if (r.statusCode >= 400) throw CloudError(_httpErr(r));
    final doc = Map<String, dynamic>.from(jsonDecode(r.body));
    final f = doc['fields'];
    if (f == null || f['v'] == null) return null;
    return {
      'v': f['v']['stringValue'],
      'ts': int.tryParse((f['ts']?['integerValue'] ?? '0').toString()) ?? 0,
    };
  }

  String _httpErr(http.Response r) {
    try {
      final j = Map<String, dynamic>.from(jsonDecode(r.body));
      return (j['error']?['message'] ?? 'HTTP ${r.statusCode}').toString();
    } catch (_) {
      return 'HTTP ${r.statusCode}';
    }
  }

  // ── push / pull ─────────────────────────────────────────────────────────────
  void queue(String key) {
    if (!on || !cloudKeys.contains(key)) return;
    _pending[key] = true;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 1500), flush);
  }

  Future<void> flush() async {
    if (!on || busy) return;
    final keys = _pending.keys.toList();
    if (keys.isEmpty) return;
    _pending.clear();
    busy = true;
    _paint('sync');
    try {
      final token = await _freshToken();
      for (final k in keys) {
        await _putKey(k, token);
      }
      lastSync = DateTime.now().millisecondsSinceEpoch;
      lastError = '';
      await _save();
      busy = false;
      _paint('ok');
    } catch (e) {
      for (final k in keys) {
        _pending[k] = true;
      }
      lastError = errText(e);
      busy = false;
      _paint('err');
    }
  }

  /// Pull every key. Remote wins only when its timestamp is newer than ours.
  /// Returns how many keys were applied locally.
  Future<int> pull({bool force = false}) async {
    if (!on) return 0;
    _sp ??= await SharedPreferences.getInstance();
    busy = true;
    _paint('sync');
    var applied = 0;
    try {
      final token = await _freshToken();
      for (final k in cloudKeys) {
        final remote = await _getKey(k, token);
        if (remote == null) continue;
        final localTs = _sp!.getInt('pos_ts_$k') ?? 0;
        final rts = (remote['ts'] as int?) ?? 0;
        if (!force && rts <= localTs) continue;
        if (_sp!.getString(k) == remote['v']) continue;
        await _sp!.setString(k, remote['v'].toString());
        await _sp!.setInt('pos_ts_$k', rts);
        applied++;
      }
      lastSync = DateTime.now().millisecondsSinceEpoch;
      lastError = '';
      await _save();
      busy = false;
      _paint('ok');
      return applied;
    } catch (e) {
      lastError = errText(e);
      busy = false;
      _paint('err');
      return 0;
    }
  }

  /// Push every key now — used after signing in on a device that already has data.
  Future<void> pushAll() async {
    if (!on) return;
    for (final k in cloudKeys) {
      _pending[k] = true;
    }
    await flush();
  }

  /// What is already in the cloud for this account? Used at sign-in to choose
  /// direction. NEVER infer this from timestamps — a fresh install has newer
  /// stamps than a PC that uploaded yesterday, so a timestamp guess would push
  /// the empty device over the real data and destroy it.
  Future<SyncInfo> remoteInfo() async {
    final token = await _freshToken();
    var has = false;
    var b = 0, p = 0, s = 0;
    for (final k in cloudKeys) {
      final r = await _getKey(k, token);
      if (r == null || r['v'] == null) continue;
      var n = 0;
      try {
        final a = jsonDecode(r['v'].toString());
        n = a is List ? a.length : 0;
      } catch (_) {}
      if (k == 'pos_biz_list') b = n;
      if (k == 'pos_prod') p = n;
      if (k == 'pos_sales') s = n;
      if (n > 0) has = true;
    }
    return SyncInfo(has: has, businesses: b, products: p, sales: s);
  }

  Future<SyncInfo> localInfo() async {
    _sp ??= await SharedPreferences.getInstance();
    int n(String k) {
      try {
        final a = jsonDecode(_sp!.getString(k) ?? '[]');
        return a is List ? a.length : 0;
      } catch (_) {
        return 0;
      }
    }

    return SyncInfo(
        businesses: n('pos_biz_list'),
        products: n('pos_prod'),
        sales: n('pos_sales'));
  }

  // ── public actions ──────────────────────────────────────────────────────────
  /// Signs in (or signs up). The CALLER decides which way data should move.
  Future<SyncInfo> signIn(String em, String pw, {bool isNew = false}) async {
    final j = await _auth(isNew ? 'signUp' : 'signInWithPassword', em, pw);
    email = em;
    await _applySession(j);
    _paint('ok');
    return remoteInfo();
  }

  Future<void> signOut() async {
    on = false;
    _idToken = '';
    _refreshToken = '';
    uid = '';
    email = '';
    _pending.clear();
    await _save();
    _paint('off');
  }

  // ── workspace approval registry ─────────────────────────────────────────────
  //  casripos_workspaces/{uid}: { email, name, plan, approved, createdAt }.
  //  A client reads/writes only its OWN doc; the master lists all and flips
  //  `approved`. Holds NO shop data — products/sales stay private to each uid.
  Uri _wsUrl([String? u]) => Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/casripos_workspaces/${u ?? uid}');

  Future<void> registerWorkspace(String name, String plan) async {
    final token = await _freshToken();
    final body = jsonEncode({
      'fields': {
        'email': {'stringValue': email},
        'name': {'stringValue': name},
        'plan': {'stringValue': plan},
        'approved': {'booleanValue': false},
        'createdAt': {
          'integerValue': DateTime.now().millisecondsSinceEpoch.toString()
        },
      }
    });
    final r = await http.patch(_wsUrl(),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: body);
    if (r.statusCode >= 400) throw CloudError(_httpErr(r));
  }

  /// This account's approval status.
  Future<Workspace?> workspaceStatus() async {
    final token = await _freshToken();
    final r = await http.get(_wsUrl(), headers: {'Authorization': 'Bearer $token'});
    if (r.statusCode == 404) return null;
    if (r.statusCode >= 400) throw CloudError(_httpErr(r));
    final doc = Map<String, dynamic>.from(jsonDecode(r.body));
    final f = doc['fields'] ?? {};
    return Workspace(
      uid: uid,
      email: (f['email']?['stringValue'] ?? '').toString(),
      name: (f['name']?['stringValue'] ?? '').toString(),
      plan: (f['plan']?['stringValue'] ?? '').toString(),
      approved: f['approved']?['booleanValue'] == true,
    );
  }

  /// Master: list every workspace.
  Future<List<Workspace>> listWorkspaces() async {
    final token = await _freshToken();
    final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/casripos_workspaces?pageSize=300');
    final r = await http.get(url, headers: {'Authorization': 'Bearer $token'});
    if (r.statusCode >= 400) throw CloudError(_httpErr(r));
    final j = Map<String, dynamic>.from(jsonDecode(r.body));
    final docs = (j['documents'] as List?) ?? [];
    return docs.map((d) {
      final doc = Map<String, dynamic>.from(d);
      final f = doc['fields'] ?? {};
      final nm = (doc['name'] ?? '').toString();
      return Workspace(
        uid: nm.substring(nm.lastIndexOf('/') + 1),
        email: (f['email']?['stringValue'] ?? '').toString(),
        name: (f['name']?['stringValue'] ?? '').toString(),
        plan: (f['plan']?['stringValue'] ?? '').toString(),
        approved: f['approved']?['booleanValue'] == true,
        createdAt:
            int.tryParse((f['createdAt']?['integerValue'] ?? '0').toString()) ??
                0,
      );
    }).toList();
  }

  /// Master: approve (or revoke) a workspace — patches only `approved`.
  Future<void> approveWorkspace(String u, bool approved) async {
    final token = await _freshToken();
    final url = Uri.parse(
        'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents/casripos_workspaces/$u?updateMask.fieldPaths=approved');
    final r = await http.patch(url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: jsonEncode({
          'fields': {
            'approved': {'booleanValue': approved}
          }
        }));
    if (r.statusCode >= 400) throw CloudError(_httpErr(r));
  }

  /// Restore the session on boot and return keys applied by a quiet pull.
  Future<int> boot() async {
    await load();
    if (_refreshToken.isEmpty) {
      _paint('off');
      return 0;
    }
    on = true;
    _paint('sync');
    try {
      await _freshToken();
      return await pull(force: false);
    } catch (e) {
      lastError = errText(e);
      _paint('err');
      return 0;
    }
  }

  // Friendly text for Firebase's shouty error codes.
  static String errText(Object e) {
    final code = e is CloudError ? e.code : e.toString();
    const m = {
      'EMAIL_NOT_FOUND': 'No account with that email',
      'INVALID_PASSWORD': 'Wrong password',
      'INVALID_LOGIN_CREDENTIALS': 'Wrong email or password',
      'EMAIL_EXISTS': 'That email already has an account',
      'WEAK_PASSWORD': 'Password must be at least 6 characters',
      'INVALID_EMAIL': "That email address isn't valid",
      'OPERATION_NOT_ALLOWED': 'Email sign-in is not enabled',
      'NO_SESSION': 'Sign in first',
      'TOO_MANY_ATTEMPTS_TRY_LATER': 'Too many attempts — try later',
    };
    for (final k in m.keys) {
      if (code.contains(k)) return m[k]!;
    }
    if (code.contains('SocketException') ||
        code.contains('Failed host lookup') ||
        code.contains('ClientException')) {
      return 'No internet connection';
    }
    return code;
  }
}

class CloudError implements Exception {
  final String code;
  CloudError(this.code);
  @override
  String toString() => code;
}

/// The one cloud client, shared by the store (for sync) and the UI (for status).
final cloud = Cloud();
