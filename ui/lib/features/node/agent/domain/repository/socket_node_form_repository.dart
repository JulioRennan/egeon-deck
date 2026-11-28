import 'dart:ui';

import '../../../../../core/adapters/egeon_socket_client.dart';
import '../entities/node_form_submit.dart';
import '../entities/node_form_view.dart';
import '../entities/node_screen.dart';
import '../entities/node_template.dart';
import '../errors/agent_error.dart';
import 'node_form_repository.dart';

/// Os comandos `node_form`, `node_form_screen`, `node_folder`, `create_node`
/// com `form`, `apply_node` e `components`.
class SocketNodeFormRepository implements NodeFormRepository {
  const SocketNodeFormRepository(this._client);

  final EgeonSocketClient _client;

  /// Recusa e queda do socket viram [AgentError].
  Future<EgeonMessage> _request(String cmd, [EgeonMessage args = const {}]) =>
      _client
          .request(cmd, args)
          .failingAs(refused: AgentRefused.new, offline: AgentOffline.new);

  @override
  Future<NodeFormView> open(String workbenchId, {String? nodeId}) async =>
      NodeFormView.fromMap(
        await _request('node_form', {
          'workbench': workbenchId,
          'node': ?nodeId,
        }),
      );

  @override
  Future<NodeScreen> screen(
    String workbenchId, {
    required NodeTemplate template,
    String? nodeId,
    ShownFields? shown,
    String? cli,
    String? config,
  }) async => NodeScreen.fromMap(
    await _request('node_form_screen', {
      'workbench': workbenchId,
      'node': ?nodeId,
      'template': template.toMap(),
      if (shown != null) 'shown': shown.toMap(),
      'cli': ?cli,
      'config': ?config,
    }),
  );

  @override
  Future<FolderOption> folder(String workbenchId, String path) async {
    final reply = await _request('node_folder', {
      'workbench': workbenchId,
      'path': path,
    });
    return FolderOption(
      value: reply['cwd'] as String? ?? '',
      shown: reply['shown'] as String? ?? '',
    );
  }

  @override
  Future<String> create(
    String workbenchId,
    NodeFormSubmit form, {
    Rect? frame,
    Rect? visible,
  }) async {
    final reply = await _request('create_node', {
      'workbench': workbenchId,
      'type': form.fields.kind.wire,
      if (frame != null)
        'frame': {
          'x': frame.left,
          'y': frame.top,
          'w': frame.width,
          'h': frame.height,
        },
      if (visible != null)
        'visible': {
          'x': visible.left,
          'y': visible.top,
          'w': visible.width,
          'h': visible.height,
        },
      'form': form.toMap(),
    });
    return reply['node'] as String? ?? '';
  }

  @override
  Future<String> apply(
    String workbenchId,
    String nodeId,
    NodeFormSubmit form,
  ) async {
    final reply = await _request('apply_node', {
      'workbench': workbenchId,
      'node': nodeId,
      'form': form.toMap(),
    });
    return reply['node'] as String? ?? nodeId;
  }

  @override
  Future<List<ComponentInfo>> components() async {
    final reply = await _request('components');
    return [
      for (final c in (reply['components'] as List<Object?>? ?? const []))
        ComponentInfo.fromMap(c! as Map<String, Object?>),
    ];
  }
}
