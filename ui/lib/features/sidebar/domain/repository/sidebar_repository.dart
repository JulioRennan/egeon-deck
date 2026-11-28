import '../entities/sidebar_tree.dart';

/// A barra lateral. A árvore, a ordem e onde cada item pode cair são do core
/// Rust; aqui só se pergunta e se manda o gesto.
/// Onde o core diz que o item cairia, sem aplicar nada.
class MoveLanding {
  const MoveLanding({this.parent, required this.to});

  final String? parent;
  final int to;

  @override
  bool operator ==(Object other) =>
      other is MoveLanding && other.parent == parent && other.to == to;

  @override
  int get hashCode => Object.hash(parent, to);
}

abstract interface class SidebarRepository {
  Stream<SidebarTree> watch();

  Future<void> select(String benchId);

  Future<void> toggleWorkspace(String workspaceId);

  Future<void> toggleProject(String workspaceId, String projectId);

  Future<void> toggleDrawer(String workspaceId);

  Future<void> setStored(
    String workspaceId,
    String projectId, {
    required bool stored,
  });

  Future<void> moveWorkspace(String id, int position);

  Future<void> moveProject(
    String id,
    String workspaceId,
    int position, {
    required bool stored,
  });

  Future<void> moveBench(String id, String projectId, int position);

  /// Pergunta ao core onde o item cairia: `null` se ele recusa. [kind] é um de
  /// `workspace`, `project`, `workbench` ou `store`; [to] é a posição entre os
  /// irmãos que o ponteiro aponta.
  Future<MoveLanding?> planMove(
    String kind,
    String item, {
    String? parent,
    required int to,
  });
}
