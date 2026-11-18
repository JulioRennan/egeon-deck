import 'package:egeon_deck/commons/utils/agent_palette.dart';
import 'package:egeon_deck/features/usage/domain/entities/usage_view.dart';
import 'package:egeon_deck/features/usage/domain/repository/usage_repository.dart';
import 'package:egeon_deck/features/usage/domain/usecase/watch_usage.dart';
import 'package:egeon_deck/features/usage/presentation/cubit/usage_cubit.dart';
import 'package:egeon_deck/features/usage/presentation/widgets/usage_panel.dart';
import 'package:egeon_deck/features/usage/presentation/widgets/usage_pill.dart';
import 'package:egeon_deck/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_usage_repository.dart';

void main() {
  late FakeUsageRepository repo;

  Future<void> pumpPill(
    WidgetTester tester, {
    Map<String, Object?>? map,
  }) async {
    repo = FakeUsageRepository(UsageView.fromMap(map ?? sampleUsage()));
    tester.view
      ..physicalSize = const Size(1000, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<UsageRepository>.value(
        value: repo,
        child: WidgetsApp(
          color: const Color(0xFF000000),
          textStyle: AppTheme.textStyle,
          builder: (context, _) => Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: BlocProvider(
                      create: (_) => UsageCubit(
                        workbenchId: 'bancada',
                        watch: WatchUsage(repo),
                      ),
                      child: const UsagePill(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
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

  testWidgets('a pastilha mostra o custo da bancada', (tester) async {
    await pumpPill(tester);
    expect(find.text('US\$ 12,34'), findsOneWidget);
    expect(repo.watched, ['bancada']);
  });

  testWidgets('o custo acompanha o que o core manda', (tester) async {
    await pumpPill(tester);
    repo.push(
      UsageView.fromMap({
        'pill': {'text': 'US\$ 13,00'},
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('US\$ 13,00'), findsOneWidget);
  });

  testWidgets('a pastilha tem a mão do ponteiro', (tester) async {
    await pumpPill(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('usage-pill'))),
    );
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });

  group('o detalhe', () {
    testWidgets(
      'abre ancorado na pastilha, com total, legenda, agentes e modelos',
      (tester) async {
        await pumpPill(tester);
        await tester.tap(find.byKey(const ValueKey('usage-pill')));
        await tester.pump();

        expect(find.byKey(const ValueKey('usage-popover')), findsOneWidget);
        expect(find.text('NEXUS · BANCADA'), findsOneWidget);
        expect(find.byKey(const ValueKey('usage-total')), findsOneWidget);
        expect(find.text('1,2M tokens'), findsOneWidget);
        for (final title in [
          'Saída',
          'Entrada',
          'Cache escrito',
          'Cache lido',
        ]) {
          expect(find.text(title), findsOneWidget);
        }
        expect(
          find.textContaining('AGENTES', findRichText: true),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('agent-claude')), findsOneWidget);
        expect(find.text('Opus 5.5'), findsWidgets);
        expect(
          find.textContaining('MODELOS', findRichText: true),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('model-Sonnet 5.5')), findsOneWidget);

        // Fica embaixo da pastilha.
        final pill = tester.getRect(find.byKey(const ValueKey('usage-pill')));
        final popover = tester.getRect(
          find.byKey(const ValueKey('usage-popover')),
        );
        expect(popover.top, greaterThan(pill.bottom));
        expect(popover.width, UsagePanel.width);
      },
    );

    testWidgets('a barra de cada linha é proporcional ao maior', (
      tester,
    ) async {
      await pumpPill(tester);
      await tester.tap(find.byKey(const ValueKey('usage-pill')));
      await tester.pump();
      final big = tester
          .getSize(find.byKey(const ValueKey('agent-bar-claude')))
          .width;
      final small = tester
          .getSize(find.byKey(const ValueKey('agent-bar-dev')))
          .width;
      expect(small / big, closeTo(0.37, 0.01));
    });

    testWidgets('o agente leva a cor da paleta; o modelo, a da família', (
      tester,
    ) async {
      await pumpPill(tester);
      await tester.tap(find.byKey(const ValueKey('usage-pill')));
      await tester.pump();
      Color? colorOf(String key) =>
          ((tester.widget<Container>(find.byKey(ValueKey(key))).decoration!)
                  as BoxDecoration)
              .color;
      expect(colorOf('agent-bar-claude'), AgentPalette.of('claude'));
      expect(colorOf('agent-bar-dev'), AgentPalette.of('dev'));
      expect(colorOf('model-bar-Opus 5.5'), TariffColors.family('opus'));
      expect(colorOf('model-bar-Sonnet 5.5'), TariffColors.family('sonnet'));
    });

    testWidgets('a tabela de preços nasce recolhida e abre no clique', (
      tester,
    ) async {
      await pumpPill(tester);
      await tester.tap(find.byKey(const ValueKey('usage-pill')));
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-prices')), findsNothing);
      expect(find.text('Tabela de preços'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('usage-prices-toggle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-prices')), findsOneWidget);
      expect(
        find.text('● Opus 5.5'),
        findsOneWidget,
        reason: 'o que a bancada usa',
      );
      expect(
        find.text('✎ Haiku'),
        findsOneWidget,
        reason: 'veio do pricing.json',
      );
      expect(find.textContaining('modo rápido custa 2×'), findsOneWidget);
      expect(find.textContaining('~/.egeon/pricing.json'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('usage-prices-toggle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-prices')), findsNothing);
    });

    testWidgets('fecha com Esc e ao clicar fora', (tester) async {
      await pumpPill(tester);
      await tester.tap(find.byKey(const ValueKey('usage-pill')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-popover')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('usage-pill')));
      await tester.pump();
      await tester.tapAt(const Offset(900, 700));
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-popover')), findsNothing);
    });

    testWidgets('sem painel, o clique não abre nada', (tester) async {
      await pumpPill(
        tester,
        map: {
          'pill': {'text': 'US\$ —'},
        },
      );
      await tester.tap(find.byKey(const ValueKey('usage-pill')));
      await tester.pump();
      expect(find.byKey(const ValueKey('usage-popover')), findsNothing);
    });

    testWidgets('a tabela de preços tem a mão no cabeçalho', (tester) async {
      await pumpPill(tester);
      await tester.tap(find.byKey(const ValueKey('usage-pill')));
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('usage-prices-toggle'))),
      );
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );
    });
  });
}
