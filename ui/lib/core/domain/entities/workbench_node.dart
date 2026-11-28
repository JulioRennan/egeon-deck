import 'dart:ui';

/// O tipo de um nó da bancada.
enum NodeKind {
  shell('shell'),
  agent('agent'),
  web('web'),
  queue('queue');

  const NodeKind(this.wire);

  final String wire;

  /// Tipo desconhecido vira terminal: nó de um tipo que saiu do app não pode
  /// derrubar a bancada.
  static NodeKind fromWire(Object? raw) => values.firstWhere(
    (kind) => kind.wire == raw,
    orElse: () => NodeKind.shell,
  );
}

/// Um nó no canvas: id, tipo, título e o retângulo que ocupa.
class WorkbenchNode {
  const WorkbenchNode({
    required this.id,
    required this.kind,
    required this.title,
    required this.frame,
  });

  final String id;
  final NodeKind kind;
  final String title;
  final Rect frame;

  factory WorkbenchNode.fromMap(Map<String, Object?> map) {
    final f = (map['frame'] as Map<String, Object?>?) ?? const {};
    double n(String key) => (f[key] as num?)?.toDouble() ?? 0;
    return WorkbenchNode(
      id: map['id']! as String,
      kind: NodeKind.fromWire(map['kind']),
      title: map['title'] as String? ?? map['id']! as String,
      frame: Rect.fromLTWH(n('x'), n('y'), n('w'), n('h')),
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind.wire,
    'title': title,
    'frame': {
      'x': frame.left,
      'y': frame.top,
      'w': frame.width,
      'h': frame.height,
    },
  };
}
