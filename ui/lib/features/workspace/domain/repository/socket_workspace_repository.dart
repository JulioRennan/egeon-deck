import '../../../../core/adapters/organization_feed.dart';
import '../entities/workspace_draft.dart';
import '../entities/workspace_saved.dart';
import 'workspace_repository.dart';
import '../../../../core/adapters/egeon_socket_client.dart';
import '../errors/workspace_error.dart';

/// Workspaces e projetos falando com o core Rust.
class SocketWorkspaceRepository implements WorkspaceRepository {
  const SocketWorkspaceRepository(this._feed);

  final OrganizationFeed _feed;

  /// Recusa e queda do socket viram [WorkspaceError].
  Future<EgeonMessage> _command(String cmd, [EgeonMessage args = const {}]) =>
      _feed
          .command(cmd, args)
          .failingAs(
            refused: WorkspaceRefused.new,
            offline: WorkspaceOffline.new,
          );

  @override
  Future<void> removeWorkspace(String id, {bool dryRun = false}) =>
      _command('remove_workspace', {'workspace': id, 'dry_run': dryRun});

  @override
  Future<void> removeProject(
    String workspaceId,
    String projectId, {
    bool dryRun = false,
  }) => _command('remove_project', {'project': projectId, 'dry_run': dryRun});

  /// O rascunho nasce do que a organização já tem: as pastas são os projetos
  /// simples; cada multi-projeto leva as pastas dos seus membros.
  @override
  Future<WorkspaceDraft> draft(String id) async {
    final org = _feed.last;
    final ws = org?.workspace(id);
    if (org == null || ws == null) {
      throw const WorkspaceRefused('workspace desconhecido');
    }
    return WorkspaceDraft(
      name: ws.name,
      icon: ws.icon,
      folders: [
        for (final p in ws.projects)
          if (!p.isMulti) p.path,
      ],
      multis: [
        for (final p in ws.projects)
          if (p.isMulti)
            MultiDraft(
              id: p.id,
              name: p.name,
              folders: [for (final m in p.members!) ?org.project(m)?.path],
            ),
      ],
    );
  }

  /// O formulário salva de uma vez: o core aplica as pastas e os
  /// multi-projetos como o Swift aplicava.
  @override
  Future<WorkspaceSaved> save(WorkspaceDraft draft, {String? id}) async =>
      WorkspaceSaved.fromMap(
        await _command('save_workspace', {
          'workspace': ?id,
          'name': draft.name,
          if (draft.iconSource != null)
            'icon': draft.iconSource
          else if (draft.clearIcon)
            'icon': null,
          'folders': draft.folders,
          'multis': [
            for (final m in draft.multis)
              {
                'id': ?m.id,
                if (m.name.isNotEmpty) 'name': m.name,
                'folders': m.folders,
              },
          ],
        }),
      );

  @override
  Future<String> suggestedParent(String workspaceId) async {
    final reply = await _command('suggest_parent', {'workspace': workspaceId});
    return reply['parent']! as String;
  }

  @override
  Future<String> multiName(String? workspaceId, List<String> folders) async {
    final reply = await _command('multi_name', {
      'workspace': ?workspaceId,
      'folders': folders,
    });
    return reply['name']! as String;
  }

  @override
  Future<void> createProject(
    String workspaceId, {
    required String name,
    required String parent,
    required bool git,
  }) => _command('create_project', {
    'workspace': workspaceId,
    'name': name,
    'parent': parent,
    'git': git,
  });
}
