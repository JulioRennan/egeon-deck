import 'package:egeon_deck/commons/widgets/eg/agent_name.dart';
import 'package:egeon_deck/commons/widgets/eg/attention_ring.dart';
import 'package:egeon_deck/commons/widgets/eg/badge.dart';
import 'package:egeon_deck/commons/widgets/eg/banner.dart';
import 'package:egeon_deck/commons/widgets/eg/code_block.dart';
import 'package:egeon_deck/commons/widgets/eg/context_ring.dart';
import 'package:egeon_deck/commons/widgets/eg/counter.dart';
import 'package:egeon_deck/commons/widgets/eg/diff_view.dart';
import 'package:egeon_deck/commons/widgets/eg/edge_label.dart';
import 'package:egeon_deck/commons/widgets/eg/eg_icon.dart';
import 'package:egeon_deck/commons/widgets/eg/identity.dart';
import 'package:egeon_deck/commons/widgets/eg/info_pill.dart';
import 'package:egeon_deck/commons/widgets/eg/spinner.dart';
import 'package:egeon_deck/commons/widgets/eg/status.dart';
import 'package:egeon_deck/commons/widgets/eg/status_dot.dart';
import 'package:egeon_deck/commons/widgets/eg/usage_bar.dart';
import 'package:egeon_deck/commons/widgets/eg/workbench_clock.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

const _c = EgeonColors.dark;

BoxDecoration _dot(WidgetTester tester) =>
    tester
            .widget<DecoratedBox>(
              find
                  .descendant(
                    of: find.byType(StatusDot),
                    matching: find.byType(DecoratedBox),
                  )
                  .first,
            )
            .decoration
        as BoxDecoration;

