import 'package:egeon_deck/commons/widgets/eg/glass_surface.dart';
import 'package:egeon_deck/commons/widgets/eg/spinner.dart';
import 'package:egeon_deck/core/domain/entities/activity_summary.dart';
import 'package:egeon_deck/features/home/presentation/widgets/bench_rail.dart';
import 'package:egeon_deck/features/tabs/domain/entities/workbench_tab.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:egeon_deck/commons/widgets/eg/attention_ring.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

const _c = EgeonColors.dark;

Widget _rail(
  List<WorkbenchTab> tabs, {
  bool open = false,
  List<String>? log,
  bool manage = false,
}) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(
    height: 600,
    child: BenchRail(
      tabs: tabs,
      drawerOpen: open,
      onPick: (id) => log?.add('pick:$id'),
      onNew: () => log?.add('nova'),
      onToggleDrawer: () => log?.add('gaveta'),
      onClose: manage ? (id) => log?.add('fechar:$id') : null,
      onReorder: manage ? (ids) => log?.add('ordem:${ids.join(',')}') : null,
    ),
  ),
);

WorkbenchTab _tab(
  String id,
  String name, {
  bool active = false,
  String? color,
  ActivitySummary summary = ActivitySummary.none,
}) => WorkbenchTab(
  id: id,
  name: name,
  isActive: active,
  color: color,
  summary: summary,
);

