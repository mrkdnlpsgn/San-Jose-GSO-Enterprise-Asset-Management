import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/transfer_service.dart';
import '../model/transfer_model.dart';

/// Transfer requests - every request for an admin, your own for staff.
final transfersProvider = FutureProvider.autoDispose<List<TransferModel>>((ref) => TransferService().list());