void main() {
  group('Identity', () {
    test('12 cores na ordem de atribuição, todas distintas', () {
      expect(Identity.values.length, 12);
      expect(Identity.values.map((i) => i.color(_c)).toSet().length, 12);
      expect(Identity.values.map((i) => i.color(_c)).toList(), _c.identities);
    });

    test('auto dá a volta e fromName entende steel como slate', () {
      expect(Identity.auto(0), Identity.sky);
      expect(Identity.auto(12), Identity.sky);
      expect(Identity.auto(13), Identity.iris);
      expect(Identity.fromName('moss'), Identity.moss);
      expect(Identity.fromName('steel'), Identity.slate);
      expect(Identity.fromName('inexistente'), Identity.slate);
      expect(identityColor(_c, null), _c.idSlate);
    });

    testEg('AgentName escreve o nome na cor e o endereço em mono', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(
          const AgentName(
            'front',
            identity: Identity.jade,
            address: 'loja/front',
          ),
        ),
      );
      final name = tester.widget<Text>(find.text('front'));
      expect(name.style!.color, _c.idJade);
      expect(name.style!.fontWeight, FontWeight.w600);
      final address = tester.widget<Text>(find.text('loja/front'));
      expect(address.style!.color, _c.textMuted);
      expect(address.style!.fontFamily, 'JetBrains Mono');
    });
  });

  group('StatusDot', () {
    testEg('cor e forma de cada estado', (tester) async {
      Future<void> show(Status s, {bool animated = false}) =>
          tester.pumpWidget(egHost(StatusDot(s, animated: animated)));

      await show(Status.success);
      expect(_dot(tester).color, _c.success);
      expect(_dot(tester).shape, BoxShape.circle);
      expect(tester.getSize(find.byType(StatusDot)), const Size(8, 8));

      await show(Status.danger);
      expect(_dot(tester).color, _c.danger);

      await show(Status.attention);
      expect(_dot(tester).color, _c.attention);
      expect(find.byType(AttentionRing), findsNothing);

      await show(Status.attention, animated: true);
      expect(find.byType(AttentionRing), findsOneWidget);

      await show(Status.running);
      expect(_dot(tester).color, _c.running);
      await show(Status.running, animated: true);
      expect(find.byType(Spinner), findsOneWidget);

      for (final s in [Status.background, Status.waiting]) {
        await show(s);
        expect(
          tester.widget<EgIcon>(find.byType(EgIcon)).icon,
          EgIcons.hourglass,
        );
        expect(tester.widget<EgIcon>(find.byType(EgIcon)).color, _c.waiting);
      }
      await show(Status.retrying);
      expect(tester.widget<EgIcon>(find.byType(EgIcon)).icon, EgIcons.refresh);

      await show(Status.idle);
      expect(_dot(tester).color, isNull);
      expect((_dot(tester).border! as Border).top.color, _c.textDisabled);
      await show(Status.dead);
      expect((_dot(tester).border! as Border).top.color, _c.lineStrong);
      await tester.pumpWidget(const SizedBox());
    });

    testEg('tamanho sm é 6 e o rótulo usa o nome do estado', (tester) async {
      await tester.pumpWidget(
        egHost(const StatusDot(Status.success, size: StatusDotSize.sm)),
      );
      expect(tester.getSize(find.byType(StatusDot)), const Size(6, 6));
      await tester.pumpWidget(
        egHost(const StatusDot(Status.attention, showLabel: true)),
      );
      expect(find.text('Precisa de você'), findsOneWidget);
      await tester.pumpWidget(
        egHost(const StatusDot(Status.attention, label: 'Pedido')),
      );
      expect(find.text('Pedido'), findsOneWidget);
    });

    test('os nove estados têm nome em português', () {
      expect(Status.values.length, 9);
      expect(Status.values.every((s) => s.label.isNotEmpty), isTrue);
    });
  });

  group('AttentionRing e Spinner', () {
    test('o halo segue o pulso da v3: 0px a 0x66 → 5px transparente → 0px', () {
      final base = _c.attention;
      final start = haloAt(0, base);
      expect(start.spread, 0);
      expect(start.color, base.withAlpha(0x66));
      final peak = haloAt(0.7, base);
      expect(peak.spread, closeTo(5, 1e-9));
      expect(peak.color.a, closeTo(0, 1e-3));
      expect(haloAt(1, base).spread, closeTo(0, 1e-9));
      expect(haloAt(0.35, base).spread, inInclusiveRange(0, 5));
      expect(haloAt(0.35, base).color.a, inExclusiveRange(0, 0x66 / 255));
    });

    test('o pulso verde é o mesmo, na cor success', () {
      final green = _c.success;
      expect(haloAt(0, green).color, green.withAlpha(0x66));
      expect(haloAt(0.7, green).spread, closeTo(5, 1e-9));
    });

    testEg(
      'o halo pulsa e leva o anel de 1.5px; com movimento reduzido, é mais lento',
      (tester) async {
        List<BoxShadow> shadows() {
          final box =
              tester
                      .widget<DecoratedBox>(
                        find
                            .descendant(
                              of: find.byType(AttentionRing),
                              matching: find.byType(DecoratedBox),
                            )
                            .first,
                      )
                      .decoration
                  as BoxDecoration;
          return box.boxShadow!;
        }

        const ring = AttentionRing(
          round: true,
          child: SizedBox(width: 8, height: 8),
        );
        await tester.pumpWidget(egHost(ring));
        expect(shadows().length, 2);
        expect(shadows().last.color, _c.attention);
        expect(shadows().last.spreadRadius, 1.5);
        await tester.pump(const Duration(milliseconds: 800));
        final normal = shadows().first.spreadRadius;
        expect(normal, greaterThan(0));

        await tester.pumpWidget(egHost(reduceMotion: true, ring));
        await tester.pump(const Duration(milliseconds: 800));
        final slow = shadows().first.spreadRadius;
        // 800 ms de 3200 ainda sobe; de 1600 já passou do pico.
        expect(slow, isNot(normal));
        await tester.pumpWidget(
          egHost(
            const AttentionRing(
              ring: false,
              child: SizedBox(width: 8, height: 8),
            ),
          ),
        );
        expect(shadows().length, 1);
      },
    );

    testEg('o spinner gira em 900 ms e, com movimento reduzido, em 1800 ms', (
      tester,
    ) async {
      double turns() => tester
          .widget<RotationTransition>(find.byType(RotationTransition))
          .turns
          .value;
      await tester.pumpWidget(egHost(const Spinner()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(turns(), closeTo(300 / 900, 0.02));
      await tester.pumpWidget(egHost(reduceMotion: true, const Spinner()));
      await tester.pump(const Duration(milliseconds: 300));
      expect(turns(), closeTo(300 / 1800, 0.02));
    });
  });

  group('Counter, Badge, Clock e ContextRing', () {
    testEg('contador: neutro, atenção, segundo plano e 99+', (tester) async {
      BoxDecoration box() =>
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(Counter),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      await tester.pumpWidget(egHost(const Counter(3)));
      expect(box().color, _c.steelActive);
      await tester.pumpWidget(
        egHost(const Counter(2, tone: CounterTone.attention)),
      );
      expect(box().color, _c.attention);
      expect(tester.widget<Text>(find.text('2')).style!.color, _c.onAttention);
      await tester.pumpWidget(
        egHost(Counter(4, tone: CounterTone.waiting, icon: EgIcons.hourglass)),
      );
      expect(box().color, _c.waitingSoft);
      expect(find.byType(EgIcon), findsOneWidget);
      await tester.pumpWidget(egHost(const Counter(120)));
      expect(find.text('99+'), findsOneWidget);
      expect(box().borderRadius, BorderRadius.circular(EgeonRadius.full));
    });

    testEg('badge: tons, ícone do estado e sem ícone', (tester) async {
      await tester.pumpWidget(
        egHost(Badge('Falhou', tone: BadgeTone.status(Status.danger))),
      );
      expect(tester.widget<EgIcon>(find.byType(EgIcon)).icon, EgIcons.octagon);
      await tester.pumpWidget(
        egHost(Badge('Rodando', tone: BadgeTone.status(Status.running))),
      );
      expect(find.byType(Spinner), findsOneWidget);
      await tester.pumpWidget(
        egHost(const Badge('órfão', tone: BadgeTone.outline, showIcon: false)),
      );
      expect(find.byType(EgIcon), findsNothing);
      await tester.pumpWidget(
        egHost(Badge('Ok', tone: BadgeTone.status(Status.success))),
      );
      expect(tester.widget<EgIcon>(find.byType(EgIcon)).icon, EgIcons.check);
      await tester.pumpWidget(const SizedBox());
    });

    testEg(
      'cronômetro: três fases, apagada quando zerada; compacto só a que manda',
      (tester) async {
        await tester.pumpWidget(
          egHost(
            const WorkbenchClock(
              work: Duration(minutes: 12, seconds: 4),
              you: Duration(minutes: 0, seconds: 48),
            ),
          ),
        );
        expect(find.text('12:04'), findsOneWidget);
        expect(find.text('00:48'), findsOneWidget);
        expect(find.text('00:00'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('00:00')).style!.color,
          _c.textMuted,
        );
        expect(
          tester.widget<Text>(find.text('00:48')).style!.color,
          _c.attention,
        );
        expect(
          tester.widget<Text>(find.text('12:04')).style!.color,
          _c.textSecondary,
        );

        await tester.pumpWidget(
          egHost(
            const WorkbenchClock(
              work: Duration(minutes: 12, seconds: 4),
              you: Duration(minutes: 0, seconds: 48),
              compact: true,
            ),
          ),
        );
        expect(find.text('00:48'), findsOneWidget);
        expect(find.text('12:04'), findsNothing);

        await tester.pumpWidget(
          egHost(
            const WorkbenchClock(
              work: Duration(minutes: 3, seconds: 0),
              error: Duration(minutes: 0, seconds: 10),
              compact: true,
            ),
          ),
        );
        expect(find.text('00:10'), findsOneWidget);
        expect(find.text('03:00'), findsNothing);
        expect(
          tester.widgetList<EgIcon>(find.byType(EgIcon)).single.icon,
          EgIcons.octagon,
        );
        await tester.pumpWidget(egHost(const WorkbenchClock(compact: true)));
        expect(find.byType(EgIcon), findsNothing);
      },
    );

    test('ContextRing.tone: cinza, laranja a 80% e vermelho a 95%', () {
      expect(ContextRing.tone(_c, 0.5), _c.textSecondary);
      expect(ContextRing.tone(_c, 0.8), _c.attention);
      expect(ContextRing.tone(_c, 0.95), _c.danger);
    });

    testEg(
      'anel de contexto: porcentagem arredondada para cima e traço sem valor',
      (tester) async {
        await tester.pumpWidget(egHost(const ContextRing(0.412)));
        expect(find.text('42%'), findsOneWidget);
        await tester.pumpWidget(egHost(const ContextRing(null)));
        expect(find.text('—'), findsOneWidget);
        await tester.pumpWidget(
          egHost(const ContextRing(0.5, showValue: false)),
        );
        expect(find.byType(Text), findsNothing);
      },
    );
  });

  group('InfoPill, EdgeLabel e Banner', () {
    testEg('pastilha: ghost e atenção', (tester) async {
      await tester.pumpWidget(
        egHost(const InfoPill('medium', icon: EgIcons.gauge)),
      );
      expect(
        tester.widget<Text>(find.text('medium')).style!.color,
        _c.textSecondary,
      );
      await tester.pumpWidget(
        egHost(const InfoPill('pede você', tone: InfoPillTone.attention)),
      );
      expect(
        tester.widget<Text>(find.text('pede você')).style!.color,
        _c.attention,
      );
    });

    testEg('rótulo de aresta: usados/limite, infinito e estados', (
      tester,
    ) async {
      await tester.pumpWidget(egHost(const EdgeLabel(used: 3, max: 5)));
      expect(find.text('3/5'), findsOneWidget);
      await tester.pumpWidget(egHost(const EdgeLabel()));
      expect(find.text('∞'), findsOneWidget);
      await tester.pumpWidget(
        egHost(
          const EdgeLabel(used: 1, max: 2, state: EdgeLabelState.selected),
        ),
      );
      expect(tester.widget<Text>(find.text('1/2')).style!.color, _c.accent);
      await tester.pumpWidget(
        egHost(const EdgeLabel(used: 5, max: 5, state: EdgeLabelState.spent)),
      );
      expect(
        tester.widget<Text>(find.text('5/5')).style!.color,
        _c.textDisabled,
      );
      await tester.pumpWidget(
        egHost(const EdgeLabel(used: 2, max: 5, state: EdgeLabelState.active)),
      );
      expect(tester.widget<Text>(find.text('2/5')).style!.color, _c.running);
      await tester.pumpWidget(egHost(const EdgeLabel(used: 0, max: 5)));
      expect(tester.widget<Text>(find.text('0/5')).style!.color, _c.textMuted);
    });

    testEg('banner: ícone do tom, texto, ação e Fechar', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        egHost(
          NoticeBanner(
            tone: BannerTone.danger,
            action: const Text('Tentar de novo'),
            onDismiss: () => closed++,
            child: const Text('A conexão caiu.'),
          ),
        ),
      );
      expect(find.text('A conexão caiu.'), findsOneWidget);
      expect(find.text('Tentar de novo'), findsOneWidget);
      expect(
        tester.widgetList<EgIcon>(find.byType(EgIcon)).first.icon,
        EgIcons.octagon,
      );
      await tester.tap(find.byType(EgIcon).last);
      expect(closed, 1);
    });
  });

  group('CodeBlock', () {
    test('o realçador pinta comentário em itálico, texto, número, palavra-chave e função', () {
      final spans = highlightLine("const x = f(42, 'a'); // fim", _c);
      Color? colorOf(String t) =>
          spans.firstWhere((s) => s.text == t).style?.color;
      expect(colorOf('const'), _c.synKeyword);
      expect(colorOf('f'), _c.synFunction);
      expect(colorOf('42'), _c.synNumber);
      expect(colorOf("'a'"), _c.synString);
      final comment = spans.firstWhere((s) => s.text!.startsWith('//'));
      expect(comment.style!.color, _c.synComment);
      expect(comment.style!.fontStyle, FontStyle.italic);
      expect(spans.map((s) => s.text).join(), "const x = f(42, 'a'); // fim");
    });

    testEg('números de linha a partir de start, cabeçalho e copiar', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(
          const CodeBlock('a\nb\nc', filename: 'x.ts', lang: 'ts', start: 10),
        ),
      );
      expect(find.text('10'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('x.ts'), findsOneWidget);
      await tester.pumpWidget(
        egHost(const CodeBlock('a\nb', lineNumbers: false)),
      );
      expect(find.text('1'), findsNothing);
    });
  });

  group('DiffView', () {
    const rows = [
      DiffRow(left: DiffCell(1, 'igual'), right: DiffCell(1, 'igual')),
      DiffRow(
        left: DiffCell(2, 'a [-velho] b', sign: DiffSign.removed),
        right: DiffCell(2, 'a [+novo] b', sign: DiffSign.added),
      ),
      DiffRow(right: DiffCell(3, 'só nova', sign: DiffSign.added)),
      DiffRow.fold('⋯ 5 linhas'),
    ];

    test('unificado: contexto uma vez, remoção antes da adição', () {
      final u = DiffView.unify(rows);
      expect(u.length, 5);
      expect(u[0].right?.text, 'igual');
      expect(u[1].left?.sign, DiffSign.removed);
      expect(u[2].right?.sign, DiffSign.added);
      expect(u[3].right?.text, 'só nova');
      expect(u[4].fold, '⋯ 5 linhas');
    });

    test('palavras [+x] e [-x] ganham o fundo de palavra', () {
      final spans = diffSpans('a [-velho] b [+novo]', _c).cast<TextSpan>();
      expect(spans.map((s) => s.text).toList(), ['a ', 'velho', ' b ', 'novo']);
      expect(spans[1].style!.backgroundColor, _c.diffDelWord);
      expect(spans[3].style!.backgroundColor, _c.diffAddWord);
    });

    testEg('lado a lado: fundos diff-*, sinais e contagens', (tester) async {
      await tester.pumpWidget(
        egHost(
          const SizedBox(
            width: 600,
            child: DiffView(
              filename: 'a.dart',
              rows: rows,
              added: 2,
              removed: 1,
            ),
          ),
        ),
      );
      expect(find.text('a.dart'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('−1'), findsOneWidget);
      expect(find.text('⋯ 5 linhas'), findsNWidgets(2));
      final colors = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((b) => b.color);
      expect(colors, contains(_c.diffAddBg));
      expect(colors, contains(_c.diffDelBg));
    });

    testEg('unificado mostra cada linha numa coluna só', (tester) async {
      await tester.pumpWidget(
        egHost(
          const SizedBox(
            width: 600,
            child: DiffView(
              filename: 'a.dart',
              rows: rows,
              mode: DiffMode.unified,
            ),
          ),
        ),
      );
      expect(find.text('igual'), findsOneWidget);
    });
  });

  group('UsageBar', () {
    testEg('largura proporcional ao valor, cor por tarifa e legenda', (
      tester,
    ) async {
      await tester.pumpWidget(
        egHost(
          const SizedBox(
            width: 400,
            child: UsageBar(
              title: 'Consumo',
              totalLabel: 'US\$ 1,00',
              max: 100,
              segments: [
                UsageSegment(
                  tariff: Tariff.output,
                  value: 50,
                  display: 'US\$ 0,60',
                  tokens: '14K',
                ),
                UsageSegment(
                  tariff: Tariff.cacheRead,
                  value: 25,
                  display: 'US\$ 0,40',
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Consumo'), findsOneWidget);
      expect(find.text('Saída'), findsOneWidget);
      expect(find.text('Cache lido'), findsOneWidget);
      expect(find.text('14K tokens'), findsOneWidget);
      expect(find.text('US\$ 0,60'), findsOneWidget);
      final bar = tester.getSize(find.byType(ClipRRect).first);
      final segments = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .where((b) => b.color == _c.idIris || b.color == _c.idTeal)
          .toList();
      expect(segments.length, greaterThanOrEqualTo(2));
      final iris = tester.getSize(
        find
            .byWidgetPredicate((w) => w is ColoredBox && w.color == _c.idIris)
            .first,
      );
      expect(iris.width, closeTo(bar.width * 0.5, 1));
    });

    testEg('sem legenda não a mostra', (tester) async {
      await tester.pumpWidget(
        egHost(
          const SizedBox(
            width: 400,
            child: UsageBar(
              legend: false,
              segments: [
                UsageSegment(tariff: Tariff.input, value: 1, display: 'x'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Entrada'), findsNothing);
    });
  });
}
