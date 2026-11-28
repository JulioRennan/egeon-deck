import '../entities/usage_view.dart';

abstract interface class UsageRepository {
  /// O consumo da bancada [workbenchId]: inteiro a cada mudança.
  Stream<UsageView> watch(String workbenchId);
}
