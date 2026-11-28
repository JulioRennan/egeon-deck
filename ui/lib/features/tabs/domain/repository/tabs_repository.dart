import '../entities/workbench_tab.dart';

/// As abas das bancadas abertas. Quem decide a ordem e a vizinha que assume ao
/// fechar é o core Rust; aqui só se pergunta e se manda o gesto.
abstract interface class TabsRepository {
  Stream<List<WorkbenchTab>> watch();

  Future<void> pick(String id);

  Future<void> close(String id);

  /// A ordem nova inteira, como ficou depois do arrasto.
  Future<void> reorder(List<String> ids);
}