void main() {
  test('as iniciais: primeira maiúscula, segunda como está', () {
    expect(BenchRail.initials('egeon-deck'), 'Eg');
    expect(BenchRail.initials('AGROS-3662'), 'AG');
    expect(BenchRail.initials('Análise de performance'), 'An');
    expect(BenchRail.initials('x'), 'X');
    expect(BenchRail.initials('  '), '?');
  });

  testEg(
    '44 de largura, com Nova bancada, Todas as bancadas e uma tecla por bancada',
    (tester) async {
      await tester.pumpWidget(
        egHost(
          _rail([_tab('a', 'egeon-deck', active: true), _tab('b', 'agros')]),
        ),
      );
      // A coluna das pastilhas; a faixa em volta é a área do hover.
      final pill = find
          .descendant(
            of: find.byType(BenchRail),
            matching: find.byType(GlassSurface),
          )
          .first;
      expect(tester.getSize(pill).width, BenchRail.width);
      expect(find.bySemanticsLabel('Nova bancada'), findsOneWidget);
      expect(find.bySemanticsLabel('Todas as bancadas'), findsOneWidget);
      expect(find.text('Eg'), findsOneWidget);
      expect(find.text('Ag'), findsOneWidget);
    },
  );

  testEg('as teclas chamam pegar, nova e gaveta', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      egHost(_rail([_tab('a', 'um'), _tab('b', 'dois')], log: log)),
    );
    await tester.tap(find.text('Do'));
    await tester.tap(find.bySemanticsLabel('Nova bancada'));
    await tester.tap(find.bySemanticsLabel('Todas as bancadas'));
    expect(log, ['pick:b', 'nova', 'gaveta']);
  });

  testEg('arrastar uma tecla para baixo reordena e manda a ordem nova ao '
      'soltar', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      egHost(
        _rail(
          [_tab('a', 'um'), _tab('b', 'dois'), _tab('c', 'tres')],
          log: log,
          manage: true,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Um')),
    );
    await gesture.moveBy(const Offset(0, 10));
    await gesture.moveBy(const Offset(0, 70));
    await tester.pump();
    expect(log, isEmpty, reason: 'só manda ao soltar');
    await gesture.up();
    await tester.pump();
    expect(log, ['ordem:b,c,a']);
  });

  testEg('arrastar pouco e voltar não manda nada, e o clique ainda pega', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      egHost(
        _rail([_tab('a', 'um'), _tab('b', 'dois')], log: log, manage: true),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Um')),
    );
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, -30));
    await gesture.up();
    await tester.pump();
    expect(log, isEmpty);
    await tester.tap(find.text('Do'));
    expect(log, ['pick:b']);
  });

  testEg('o botão direito abre "Fechar bancada" e fecha a bancada', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      egHost(
        _rail([_tab('a', 'um'), _tab('b', 'dois')], log: log, manage: true),
      ),
    );
    await tester.tap(find.text('Do'), buttons: kSecondaryButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fechar bancada'), findsOneWidget);
    await tester.tap(find.text('Fechar bancada'));
    await tester.pump();
    expect(log, ['fechar:b']);
  });

  testEg('a atual leva o fundo tingido e o traço de 2px na cor dela', (
    tester,
  ) async {
    await tester.pumpWidget(
      egHost(
        _rail([
          _tab('a', 'um', active: true, color: 'red'),
          _tab('b', 'dois', color: 'red'),
        ]),
      ),
    );
    final rose = _c.idRose;
    Color? fill(String letters) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text(letters),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color;
    }

    expect(fill('Um'), rose.withValues(alpha: 0.14));
    expect(fill('Do'), isNot(rose.withValues(alpha: 0.14)));
    expect(tester.widget<Text>(find.text('Um')).style!.color, rose);
    final bars = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .where((b) => (b.decoration as BoxDecoration).color == rose);
    expect(bars, isNotEmpty, reason: 'o traço da atual');
  });

  testEg('o estado que aparece: pedido, terminou, trabalhando ou nada', (
    tester,
  ) async {
    String? label(WorkbenchTab tab) {
      final bench = RailBench(tab: tab, onPressed: () {});
      return bench.status;
    }

    final attention = _tab(
      'a',
      'um',
      summary: const ActivitySummary(attention: 2, working: 1, done: 1),
    );
    final done = _tab('b', 'dois', summary: const ActivitySummary(done: 1));
    final doneHere = _tab(
      'c',
      'tres',
      active: true,
      summary: const ActivitySummary(done: 1),
    );
    final work = _tab(
      'd',
      'quatro',
      summary: const ActivitySummary(working: 3),
    );
    final idle = _tab('e', 'cinco');
    expect(label(attention), '2 esperando você');
    expect(label(done), 'terminou');
    expect(
      label(doneHere),
      'terminou',
      reason: 'também na bancada que está na tela (a v3 mostra o ponto)',
    );
    expect(label(work), '3 em trabalho');
    expect(label(idle), 'parada');
    expect(
      RailBench(tab: attention, onPressed: () {}).badge,
      RailBadge.attention,
    );
    expect(RailBench(tab: done, onPressed: () {}).badge, RailBadge.done);
    expect(RailBench(tab: work, onPressed: () {}).badge, RailBadge.working);
    expect(RailBench(tab: idle, onPressed: () {}).badge, RailBadge.none);

    await tester.pumpWidget(egHost(_rail([work])));
    expect(find.byType(Spinner), findsOneWidget);
    await tester.pumpWidget(egHost(_rail([idle])));
    expect(find.byType(Spinner), findsNothing);
  });

  testEg('o ponto de terminou pulsa em verde; o de trabalhando não pulsa', (
    tester,
  ) async {
    await tester.pumpWidget(
      egHost(
        _rail([_tab('b', 'dois', summary: const ActivitySummary(done: 1))]),
      ),
    );
    final ring = tester.widget<AttentionRing>(find.byType(AttentionRing));
    expect(ring.color, _c.success);
    expect(ring.ring, isFalse);
    // Anima: o halo cresce com o tempo.
    double spread() {
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
      return box.boxShadow!.first.spreadRadius;
    }

    await tester.pump(const Duration(milliseconds: 800));
    expect(spread(), greaterThan(0));

    await tester.pumpWidget(
      egHost(
        _rail([
          _tab('d', 'quatro', summary: const ActivitySummary(working: 1)),
        ]),
      ),
    );
    expect(find.byType(AttentionRing), findsNothing);
  });

  testEg('o tooltip diz nome e estado', (tester) async {
    await tester.pumpWidget(
      egHost(
        Padding(
          padding: const EdgeInsets.all(100),
          child: _rail([
            _tab('a', 'migracao', summary: const ActivitySummary(attention: 2)),
          ]),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Mi')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('migracao · 2 esperando você'), findsOneWidget);
    await mouse.removePointer();
  });

  testEg('o contador total soma os pedidos de todas as bancadas', (
    tester,
  ) async {
    await tester.pumpWidget(
      egHost(
        _rail([
          _tab('a', 'um', summary: const ActivitySummary(attention: 2)),
          _tab('b', 'dois', summary: const ActivitySummary(attention: 3)),
        ]),
      ),
    );
    expect(find.text('5'), findsOneWidget);
    await tester.pumpWidget(egHost(_rail([_tab('a', 'um')])));
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == '0'),
      findsNothing,
    );
  });

  testEg('a gaveta aberta acende o botão (accentSoft)', (tester) async {
    await tester.pumpWidget(egHost(_rail([_tab('a', 'um')], open: true)));
    final box = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((c) => (c.decoration! as BoxDecoration).color);
    expect(box, contains(_c.accentSoft));
  });

  testEg('muitas bancadas rolam em vez de estourar', (tester) async {
    await tester.pumpWidget(
      egHost(
        SizedBox(
          height: 300,
          child: BenchRail(
            tabs: [for (var i = 0; i < 30; i++) _tab('$i', 'bancada $i')],
            drawerOpen: false,
            onPick: (_) {},
            onNew: () {},
            onToggleDrawer: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(BenchRail)).height,
      lessThanOrEqualTo(300),
    );
    expect(EgeonSize.controlMd, 36);
  });
}
