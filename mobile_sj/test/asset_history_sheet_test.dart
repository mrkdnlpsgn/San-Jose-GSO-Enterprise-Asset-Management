import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:san_jose_eam_mobile/core/theme/app_theme.dart';
import 'package:san_jose_eam_mobile/features/asset_history/model/asset_history_model.dart';
import 'package:san_jose_eam_mobile/features/asset_history/provider/asset_history_provider.dart';
import 'package:san_jose_eam_mobile/features/assets/model/asset_model.dart';
import 'package:san_jose_eam_mobile/features/assets/widgets/asset_history_sheet.dart';
import 'package:san_jose_eam_mobile/features/disposal/provider/disposal_provider.dart';
import 'package:san_jose_eam_mobile/features/maintenance/provider/maintenance_provider.dart';

final _asset = AssetModel.fromJson({'id': 7, 'propertyNumber': 'COA-2016-902', 'description': 'Split-type Aircon'});

AssetHistoryModel _event(int id, String type, String date, {String? to}) => AssetHistoryModel.fromJson({
      'id': id,
      'asset': {'id': 7, 'propertyNumber': 'COA-2016-902', 'description': 'Split-type Aircon'},
      'eventType': type,
      'toOffice': to == null ? null : {'id': 2, 'officeName': to},
      'performedBy': {'id': 1, 'username': 'admin', 'fullName': 'GSO Admin'},
      'eventDate': date,
    });

void main() {
  testWidgets('scanned asset history sheet lists only that asset', (tester) async {
    final asked = <int>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        assetHistoryProvider.overrideWith((ref, id) async {
          asked.add(id);
          return [
            _event(1, 'REGISTERED', '2016-03-01T08:00:00Z'),
            _event(2, 'TRANSFERRED', '2021-06-15T08:00:00Z', to: 'Accounting Office'),
          ];
        }),
        maintenanceByAssetProvider.overrideWith((ref, id) async => []),
        disposalByAssetProvider.overrideWith((ref, id) async => []),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => showAssetHistorySheet(context, _asset), child: const Text('open')),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Asset History'), findsOneWidget);
    expect(find.text('COA-2016-902 · Split-type Aircon'), findsOneWidget);
    expect(find.text('Registered'), findsOneWidget);
    expect(find.text('Transferred'), findsOneWidget);
    expect(asked, [7]); // fetched for the scanned asset only
  });
}
