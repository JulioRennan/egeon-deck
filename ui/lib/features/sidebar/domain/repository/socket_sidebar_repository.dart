import '../../../../core/adapters/organization_feed.dart';
import '../../../../core/domain/entities/organization.dart';
import '../entities/sidebar_tree.dart';
import 'sidebar_repository.dart';
import '../../../../core/adapters/egeon_socket_client.dart';
import '../errors/sidebar_error.dart';

/// A barra lateral falando com o core Rust pelo tópico `workspaces`.
class SocketSidebarRepository implements SidebarRepository {
  const SocketSidebarRepository(this._feed);

  final OrganizationFeed _feed;

  /// Recusa e queda do socket viram [SidebarError].
  Future<EgeonMessage> _command(String cmd, [EgeonMessage args = const {}]) =>
      _feed
          .command(cmd, args)
          .failingAs(refused: SidebarRefused.new, offline: SidebarOffline.new);

  @override
  Stream<SidebarTree> watch() =>
      _feed.watch().map(SidebarTree.fromOrganization);

  /// Escolher uma bancada na barra a abre (ganha aba, se não tinha) e a põe na
  /// tela.
  @override
  Future<void> select(String benchId) =>
      _command('open_workbench', {'workbench': benchId});

  /// Recolher é o contrário do que está na tela agora.
  @override
  Future<void> toggleWorkspace(String workspaceId) {
    final now = _feed.last?.workspace(workspaceId)?.collapsed ?? false;
    return _command('set_workspace', {
      'workspace': workspaceId,
      'collapsed': !now,
    });
  }

  @override
  Future<void> toggleProject(String workspaceId, String projectId) {
    final now = _feed.last?.project(projectId)?.collapsed ?? false;
    return _command('set_project', {'project': projectId, 'collapsed': !now});
  }

  @override
  Future<void> toggleDrawer(String workspaceId) =>
      _command('move', {'kind': 'drawer', 'item': workspaceId, 'to': 0});

  /// Guardar e tirar pelo menu vão para o fim do lado de destino.
  @override
  Future<void> setStored(
    String workspaceId,
    String projectId, {
    required bool stored,
  }) {
    final others = [
      for (final p
          in _feed.last?.workspace(workspaceId)?.projects ?? <OrgProject>[])
        if (p.id != projectId && p.stored == stored) p,
    ];
    return _command('move', {
      'kind': stored ? 'store' : 'unstore',
      'item': projectId,
      'parent': workspaceId,
      'to': others.length,
    });
  }

  @override
  Future<void> moveWorkspace(String id, int position) =>
      _command('move', {'kind': 'workspace', 'item': id, 'to': position});

  /// Soltar na gaveta guarda o projeto já na posição; soltar fora dela, vindo
  /// da gaveta, tira. É um comando só.
  @override
  Future<void> moveProject(
    String id,
    String workspaceId,
    int position, {
    required bool stored,
  }) {
    final wasStored = _feed.last?.project(id)?.stored ?? false;
    return _command('move', {
      'kind': stored ? 'store' : (wasStored ? 'unstore' : 'project'),
      'item': id,
      'parent': workspaceId,
      'to': position,
    });
  }

  /// O core responde `lands` quando aceita e `ok:false` quando não; a recusa
  /// aqui é só "não há onde cair", sem mostrar aviso.
  @override
  Future<MoveLanding?> planMove(
    String kind,
    String item, {
    String? parent,
    required int to,
  }) async {
    try {
      final reply = await _command('plan_move', {
        'kind': kind,
        'item': item,
        'parent': ?parent,
        'to': to,
      });
      final lands = reply['lands'] as Map<String, Object?>?;
      if (lands == null) return null;
      return MoveLanding(
        parent: lands['parent'] as String?,
        to: lands['to']! as int,
      );
    } on SidebarRefused {
      return null;
    }
  }

  @override
  Future<void> moveBench(String id, String projectId, int position) => _command(
    'move',
    {'kind': 'workbench', 'item': id, 'parent': projectId, 'to': position},
  );
}
