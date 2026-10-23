import 'dart:math';

/// One key per create-form-instance (generate it once in a State field), reused
/// across retries of that same submission so a network retry or double-tap can't
/// create a duplicate record. A fresh key naturally appears each time the screen is
/// opened again for a new entry. 128 bits of entropy - equivalent to a UUID v4,
/// without pulling in the `uuid` package for this alone.
String newIdempotencyKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
