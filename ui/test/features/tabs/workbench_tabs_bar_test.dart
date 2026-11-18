import 'package:egeon_deck/core/domain/entities/activity_summary.dart';
import 'package:egeon_deck/features/tabs/domain/entities/workbench_tab.dart';
import 'package:egeon_deck/features/tabs/presentation/widgets/workbench_tab_pill.dart';
import 'package:egeon_deck/features/tabs/presentation/widgets/workbench_tabs_bar.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Porte de WorkbenchTabsBarTests.swift, mais o clique, o ✕ e o arrasto que o
// Swift fazia com o laço de eventos da janela.
WorkbenchTab tab(
  String name, {
  bool active = false,
  ActivitySummary summary = ActivitySummary.none,
}) => WorkbenchTab(id: name, name: name, isActive: active, summary: summary);

class Harness {
  final picked = <String>[];
  final closed = <String>[];
  final reordered = <List<String>>[];

  Widget bar(List<WorkbenchTab> tabs, {double width = 900, double inset = 0}) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: WorkbenchTabsBar(
              tabs: tabs,
              leftInset: inset,
              onPick: picked.add,
              onClose: closed.add,
              onReorder: reordered.add,
            ),
          ),
        ),
      );
}

Finder pill(String id) => find.byKey(ValueKey('tab-$id'));

List<String> onScreen(WidgetTester tester, List<String> ids) => [...ids]
  ..sort(
    (a, b) =>
        tester.getTopLeft(pill(a)).dx.compareTo(tester.getTopLeft(pill(b)).dx),
  );

