import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_card.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump_canvas.dart';

/// "Nova worktree para este terminal…" (`NodeView.swift`): botão no cabeçalho
/// e item do botão direito, só em quem abre pasta.
void main() {
  const shell = CanvasCard(
    id: 'sh',
    kind: NodeKind.shell,
    title: 'sh',
    subtitle: '~/x',
    frame: Rect.fromLTWH(200, 300, 720, 460),
  );

  testWidgets('o botão direito no cabeçalho oferece a worktree do terminal', (
    tester,
  ) async {
    final asked = <String>[];
    await pumpCanvas(
      tester,
      InMemoryCanvasRepository(cards: const [shell]),
      onRequestWorktree: (card) => asked.add(card.id),
    );
    final card = find.byKey(const ValueKey('card-sh'));
    await tester.tapAt(
      tester.getTopLeft(card) + const Offset(200, 12),
      buttons: kSecondaryButton,
    );
    await tester.pump();
    await tester.tap(find.text('Nova worktree para este terminal…'));
    await tester.pump();
    expect(asked, ['sh']);

    await tester.tap(find.byKey(const ValueKey('card-worktree')));
    await tester.pump();
    expect(asked, ['sh', 'sh']);
  });
}
