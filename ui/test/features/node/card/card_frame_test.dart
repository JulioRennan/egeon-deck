import 'package:egeon_deck/commons/widgets/eg/eg_icon.dart';
import 'package:egeon_deck/commons/widgets/eg/identity.dart';
import 'package:egeon_deck/commons/widgets/eg/status_dot.dart';
import 'package:egeon_deck/core/domain/entities/workbench_node.dart';
import 'package:egeon_deck/features/node/card/domain/entities/card_activity.dart';
import 'package:egeon_deck/features/node/card/presentation/widgets/card_frame.dart';
import 'package:egeon_deck/features/node/card/presentation/widgets/subtitle_link.dart';
import 'package:egeon_deck/features/node/terminal/presentation/widgets/terminal_metrics.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/eg_host.dart';

CardFrame frame(
  NodeKind kind, {
  CardActivity activity = CardActivity.none,
  bool maestro = false,
  Widget? accessory,
  VoidCallback? onDragStart,
}) => CardFrame(
  id: 'x',
  kind: kind,
  title: 'x',
  subtitle: '~/Documents/a/b/c',
  height: 400,
  linkable: false,
  activity: activity,
  maestro: maestro,
  accessory: accessory,
  onConfigure: () {},
  onWorktree: () {},
  onDragStart: (_) => onDragStart?.call(),
  onDrag: (_) {},
  onDragEnd: () {},
  onResize: (_) {},
  onResizeEnd: () {},
  onClose: () {},
  onPortDrag: (_) {},
  onPortRelease: (_) {},
  onPortCancel: () {},
  child: const SizedBox.expand(),
);

Widget host(Widget child) =>
    egHost(SizedBox(width: 600, height: 400, child: child));

void main() {
  test('o caminho curto fica com as duas últimas partes', () {
    expect(shortPath('~/Documents/a/b/c'), '~/…/b/c');
    expect(shortPath('/Users/x/a/b'), '~/…/a/b');
    expect(shortPath('~/a/b'), '~/a/b');
    expect(
      shortPath('https://example.com/a/b/c/d'),
      'https://example.com/a/b/c/d',
    );
  });

  testWidgets('o cabeçalho do agente tem 56 e o do shell, 50', (tester) async {
    await tester.pumpWidget(host(frame(NodeKind.agent)));
    expect(CardFrame.headerHeightOf(NodeKind.agent), 56);
    expect(CardFrame.headerHeightOf(NodeKind.shell), 50);
    expect(find.text('~/…/b/c'), findsOneWidget);
  });

  testWidgets('o shell leva o ícone do terminal com o ponto de estado', (
    tester,
  ) async {
    await tester.pumpWidget(host(frame(NodeKind.shell)));
    expect(
      tester.widgetList<EgIcon>(find.byType(EgIcon)).map((i) => i.icon),
      contains(EgIcons.terminal),
    );
    expect(find.byType(StatusDot), findsOneWidget);
    expect(find.byKey(const ValueKey('card-configure')), findsOneWidget);
  });

  testWidgets('o card do shell é neutro; o erro troca a borda para danger', (
    tester,
  ) async {
    await tester.pumpWidget(host(frame(NodeKind.shell)));
    BoxDecoration deco() =>
        tester
                .widgetList<DecoratedBox>(find.byType(DecoratedBox))
                .firstWhere(
                  (d) => (d.decoration as BoxDecoration).boxShadow != null,
                )
                .decoration
            as BoxDecoration;
    expect((deco().border! as Border).top.color, const Color(0x1AFFFFFF));
    await tester.pumpWidget(
      host(
        frame(
          NodeKind.shell,
          activity: const CardActivity(tone: ActivityTone.red),
        ),
      ),
    );
    expect(
      (deco().border! as Border).top.color,
      EgeonColors.dark.danger.withValues(alpha: 0.4),
    );
  });

  testWidgets('arrastado, o card leva a sombra de arrasto', (tester) async {
    await tester.pumpWidget(host(frame(NodeKind.agent)));
    List<BoxShadow>? shadows() =>
        (tester
                    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
                    .firstWhere(
                      (d) => (d.decoration as BoxDecoration).boxShadow != null,
                    )
                    .decoration
                as BoxDecoration)
            .boxShadow;
    expect(shadows(), isNot(EgeonShadow.drag));
    final gesture = await tester.startGesture(
      tester.getTopLeft(find.byType(CardFrame)) + const Offset(300, 20),
    );
    await tester.pump();
    expect(shadows(), EgeonShadow.drag);
    await gesture.up();
    await tester.pump();
    expect(shadows(), isNot(EgeonShadow.drag));
  });

  testWidgets('a faixa de controles ocupa 36 sob o cabeçalho', (tester) async {
    await tester.pumpWidget(
      host(
        frame(
          NodeKind.agent,
          accessory: const SizedBox(key: ValueKey('strip')),
        ),
      ),
    );
    final strip = tester.getRect(find.byKey(const ValueKey('strip')));
    expect(strip.height, 36);
    expect(strip.top - tester.getTopLeft(find.byType(CardFrame)).dy, 56);
  });

  testWidgets(
    'o maestro é sand em tudo — faixa, gradiente, nome, etiqueta — e leva a '
    'mesma faixa de controles',
    (tester) async {
      await tester.pumpWidget(
        host(
          frame(
            NodeKind.agent,
            maestro: true,
            accessory: const SizedBox(key: ValueKey('strip')),
          ),
        ),
      );
      final sand = Identity.sand.color(EgeonColors.dark);
      expect(find.byKey(const ValueKey('strip')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('card-title')))
            .style!
            .color,
        sand,
      );
      final decorations = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>();
      final gradient = decorations
          .map((d) => d.gradient)
          .whereType<LinearGradient>()
          .single;
      expect(gradient.colors, [
        sand.withValues(alpha: 0.14),
        sand.withValues(alpha: 0.03),
        sand.withValues(alpha: 0),
      ]);
      expect(gradient.stops, [0, 0.7, 1]);
      expect(
        decorations.any((d) => d.color == sand.withValues(alpha: 0.16)),
        isTrue,
        reason: 'fundo da etiqueta',
      );
      expect(
        tester
            .widgetList<ColoredBox>(find.byType(ColoredBox))
            .any((b) => b.color == sand),
        isTrue,
        reason: 'faixa de 2px no topo',
      );
    },
  );

  test('o terminal usa JetBrains Mono 14/20 e a paleta nova', () {
    expect(TerminalMetrics.baseStyle.fontFamily, 'JetBrains Mono');
    expect(TerminalMetrics.baseStyle.fontSize, 14);
    expect(TerminalMetrics.baseStyle.height, closeTo(20 / 14, 1e-9));
  });
}
