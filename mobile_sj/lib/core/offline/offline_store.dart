import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Files the app keeps on the phone for offline use, one folder per signed-in account
/// (`<documents>/offline/<username>/`) so one person's saved data never shows for another.
/// Everything is JSON; writes go to a temp file first and are renamed into place, so a crash
/// mid-write leaves the previous copy intact.
class OfflineStore {
  OfflineStore._();
  static final OfflineStore instance = OfflineStore._();

  Directory? _root;
  String? _account;

  /// [at] replaces the app's documents folder (tests).
  Future<void> init({Directory? at}) async {
    final docs = at ?? await getApplicationDocumentsDirectory();
    _root = Directory('${docs.path}/offline');
    await _root!.create(recursive: true);
  }

  /// The account whose folder is in use; null before anyone signs in.
  String? get account => _account;

  void useAccount(String? username) => _account = username;

  /// The shared folder (not tied to an account) - the outbox lives here, tagged per item.
  Directory get rootDir => _root!;

  /// This account's folder, or null when nobody is signed in.
  Directory? accountDir([String sub = '']) {
    final a = _account;
    if (_root == null || a == null) return null;
    final safe = a.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    return Directory('${_root!.path}/$safe${sub.isEmpty ? '' : '/$sub'}');
  }

  static Future<Object?> readJson(File f) async {
    try {
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null; // unreadable (half-written by an older build) - treat as missing
    }
  }

  static Future<void> writeJson(File f, Object? value) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(f.path);
  }

  /// Stable across app runs (String.hashCode isn't), for file names from cache keys.
  static String fnv1a(String s) {
    // 32-bit FNV-1a, twice with different seeds, so the result stays exact on every platform.
    String run(int seed) {
      var h = seed;
      for (final c in utf8.encode(s)) {
        h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
      }
      return h.toRadixString(16).padLeft(8, '0');
    }

    return run(0x811c9dc5) + run(0x050c5d1f);
  }
}
