import 'dart:async';
import 'dart:ui';

import '../../../../core/adapters/egeon_socket_client.dart';
import '../entities/canvas_card.dart';
import '../entities/canvas_tool.dart';
import '../entities/edge_link.dart';
import 'canvas_repository.dart';
import '../errors/canvas_error.dart';

/// O canvas falando com o core Rust pelo cliente único do socket: o tópico
/// `workbench/<id>/nodes` traz o estado inteiro a cada mudança, e os gestos
/// viram `move_node`, `create_node`, `link`, `unlink`, `set_edge` e
/// `remove_node`.
class SocketCanvasRepository implements CanvasRepository {
  SocketCanvasRepository(this._client);

  final EgeonSocketClient _client;

  /// Recusa e queda do socket viram [CanvasError].
  Future<EgeonMessage> _request(String cmd, [EgeonMessage args = const {}]) =>
      _client
          .request(cmd, args)
          .failingAs(refused: CanvasRefused.new, offline: CanvasOffline.new);

  /// Os frames que o core tem, por bancada e nó. Só o que mudou vai em
  /// `move_node`.
  final _known = <String, Map<String, Rect>>{};

  @override
  Stream<CanvasSnapshot> watch(String workbenchId) => _client
      .subscribe('workbench/$workbenchId/nodes')
      .map((event) => _snapshot(workbenchId, event));

  CanvasSnapshot _snapshot(String workbenchId, EgeonMessage event) {
    final cards = [
      for (final node in (event['nodes'] as List<Object?>? ?? const []))
        CanvasCard.fromNode(node! as Map<String, Object?>),
    ];
    _known[workbenchId] = {for (final c in cards) c.id: c.frame};
    return CanvasSnapshot(
      cards: cards,
      links: [
        for (final l in (event['links'] as List<Object?>? ?? const []))
          EdgeLink.fromMap(l! as Map<String, Object?>),
      ],
    );
  }

  Future<void> _move(String workbenchId, String node, Rect frame) async {
    await _request('move_node', {
      'workbench': workbenchId,
      'node': node,
      'frame': {
        'x': frame.left,
        'y': frame.top,
        'w': frame.width,
        'h': frame.height,
      },
    });
  }

  @override
  Future<void> saveFrames(String workbenchId, Map<String, Rect> frames) async {
    final known = _known[workbenchId] ?? const <String, Rect>{};
    await Future.wait([
      for (final e in frames.entries)
        if (known[e.key] != e.value) _move(workbenchId, e.key, e.value),
    ]);
  }

  @override
  Future<void> placeNode(
    String workbenchId,
    CanvasTool tool,
    Rect frame, {
    String? component,
  }) async {
    final kind = tool.nodeKind;
    if (kind == null) return;
    await _request('create_node', {
      'workbench': workbenchId,
      'type': kind.wire,
      'frame': {
        'x': frame.left,
        'y': frame.top,
        'w': frame.width,
        'h': frame.height,
      },
      'component': ?component,
    });
  }

  @override
  Future<void> createLink(String workbenchId, String from, String to) =>
      _request('link', {
        'workbench': workbenchId,
        'from': from,
        'to': to,
        'both': true,
      });

  /// Remove a ligação inteira — os dois sentidos, porque na tela ela é uma
  /// linha só.
  @override
  Future<void> removeLink(String workbenchId, EdgeLink link) => _request(
    'unlink',
    {'workbench': workbenchId, 'from': link.a, 'to': link.b, 'both': true},
  );

  @override
  Future<void> cycleLink(String workbenchId, EdgeLink link) =>
      _request('set_edge', {
        'workbench': workbenchId,
        'from': link.a,
        'to': link.b,
        'direction': 'cycle',
      });

  /// `max_sends: null` é "sem limite próprio": a chave vai mesmo vazia.
  @override
  Future<void> setLinkLimit(String workbenchId, EdgeLink link, int? maxSends) =>
      _request('set_edge', {
        'workbench': workbenchId,
        'from': link.a,
        'to': link.b,
        'max_sends': maxSends,
      });

  @override
  Future<void> removeNode(String workbenchId, String nodeId) =>
      _request('remove_node', {'workbench': workbenchId, 'node': nodeId});

  /// `ui_focus`: o nó só vai quando há (o app em segundo plano não tem foco de
  /// teclado em nenhum).
  @override
  Future<void> setFocus({
    required bool appActive,
    String? workbenchId,
    String? nodeId,
    Size? window,
  }) async {
    await _request('ui_focus', {
      'app_active': appActive,
      if (workbenchId != null && nodeId != null)
        'node': {'workbench': workbenchId, 'node': nodeId},
      if (window != null) 'window': {'w': window.width, 'h': window.height},
    });
  }
}
