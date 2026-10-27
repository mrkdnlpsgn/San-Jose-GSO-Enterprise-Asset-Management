import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/provider/settings_provider.dart';
import '../data/report_definitions.dart';
import '../model/report_definition.dart';

final reportDefinitionsProvider = Provider<List<ReportDefinition>>((ref) => buildReportDefinitions());

final reportDataProvider = FutureProvider.autoDispose.family<List<ReportRow>, String>((ref, reportId) {
  final report = ref.watch(reportDefinitionsProvider).firstWhere((r) => r.id == reportId);
  return report.load();
});

const _kRpcppeSettings = 'rpcppe-settings';

/// The RPCPPE's report details, remembered on this phone so they needn't be retyped each time
/// (the web keeps them in its browser the same way). The plain reports print their entity and
/// fund cluster from here too.
class RpcppeSettingsNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_kRpcppeSettings);
    try {
      final saved = raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
      return {...rpcppeDefaults, for (final e in saved.entries) e.key: '${e.value ?? ''}'};
    } catch (_) {
      return {...rpcppeDefaults};
    }
  }

  void set(String key, String value) {
    state = {...state, key: value};
    ref.read(sharedPreferencesProvider).setString(_kRpcppeSettings, jsonEncode(state));
  }
}

final rpcppeSettingsProvider = NotifierProvider<RpcppeSettingsNotifier, Map<String, String>>(RpcppeSettingsNotifier.new);
