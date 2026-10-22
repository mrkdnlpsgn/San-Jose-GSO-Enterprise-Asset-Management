import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:san_jose_eam_mobile/core/offline/asset_snapshot.dart';
import 'package:san_jose_eam_mobile/core/offline/offline_credentials.dart';
import 'package:san_jose_eam_mobile/core/offline/offline_store.dart';
import 'package:san_jose_eam_mobile/core/offline/outbox.dart';
import 'package:san_jose_eam_mobile/core/offline/response_cache.dart';

Map<String, dynamic> _asset(int id, String no, {String desc = 'Laptop', int office = 1, String updatedAt = 't0'}) => {
      'id': id,
      'propertyNumber': no,
      'description': desc,
      'category': {'id': 3, 'categoryName': 'ICT Equipment'},
      'office': {'id': office, 'officeName': office == 1 ? 'GSO' : 'MTO'},
      'condition': 'SERVICEABLE',
      'lifecycleStatus': 'ASSIGNED',
      'updatedAt': updatedAt,
    };

/// Answers every request with [status] and [data], or throws a connection error when [down].
class _FakeServer implements HttpClientAdapter {
  bool down = false;
  int status = 200;
  Object data = const {};
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls++;
    if (down) throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('offline_test');
    await OfflineStore.instance.init(at: tmp);
    OfflineStore.instance.useAccount('ict_staff');
    for (final i in Outbox.instance.items.toList()) {
      await Outbox.instance.remove(i);
    }
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('Outbox', () {
    test('an edit to a record created offline folds into the create', () async {
      final create = await Outbox.instance.add(
        kind: 'asset.create',
        method: 'POST',
        path: '/assets',
        body: {'description': 'Printer'},
        label: 'New asset Printer',
        preview: _asset(0, 'New asset', desc: 'Printer'),
      );
      expect(create.tempId, -1);
      expect(create.preview!['id'], -1);
      expect(create.idempotencyKey, isNotNull);

      await Outbox.instance.add(
        kind: 'asset.update',
        method: 'PUT',
        path: '/assets/-1',
        body: {'description': 'Printer (color)'},
        label: 'Edit asset New asset',
        preview: _asset(-1, 'New asset', desc: 'Printer (color)'),
      );
      expect(Outbox.instance.items, hasLength(1));
      expect(Outbox.instance.items.single.body, {'description': 'Printer (color)'});
      expect(Outbox.instance.items.single.method, 'POST');
    });

    test('a second edit of the same record replaces the first but keeps the original base', () async {
      await Outbox.instance.add(
          kind: 'asset.update', method: 'PUT', path: '/assets/5', body: {'remarks': 'a'}, baseUpdatedAt: 't0', label: 'x');
      await Outbox.instance.add(
          kind: 'asset.update', method: 'PUT', path: '/assets/5', body: {'remarks': 'b'}, baseUpdatedAt: 't9', label: 'x');
      final only = Outbox.instance.items.single;
      expect(only.body, {'remarks': 'b'});
      expect(only.baseUpdatedAt, 't0');
    });

    test('after a create uploads, items that used its temporary id point at the real one', () async {
      final asset = await Outbox.instance.add(kind: 'asset.create', method: 'POST', path: '/assets', body: {}, label: 'a');
      final temp = asset.tempId!;
      await Outbox.instance.add(
          kind: 'maintenance.create', method: 'POST', path: '/maintenance', body: {'assetId': temp}, label: 'm');
      await Outbox.instance.add(kind: 'photo.upload', method: 'POST', path: '/assets/$temp/evidence', label: 'p');
      await Outbox.instance.add(kind: 'photo.upload', method: 'POST', path: '/assets/${temp}0/evidence', label: 'other');

      await Outbox.instance.resolveTempId(temp, 812);
      final items = Outbox.instance.items;
      expect(items[1].body!['assetId'], 812);
      expect(items[2].path, '/assets/812/evidence');
      expect(items[3].path, '/assets/${temp}0/evidence', reason: 'a different id that starts the same is untouched');
    });

    test('items belong to the account that made them, and survive a reload', () async {
      await Outbox.instance.add(kind: 'transfer.create', method: 'POST', path: '/transfers', body: {}, label: 't');
      OfflineStore.instance.useAccount('admin');
      expect(Outbox.instance.items, isEmpty);
      OfflineStore.instance.useAccount('ict_staff');
      expect(Outbox.instance.items, hasLength(1));
      final saved = File('${tmp.path}/offline/outbox.json').readAsStringSync();
      expect(saved, contains('"username":"ict_staff"'));
    });
  });

