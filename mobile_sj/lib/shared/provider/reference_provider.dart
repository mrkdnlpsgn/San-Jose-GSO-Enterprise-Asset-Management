import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reference_service.dart';
import '../../features/assets/model/asset_model.dart';

final referenceServiceProvider = Provider<ReferenceService>((ref) => ReferenceService());

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) {
  return ref.watch(referenceServiceProvider).getCategories();
});

// Every category's articles; the asset form shows the chosen category's.
final articlesProvider = FutureProvider<List<ArticleModel>>((ref) {
  return ref.watch(referenceServiceProvider).getArticles();
});

final officesProvider = FutureProvider<List<OfficeModel>>((ref) {
  return ref.watch(referenceServiceProvider).getOffices();
});

final personnelProvider = FutureProvider<List<PersonnelModel>>((ref) {
  return ref.watch(referenceServiceProvider).getPersonnel();
});
