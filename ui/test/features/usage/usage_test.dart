import 'package:egeon_deck/commons/utils/agent_identity.dart';
import 'package:egeon_deck/commons/widgets/eg/glass_surface.dart';
import 'package:egeon_deck/core/domain/entities/workbench_clock.dart';
import 'package:egeon_deck/features/usage/domain/entities/usage_view.dart';
import 'package:egeon_deck/features/usage/domain/usecase/watch_usage.dart';
import 'package:egeon_deck/features/usage/presentation/cubit/usage_cubit.dart';
import 'package:egeon_deck/features/usage/presentation/widgets/usage_chip.dart';
import 'package:egeon_deck/features/usage/presentation/widgets/usage_panel.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';
import '../../support/fake_usage_repository.dart';
import '../../support/inject_fakes.dart';

void main() {
  late FakeUsageRepository repo;
  var resets = 0;

  Future<void> pumpChip(
    WidgetTester tester, {
    Map<String, Object?>? map,
    WorkbenchClock? clock,
    bool withReset = true,
  }) async {
    repo = FakeUsageRepository(UsageView.fromMap(map ?? sampleUsage()));
    resets = 0;
    tester.view
      ..physicalSize = const Size(1000, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    injectFakes(usage: repo);
    await tester.pumpWidget(
      egHost(
        fill: true,
        Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: BlocProvider(
              create: (_) =>
                  UsageCubit(workbenchId: 'bancada', watch: WatchUsage(repo)),
              child: UsageChip(
                clock: clock,
                onReset: withReset ? () => resets++ : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('usage-pill-text')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  test('o consumo lê pastilha e painel prontos do core', () {
    final view = UsageView.fromMap(sampleUsage());
    expect(view.pill.text, 'US\$ 12,34');
    expect(view.pill.tooltip, contains('1,2M tokens'));
    final panel = view.panel!;
    expect(panel.totalAmount, 'US\$ 12,34');
    expect(panel.split.map((s) => s.tariff), [
      Tariff.output,
      Tariff.input,
      Tariff.cacheWrite,
      Tariff.cacheRead,
    ]);
    expect(panel.agents.first.tag, 'Opus 5.5');
    expect(panel.agents.last.tag, isNull);
    expect(panel.models.first.family, 'opus');
    expect(panel.prices.rows.first.lit, isTrue);
    expect(panel.prices.rows.last.edited, isTrue);
  });

  test('sem painel, a pastilha mostra o travessão', () {
    final view = UsageView.fromMap({});
    expect(view.pill.text, 'US\$ —');
    expect(view.panel, isNull);
  });

  test('a fração fica entre 0 e 1', () {
    expect(UsageRow.fromMap({'fraction': 7}).fraction, 1);
    expect(UsageRow.fromMap({'fraction': -1}).fraction, 0);
  });

  testWidgets('o chip é de vidro, com 46 de altura, e mostra o custo', (
    tester,
  ) async {
    await pumpChip(tester);
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(tester.getSize(find.byType(UsageChip)).height, UsageChip.height);
    expect(find.text('US\$ 12,34'), findsOneWidget);
    expect(repo.watched, ['bancada']);
  });

  testWidgets('com o relógio, o martelo e a mão vão antes do custo', (
    tester,
  ) async {
    await pumpChip(
      tester,
      clock: const WorkbenchClock(
        running: 1469,
        waiting: 29,
        ticking: {ClockPhase.running},
      ),
    );
    expect(find.text('24:29'), findsOneWidget);
    expect(find.text('00:29'), findsOneWidget);
    final clock = tester.getRect(find.text('24:29'));
    final cost = tester.getRect(find.text('US\$ 12,34'));
    expect(clock.right, lessThan(cost.left));
  });

  testWidgets('a partir de uma hora o tempo vira h:mm:ss', (tester) async {
    await pumpChip(
      tester,
      clock: const WorkbenchClock(
        running: 27 * 3600 + 29 * 60 + 32,
        waiting: 61,
      ),
    );
    expect(find.text('27:29:32'), findsOneWidget);
    expect(find.text('01:01'), findsOneWidget);
  });

  testWidgets('o custo acompanha o que o core manda', (tester) async {
    await pumpChip(tester);
    repo.push(
      UsageView.fromMap({
        'pill': {'text': 'US\$ 13,00'},
        'panel': (sampleUsage()['panel']),
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('US\$ 13,00'), findsOneWidget);
  });

  testWidgets('o chip tem a mão do ponteiro', (tester) async {
    await pumpChip(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('US\$ 12,34')));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });

  group('o painel', () {
    testWidgets('a faixa do topo tem 4 e um trecho por agente, na cor dele', (
      tester,
    ) async {
      await pumpChip(tester, clock: const WorkbenchClock(running: 5));
      await open(tester);
      final strip = find.byKey(const ValueKey('usage-agent-bar'));
      expect(tester.getSize(strip).height, 4);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('usage-agent-seg-claude')))
            .height,
        4,
        reason: 'o trecho tem de aparecer: ColoredBox sem esticar some',
      );
      final c = EgeonColors.dark;
      Color seg(String n) => tester
          .widget<ColoredBox>(find.byKey(ValueKey('usage-agent-seg-$n')))
          .color;
      expect(seg('claude'), agentIdentity('claude').color(c));
      expect(seg('dev'), agentIdentity('dev').color(c));
      // O que gastou mais tem o trecho maior.
      final big = tester.getSize(
        find.byKey(const ValueKey('usage-agent-seg-claude')),
      );
      final small = tester.getSize(
        find.byKey(const ValueKey('usage-agent-seg-dev')),
      );
      expect(big.width, greaterThan(small.width));
    });

    testWidgets('os três valores são mono 20/26 em textPrimary', (
      tester,
    ) async {
      await pumpChip(
        tester,
        clock: const WorkbenchClock(running: 75, waiting: 5),
      );
      await open(tester);
      for (final text in ['01:15', '00:05', 'US\$ 12,34']) {
        final style = tester
            .widget<Text>(
              find.descendant(
                of: find.byType(UsagePanel),
                matching: find.text(text),
              ),
            )
            .style!;
        expect(style.fontSize, 20, reason: text);
        expect(style.fontWeight, FontWeight.w500, reason: text);
        expect(style.color, EgeonColors.dark.textPrimary, reason: text);
      }
    });

    testWidgets('o painel tem raio 16 e fica 8 abaixo do chip', (tester) async {
      await pumpChip(tester, clock: const WorkbenchClock(running: 5));
      await open(tester);
      final glass = tester
          .widgetList<ClipRRect>(
            find.ancestor(
              of: find.byType(UsagePanel),
              matching: find.byType(ClipRRect),
            ),
          )
          .first;
      expect(glass.borderRadius, BorderRadius.circular(16));
      final chip = tester.getRect(find.byType(UsageChip));
      final panel = tester.getRect(find.byType(UsagePanel));
      expect(panel.top, closeTo(chip.bottom + 8, 1));
    });

    const clock = WorkbenchClock(running: 1469, waiting: 29);

    testWidgets('abre sobre o chip e marca o chip; fechar o solta', (
      tester,
    ) async {
      await pumpChip(tester, clock: clock);
      await open(tester);
      expect(find.text('Nexus · bancada'), findsOneWidget);
      expect(find.byKey(const ValueKey('usage-total')), findsOneWidget);
      expect(find.text('Trabalhando'), findsOneWidget);
      expect(find.text('Parado'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('1,2M tokens'), findsOneWidget);
      final chip = tester.getRect(find.byType(UsageChip));
      final panel = tester.getRect(find.byType(UsagePanel));
      expect(panel.top, greaterThan(chip.bottom));
      expect(panel.width, UsagePanel.width);
      expect(
        panel.right,
        closeTo(chip.right, 6),
        reason: 'junto da ponta do chip',
      );

      await tester.tap(find.byKey(const ValueKey('usage-close')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(UsagePanel), findsNothing);
    });

    testWidgets('a divisão por tarifa, com a legenda, está em Por modelo', (
      tester,
    ) async {
      await pumpChip(tester, clock: clock);
      await open(tester);
      expect(find.text('Saída'), findsNothing, reason: 'só Por modelo a traz');
      await tester.tap(find.text('Por modelo'));
      await tester.pump();
      for (final title in ['Saída', 'Entrada', 'Cache escrito', 'Cache lido']) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('o painel abre em Por agente e não tem a aba Log', (
      tester,
    ) async {
      await pumpChip(tester, clock: clock);
      await open(tester);
      expect(find.text('Log'), findsNothing);
      expect(find.byKey(const ValueKey('agent-claude')), findsOneWidget);
    });

    testWidgets('Por agente e Por modelo trocam a lista', (tester) async {
      await pumpChip(tester, clock: clock);
      await open(tester);
      await tester.tap(find.text('Por agente'));
      await tester.pump();
      expect(find.byKey(const ValueKey('agent-claude')), findsOneWidget);
      expect(find.byKey(const ValueKey('model-Sonnet 5.5')), findsNothing);
      expect(find.text('Opus 5.5'), findsWidgets);
      await tester.tap(find.text('Por modelo'));
      await tester.pump();
      expect(find.byKey(const ValueKey('model-Sonnet 5.5')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-claude')), findsNothing);
    });

    testWidgets('a barra de cada linha é proporcional ao maior', (
      tester,
    ) async {
      await pumpChip(tester, clock: clock);
      await open(tester);
      await tester.tap(find.text('Por agente'));
      await tester.pump();
      final big = tester
          .getSize(find.byKey(const ValueKey('agent-bar-claude')))
          .width;
      final small = tester
          .getSize(find.byKey(const ValueKey('agent-bar-dev')))
          .width;
      expect(small / big, closeTo(0.37, 0.01));
    });

    testWidgets(
      'o agente leva a cor dele (a do chat e a do card); o modelo, accent',
      (tester) async {
        await pumpChip(tester, clock: clock);
        await open(tester);
        await tester.tap(find.text('Por agente'));
        await tester.pump();
        Color? colorOf(String key) =>
            ((tester.widget<Container>(find.byKey(ValueKey(key))).decoration!)
                    as BoxDecoration)
                .color;
        final c = EgeonColors.dark;
        expect(colorOf('agent-bar-claude'), agentIdentity('claude').color(c));
        expect(colorOf('agent-bar-dev'), agentIdentity('dev').color(c));
        await tester.tap(find.text('Por modelo'));
        await tester.pump();
        expect(colorOf('model-bar-Opus 5.5'), c.accent);
      },
    );

    testWidgets('a tabela de preços nasce recolhida e abre no clique', (
      tester,
    ) async {
      await pumpChip(tester, clock: clock);
      await open(tester);
      expect(find.byKey(const ValueKey('usage-prices')), findsNothing);
      await tester.ensureVisible(
        find.byKey(const ValueKey('usage-prices-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('usage-prices-toggle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-prices')), findsOneWidget);
      expect(find.text('● Opus 5.5'), findsOneWidget);
      expect(find.text('✎ Haiku'), findsOneWidget);
      expect(find.textContaining('modo rápido custa 2×'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('usage-prices-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('usage-prices-toggle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-prices')), findsNothing);
    });

    testWidgets('sem ouvinte para zerar, o botão não aparece', (tester) async {
      await pumpChip(tester, clock: clock, withReset: false);
      await open(tester);
      expect(find.byKey(const ValueKey('usage-reset')), findsNothing);
    });

    testWidgets('Zerar cronômetro vai ao core e fecha o painel', (
      tester,
    ) async {
      await pumpChip(tester, clock: clock);
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('usage-reset')));
      final panelRight = tester.getRect(find.byType(UsagePanel)).right;
      final resetRight = tester
          .getRect(find.byKey(const ValueKey('usage-reset')))
          .right;
      expect(
        panelRight - resetRight,
        8,
        reason: 'o botão fica na ponta direita',
      );
      await tester.tap(find.byKey(const ValueKey('usage-reset')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(resets, 1);
      expect(find.byType(UsagePanel), findsNothing);
    });

    testWidgets('sem relógio (a bancada não rodou), sem tempos nem zerar', (
      tester,
    ) async {
      await pumpChip(tester);
      await open(tester);
      expect(find.text('Trabalhando'), findsNothing);
      expect(find.byKey(const ValueKey('usage-reset')), findsNothing);
      expect(find.text('Total'), findsOneWidget);
    });

    testWidgets('fecha com Esc e ao clicar fora', (tester) async {
      await pumpChip(tester, clock: clock);
      await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(UsagePanel), findsNothing);

      await open(tester);
      await tester.tapAt(const Offset(60, 700));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(UsagePanel), findsNothing);
    });

    testWidgets('sem painel, o clique não abre nada', (tester) async {
      await pumpChip(
        tester,
        map: {
          'pill': {'text': 'US\$ —'},
        },
      );
      await tester.tap(find.byKey(const ValueKey('usage-pill-text')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(UsagePanel), findsNothing);
    });
  });
}