  group('AssetSnapshot', () {
    test('searches and filters the saved list, with waiting changes laid over it', () async {
      await AssetSnapshot.instance.replaceAll([
        _asset(1, 'COA-2020-001', desc: 'Laptop'),
        _asset(2, 'COA-2020-002', desc: 'Aircon', office: 2),
      ]);
      await Outbox.instance.add(
        kind: 'asset.update',
        method: 'PUT',
        path: '/assets/2',
        body: {'description': 'Aircon (repaired)'},
        label: 'e',
        preview: _asset(2, 'COA-2020-002', desc: 'Aircon (repaired)', office: 2),
      );
      await Outbox.instance.add(
        kind: 'asset.create',
        method: 'POST',
        path: '/assets',
        body: {},
        label: 'n',
        preview: _asset(0, 'New asset', desc: 'Projector'),
      );

      final all = await AssetSnapshot.instance.query(size: 50);
      expect(all!.map((a) => a.id), [-1, 1, 2], reason: 'added offline comes first');
      expect((await AssetSnapshot.instance.byId(2))!.description, 'Aircon (repaired)');
      expect((await AssetSnapshot.instance.query(search: 'repaired'))!.single.id, 2);
      expect((await AssetSnapshot.instance.query(officeId: 2))!.single.id, 2);
      expect(await AssetSnapshot.instance.count(search: 'coa-2020'), 2);
      expect(await AssetSnapshot.instance.query(page: 1, size: 2), hasLength(1));
    });

    test("one account never sees another's saved list", () async {
      await AssetSnapshot.instance.replaceAll([_asset(1, 'A')]);
      OfflineStore.instance.useAccount('someone_else');
      expect(await AssetSnapshot.instance.available, isFalse);
      OfflineStore.instance.useAccount('ict_staff');
      expect(await AssetSnapshot.instance.available, isTrue);
    });
  });

  group('ResponseCacheInterceptor', () {
    late Dio dio;
    late _FakeServer server;
    late ResponseCacheInterceptor cache;

    setUp(() {
      server = _FakeServer();
      cache = ResponseCacheInterceptor();
      dio = Dio(BaseOptions(baseUrl: 'http://x/api'))
        ..httpClientAdapter = server
        ..interceptors.add(cache);
    });

    test('a GET answered once is answered from the phone when the server is unreachable', () async {
      server.data = [
        {'id': 1}
      ];
      await dio.get('/offices', queryParameters: {'b': 2, 'a': 1});
      server.down = true;
      final res = await dio.get('/offices', queryParameters: {'a': 1, 'b': 2});
      expect(res.data, [
        {'id': 1}
      ]);
      expect(res.extra['fromCache'], isTrue);
    });

    test('offline: a saved GET is answered without trying the network; others fail at once', () async {
      server.data = {'ok': true};
      await dio.get('/categories');
      cache.deviceOffline = true;
      final before = server.calls;
      expect((await dio.get('/categories')).data, {'ok': true});
      await expectLater(dio.get('/never-opened'), throwsA(isA<DioException>()));
      await expectLater(dio.post('/assets', data: {}), throwsA(isA<DioException>()));
      expect(server.calls, before, reason: 'nothing waited on the network');
    });

    test('sign-in and opted-out requests are never saved', () async {
      server.data = {'username': 'x'};
      await dio.get('/auth/me');
      await dio.get('/assets', options: Options(extra: {'noCache': true}));
      server.down = true;
      await expectLater(dio.get('/auth/me'), throwsA(isA<DioException>()));
      await expectLater(dio.get('/assets'), throwsA(isA<DioException>()));
    });
  });

  group('OfflineCredentials', () {
    final creds = OfflineCredentials.instance;
    final user = {'id': 4, 'username': 'ict_staff', 'role': 'STAFF'};

    test('PBKDF2 matches the RFC 7914 test vector', () {
      final out = pbkdf2ForTest('passwd', 'salt'.codeUnits, 1);
      expect(out.sublist(0, 8), [0x55, 0xac, 0x04, 0x6e, 0x56, 0xe3, 0x08, 0x9f]);
    });

    test('the same account signs in offline by username or the email it used, never storing the password', () async {
      await creds.remember(identifier: 'staff@sanjose.gov.ph', password: 'Secret#123', user: user);
      expect((await creds.verify('ict_staff', 'Secret#123'))['username'], 'ict_staff');
      expect((await creds.verify('STAFF@sanjose.gov.ph ', 'Secret#123'))['id'], 4);
      final saved = File('${tmp.path}/offline/credentials.json').readAsStringSync();
      expect(saved, isNot(contains('Secret#123')));
    });

    test('unknown account, expiry, wrong password and lockout', () async {
      await creds.remember(identifier: 'ict_staff', password: 'right', user: user);
      Future<OfflineSignInProblem?> problem(String id, String pw, {DateTime? now}) async {
        try {
          await creds.verify(id, pw, now: now);
          return null;
        } on OfflineSignInException catch (e) {
          return e.problem;
        }
      }

      expect(await problem('admin', 'right'), OfflineSignInProblem.notOnThisPhone);
      expect(await problem('ict_staff', 'right', now: DateTime.now().add(const Duration(days: 8))),
          OfflineSignInProblem.expired);
      expect(await problem('ict_staff', 'right', now: DateTime.now().add(const Duration(days: 6))), isNull);
      for (var i = 0; i < 4; i++) {
        expect(await problem('ict_staff', 'wrong'), OfflineSignInProblem.wrongPassword);
      }
      expect(await problem('ict_staff', 'wrong'), OfflineSignInProblem.locked);
      expect(await problem('ict_staff', 'right'), OfflineSignInProblem.locked, reason: 'locked until an online sign-in');
      await creds.remember(identifier: 'ict_staff', password: 'right', user: user);
      expect(await problem('ict_staff', 'right'), isNull);
    });
  });
}
