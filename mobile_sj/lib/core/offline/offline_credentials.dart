import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'offline_store.dart';

/// Why an offline sign-in was refused.
enum OfflineSignInProblem {
  /// This account has never fully signed in online on this phone.
  notOnThisPhone,
  /// The last online sign-in was more than [OfflineCredentials.validFor] ago.
  expired,
  /// Too many wrong passwords offline - the next sign-in must be online.
  locked,
  wrongPassword,
}

class OfflineSignInException implements Exception {
  final OfflineSignInProblem problem;
  const OfflineSignInException(this.problem);

  String get message => switch (problem) {
        OfflineSignInProblem.notOnThisPhone =>
          "You're offline, and this account hasn't signed in on this phone before. "
              'Connect to Wi-Fi or mobile data to sign in.',
        OfflineSignInProblem.expired => "You're offline, and offline sign-in has expired. It lasts "
            '${OfflineCredentials.validFor.inDays} days after you last signed in online. Connect to sign in.',
        OfflineSignInProblem.locked => 'Too many wrong passwords. Connect to Wi-Fi or mobile data to sign in.',
        OfflineSignInProblem.wrongPassword => 'The username or password is incorrect. Please check and try again.',
      };

  @override
  String toString() => message;
}

/// Lets someone who fully signed in online on this phone (password and, if asked, the emailed
/// code) sign in again with the same password while offline, for [validFor] after that.
///
/// The password itself is never stored: only a salted PBKDF2-HMAC-SHA256 hash, in the app's
/// private folder (`<documents>/offline/credentials.json`). The server is not involved - an
/// offline session has no server session, so once back online the user signs in normally
/// before anything uploads.
class OfflineCredentials {
  OfflineCredentials._();
  static final OfflineCredentials instance = OfflineCredentials._();

  static const validFor = Duration(days: 7);
  static const _iterations = 60000;
  static const _maxWrongTries = 5;

  File get _file => File('${OfflineStore.instance.rootDir.path}/credentials.json');

  Future<Map<String, dynamic>> _all() async {
    final saved = await OfflineStore.readJson(_file);
    return saved is Map ? saved.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// After a complete online sign-in. [identifier] is what was typed (username or email).
  Future<void> remember({
    required String identifier,
    required String password,
    required Map<String, dynamic> user,
  }) async {
    final username = user['username'] as String;
    final salt = _randomBytes(16);
    final hash = await compute(_pbkdf2, (password, salt, _iterations));
    final all = await _all();
    final aliases = {
      username.toLowerCase(),
      identifier.trim().toLowerCase(),
      ...?((all[username] as Map?)?['aliases'] as List?)?.cast<String>(),
    };
    all[username] = {
      'salt': base64Encode(salt),
      'hash': base64Encode(hash),
      'iterations': _iterations,
      'signedInAt': DateTime.now().toUtc().toIso8601String(),
      'aliases': aliases.toList(),
      'user': user,
      'wrongTries': 0,
    };
    await OfflineStore.writeJson(_file, all);
  }

  /// Checks [password] for [identifier] and returns the saved user (as JSON), or throws
  /// [OfflineSignInException].
  Future<Map<String, dynamic>> verify(String identifier, String password, {DateTime? now}) async {
    final all = await _all();
    final id = identifier.trim().toLowerCase();
    final entry = all.entries
        .where((e) => e.value is Map && ((e.value as Map)['aliases'] as List? ?? const []).contains(id))
        .firstOrNull;
    if (entry == null) throw const OfflineSignInException(OfflineSignInProblem.notOnThisPhone);
    final rec = (entry.value as Map).cast<String, dynamic>();

    final at = DateTime.tryParse(rec['signedInAt'] as String? ?? '');
    if (at == null || (now ?? DateTime.now()).toUtc().difference(at) > validFor) {
      throw const OfflineSignInException(OfflineSignInProblem.expired);
    }
    final wrong = rec['wrongTries'] as int? ?? 0;
    if (wrong >= _maxWrongTries) throw const OfflineSignInException(OfflineSignInProblem.locked);

    final salt = base64Decode(rec['salt'] as String);
    final expected = base64Decode(rec['hash'] as String);
    final got = await compute(_pbkdf2, (password, salt, rec['iterations'] as int? ?? _iterations));
    if (!_sameBytes(got, expected)) {
      rec['wrongTries'] = wrong + 1;
      all[entry.key] = rec;
      await OfflineStore.writeJson(_file, all);
      throw OfflineSignInException(
          wrong + 1 >= _maxWrongTries ? OfflineSignInProblem.locked : OfflineSignInProblem.wrongPassword);
    }
    if (wrong > 0) {
      rec['wrongTries'] = 0;
      all[entry.key] = rec;
      await OfflineStore.writeJson(_file, all);
    }
    return (rec['user'] as Map).cast<String, dynamic>();
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  // Constant-time compare, so timing doesn't hint how much of the hash matched.
  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

/// PBKDF2-HMAC-SHA256, one 32-byte block. Runs in a background isolate (via compute).
@visibleForTesting
Uint8List pbkdf2ForTest(String password, List<int> salt, int iterations) => _pbkdf2((password, salt, iterations));

Uint8List _pbkdf2((String, List<int>, int) args) {
  final (password, salt, iterations) = args;
  final hmac = Hmac(sha256, utf8.encode(password));
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}