void main() {
  testWidgets('toda aba ganha uma pastilha visível, dentro da faixa', (
    tester,
  ) async {
    final h = Harness();
    await tester.pumpWidget(
      h.bar([tab('deck', active: true), tab('nexus'), tab('revisor')]),
    );
    final barBox = tester.getRect(find.byType(WorkbenchTabsBar));
    for (final id in ['deck', 'nexus', 'revisor']) {
      expect(pill(id), findsOneWidget, reason: 'faixa montada sem $id');
      final rect = tester.getRect(pill(id));
      expect(rect.width, greaterThan(0), reason: '$id sem largura');
      expect(rect.height, greaterThan(0), reason: '$id sem altura');
      expect(rect.top, greaterThanOrEqualTo(barBox.top), reason: '$id acima');
      expect(
        rect.bottom,
        lessThanOrEqualTo(barBox.bottom),
        reason: '$id abaixo',
      );
      expect(rect.left, lessThan(barBox.right), reason: '$id fora da faixa');
    }
  });

  testWidgets('as pastilhas ficam lado a lado, sem empilhar no mesmo x', (
    tester,
  ) async {
    await tester.pumpWidget(
      Harness().bar([tab('um'), tab('dois'), tab('três')]),
    );
    final xs = [
      'um',
      'dois',
      'três',
    ].map((id) => tester.getTopLeft(pill(id)).dx).toList();
    expect(xs.toSet().length, 3, reason: 'pastilhas empilhadas no mesmo lugar');
    expect(xs, [...xs]..sort());
  });

  testWidgets('a faixa respeita o recuo da barra lateral', (tester) async {
    await tester.pumpWidget(Harness().bar([tab('a')], inset: 200));
    expect(tester.getTopLeft(pill('a')).dx, 200 + WorkbenchTabsBar.gap);
  });

  testWidgets('com abas demais, encolhem juntas e continuam dentro da faixa', (
    tester,
  ) async {
    final ids = [for (var i = 0; i < 12; i++) 'bancada-numero-$i'];
    await tester.pumpWidget(
      Harness().bar([for (final id in ids) tab(id)], width: 1000),
    );
    for (final id in ids) {
      final rect = tester.getRect(pill(id));
      expect(rect.right, lessThanOrEqualTo(1000 + 1), reason: id);
      expect(rect.width, greaterThanOrEqualTo(WorkbenchTabsBar.minWidth));
    }
  });

  testWidgets('clicar numa aba a escolhe', (tester) async {
    final h = Harness();
    await tester.pumpWidget(h.bar([tab('a', active: true), tab('b')]));
    await tester.tapAt(tester.getCenter(pill('b')) - const Offset(20, 0));
    expect(h.picked, ['b']);
    expect(h.reordered, isEmpty);
  });

  testWidgets('o ✕ fecha a aba e não a escolhe', (tester) async {
    final h = Harness();
    await tester.pumpWidget(h.bar([tab('a', active: true), tab('b')]));
    await tester.tap(find.text('✕'));
    expect(h.closed, ['a']);
    expect(h.picked, isEmpty);
  });

  testWidgets('o ✕ só aparece na ativa ou sob o ponteiro', (tester) async {
    await tester.pumpWidget(Harness().bar([tab('a', active: true), tab('b')]));
    expect(find.text('✕'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(pill('b')));
    await tester.pump();
    expect(find.text('✕'), findsNWidgets(2));
    await mouse.removePointer();
  });

  testWidgets('arrastar além do limiar reordena e avisa a ordem final', (
    tester,
  ) async {
    final h = Harness();
    await tester.pumpWidget(
      h.bar([tab('a', active: true), tab('b'), tab('c')]),
    );

    final from = tester.getCenter(pill('a')) - const Offset(20, 0);
    final gesture = await tester.startGesture(from);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(400, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(onScreen(tester, ['a', 'b', 'c']), ['b', 'c', 'a']);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(h.reordered, [
      ['b', 'c', 'a'],
    ]);
    expect(h.picked, isEmpty, reason: 'soltar depois de arrastar não é clique');
    expect(onScreen(tester, ['a', 'b', 'c']), ['b', 'c', 'a']);
  });

  testWidgets('movimento abaixo do limiar ainda é clique', (tester) async {
    final h = Harness();
    await tester.pumpWidget(h.bar([tab('a'), tab('b')]));
    final gesture = await tester.startGesture(
      tester.getCenter(pill('b')) - const Offset(20, 0),
    );
    await gesture.moveBy(const Offset(3, 0));
    await gesture.up();
    expect(h.picked, ['b']);
    expect(h.reordered, isEmpty);
  });

  testWidgets('a ordem que vem do core reordena sem recriar as pastilhas', (
    tester,
  ) async {
    final h = Harness();
    await tester.pumpWidget(h.bar([tab('a'), tab('b'), tab('c')]));
    final antes = {
      for (final id in ['a', 'b', 'c']) id: tester.element(pill(id)),
    };

    await tester.pumpWidget(h.bar([tab('c'), tab('a'), tab('b')]));
    await tester.pump(const Duration(milliseconds: 300));

    expect(onScreen(tester, ['a', 'b', 'c']), ['c', 'a', 'b']);
    for (final id in ['a', 'b', 'c']) {
      expect(tester.element(pill(id)), same(antes[id]), reason: '$id recriada');
    }
  });

  testWidgets('trocar só o estado não remonta as pastilhas', (tester) async {
    final h = Harness();
    await tester.pumpWidget(h.bar([tab('a', active: true), tab('b')]));
    final antes = tester.element(pill('a'));
    await tester.pumpWidget(
      h.bar([
        tab('a', active: true, summary: const ActivitySummary(working: 1)),
        tab('b'),
      ]),
    );
    expect(tester.element(pill('a')), same(antes));
  });

  testWidgets('os avisos saem na ordem fixa: trabalhando, atenção, pronto', (
    tester,
  ) async {
    await tester.pumpWidget(
      Harness().bar([
        tab(
          'a',
          summary: const ActivitySummary(working: 2, attention: 1, done: 3),
        ),
      ]),
    );
    final text = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((w) => w.text.toPlainText())
        .firstWhere((t) => t.contains('●'));
    expect(text.replaceAll(RegExp('[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]'), 'S'), 'S2 ● ●3');
    expect(
      WorkbenchTabPill.fittingWidth(tab('a')),
      lessThan(
        WorkbenchTabPill.fittingWidth(
          tab('a', summary: const ActivitySummary(working: 2, done: 3)),
        ),
      ),
    );
  });
}
