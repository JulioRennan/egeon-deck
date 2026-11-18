import 'dart:async';
import 'dart:ui';

import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_tool.dart';
import 'package:egeon_deck/features/canvas/domain/entities/edge_link.dart';
import 'package:egeon_deck/features/canvas/domain/repository/canvas_repository.dart';

/// Canvas em memória, com dados falsos. Vale até o core Rust expor o contrato
/// dos nós e das ligações; os testes e a primeira tela andam em cima dele.
class InMemoryCanvasRepository implements CanvasRepository {
  InMemoryCanvasRepository({List<CanvasCard>? cards, List<EdgeLink>? links})
    : _cards = [...(cards ?? _seedCards)],
      _links = [...(links ?? _seedLinks)];

  static const _seedCards = [
    CanvasCard(
      id: 'sh1',
      kind: NodeKind.shell,
      title: 'sh1',
      subtitle: '~/projeto',
      frame: Rect.fromLTWH(1200, 900, 720, 460),
    ),
    CanvasCard(
      id: 'claude',
      kind: NodeKind.agent,
      title: 'claude',
      subtitle: '~/projeto',
      frame: Rect.fromLTWH(2000, 900, 720, 460),
    ),
    CanvasCard(
      id: 'web1',
      kind: NodeKind.web,
      title: 'web1',
      subtitle: 'https://example.com',
      frame: Rect.fromLTWH(1200, 1440, 720, 460),
    ),
  ];

  static const _seedLinks = [
    EdgeLink(a: 'claude', b: 'sh1', aToB: false, bToA: true),
  ];

  final List<CanvasCard> _cards;
  final List<EdgeLink> _links;
  final _changes = StreamController<void>.broadcast();
  var _serial = 0;

  /// O que o core diz de cada nó: terminais ligam a outros terminais.
  CanvasSnapshot get _snapshot {
    final terminals = [
      for (final c in _cards)
        if (c.kind == NodeKind.shell || c.kind == NodeKind.agent) c.id,
    ];
    return CanvasSnapshot(
      cards: [
        for (final c in _cards)
          c.copyWith(
            port: c.kind != NodeKind.web,
            linkable: terminals.contains(c.id)
                ? [
                    for (final id in terminals)
                      if (id != c.id) id,
                  ]
                : const [],
          ),
      ],
      links: [..._links],
    );
  }

  void _publish() => _changes.add(null);

  /// Controller em vez de `async*`: cancelar um gerador parado num `await for`
  /// só termina quando ele acorda, e o `close()` do cubit esperaria para sempre.
  @override
  Stream<CanvasSnapshot> watch(String workbenchId) {
    late final StreamController<CanvasSnapshot> controller;
    StreamSubscription<void>? changes;
    controller = StreamController<CanvasSnapshot>(
      onListen: () {
        controller.add(_snapshot);
        changes = _changes.stream.listen((_) => controller.add(_snapshot));
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> saveFrames(String workbenchId, Map<String, Rect> frames) async {
    for (var i = 0; i < _cards.length; i++) {
      final frame = frames[_cards[i].id];
      if (frame != null) _cards[i] = _cards[i].copyWith(frame: frame);
    }
    _publish();
  }

  /// Base do id do nó novo: o core é quem escolhe o id de verdade.
  static String _prefix(CanvasTool tool) => switch (tool) {
    CanvasTool.cursor => '',
    CanvasTool.terminal => 'sh',
    CanvasTool.web => 'web',
    CanvasTool.queue => 'fila',
  };

  @override
  Future<void> placeNode(
    String workbenchId,
    CanvasTool tool,
    Rect frame, {
    String? component,
  }) async {
    final kind = tool.nodeKind;
    if (kind == null) return;
    String id;
    do {
      id = '${_prefix(tool)}${++_serial}';
    } while (_cards.any((card) => card.id == id));
    _cards.add(
      CanvasCard(id: id, kind: kind, title: component ?? id, frame: frame),
    );
    _publish();
  }

  @override
  Future<void> createLink(String workbenchId, String from, String to) async {
    final a = from.compareTo(to) <= 0 ? from : to;
    final b = a == from ? to : from;
    // O arrasto do + cria o par nos dois sentidos, como o core (`both`).
    final link = EdgeLink(a: a, b: b, aToB: true, bToA: true);
    // Par já ligado, em qualquer sentido: o core responde ok e não cria outra.
    if (_links.any((l) => l.a == a && l.b == b)) return;
    _links.add(link);
    _publish();
  }

  @override
  Future<void> removeLink(String workbenchId, EdgeLink link) async {
    _links.remove(link);
    _publish();
  }

  @override
  Future<void> cycleLink(String workbenchId, EdgeLink link) async {
    final index = _links.indexOf(link);
    if (index < 0) return;
    final current = _links[index];
    final (aToB, bToA) = switch ((current.aToB, current.bToA)) {
      (true, false) => (true, true),
      (true, true) => (false, true),
      _ => (true, false),
    };
    _links[index] = EdgeLink(
      a: current.a,
      b: current.b,
      aToB: aToB,
      bToA: bToA,
      maxSends: current.maxSends,
    );
    _publish();
  }

  @override
  Future<void> setLinkLimit(
    String workbenchId,
    EdgeLink link,
    int? maxSends,
  ) async {
    final index = _links.indexOf(link);
    if (index < 0) return;
    final current = _links[index];
    _links[index] = EdgeLink(
      a: current.a,
      b: current.b,
      aToB: current.aToB,
      bToA: current.bToA,
      maxSends: maxSends,
    );
    _publish();
  }

  @override
  Future<void> removeNode(String workbenchId, String nodeId) async {
    _cards.removeWhere((card) => card.id == nodeId);
    _links.removeWhere((link) => link.a == nodeId || link.b == nodeId);
    _publish();
  }

  final focuses =
      <({bool appActive, String? workbenchId, String? nodeId, Size? window})>[];

  @override
  Future<void> setFocus({
    required bool appActive,
    String? workbenchId,
    String? nodeId,
    Size? window,
  }) async => focuses.add((
    appActive: appActive,
    workbenchId: workbenchId,
    nodeId: nodeId,
    window: window,
  ));
}
