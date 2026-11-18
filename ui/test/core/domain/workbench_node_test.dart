import 'dart:ui';

import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('o nó vai e volta pelo mapa', () {
    const node = WorkbenchNode(
      id: 'a1',
      kind: NodeKind.agent,
      title: 'revisor',
      frame: Rect.fromLTWH(10, 20, 300, 200),
    );
    final again = WorkbenchNode.fromMap(node.toMap());
    expect(again.id, 'a1');
    expect(again.kind, NodeKind.agent);
    expect(again.title, 'revisor');
    expect(again.frame, const Rect.fromLTWH(10, 20, 300, 200));
  });

  test('tipo desconhecido vira terminal e título ausente vira o id', () {
    final node = WorkbenchNode.fromMap({'id': 'x', 'kind': 'holograma'});
    expect(node.kind, NodeKind.shell);
    expect(node.title, 'x');
    expect(node.frame, Rect.zero);
  });
}
