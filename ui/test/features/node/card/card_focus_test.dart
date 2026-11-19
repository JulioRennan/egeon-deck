import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/node/card/presentation/widgets/card_frame.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/overlay_host.dart';

/// O card em que você está digitando leva a cor da bancada na borda (ADR-086);
/// alerta ganha de foco.
void main() {
  const bench = Color(0xFF30B0C7);

  Future<FocusNode> mount(WidgetTester tester, {bool alert = false}) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      overlayHost(
        SizedBox(
          width: 400,
          height: 300,
          child: CardFrame(
            id: 'sh',
            kind: NodeKind.shell,
            title: 'sh',
            subtitle: '~',
            height: 300,
            linkable: false,
            needsAttention: alert,
            focusColor: bench,
            onDragStart: (_) {},
            onDrag: (_) {},
            onDragEnd: () {},
            onResize: (_) {},
            onResizeEnd: () {},
            onClose: () {},
            onPortDrag: (_) {},
            onPortRelease: (_) {},
            onPortCancel: () {},
            child: Focus(focusNode: node, child: const SizedBox.expand()),
          ),
        ),
      ),
    );
    return node;
  }

  Border border(WidgetTester tester) {
    final box = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(CardFrame),
            matching: find.byType(DecoratedBox),
          ),
        )
        .first;
    return (box.decoration as BoxDecoration).border! as Border;
  }

  testWidgets('foco dentro do card acende a borda na cor da bancada', (
    tester,
  ) async {
    final node = await mount(tester);
    expect(border(tester).top.color, isNot(bench.withValues(alpha: 0.95)));
    node.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(node.hasFocus, isTrue, reason: 'o teste deu o foco');
    expect(border(tester).top.color, bench.withValues(alpha: 0.95));
    expect(border(tester).top.width, 2);
    node.unfocus();
    await tester.pump();
    await tester.pump();
    expect(border(tester).top.width, 1);
  });

  testWidgets('alerta ganha de foco', (tester) async {
    final node = await mount(tester, alert: true);
    node.requestFocus();
    await tester.pump();
    expect(border(tester).top.color, isNot(bench.withValues(alpha: 0.95)));
  });
}
