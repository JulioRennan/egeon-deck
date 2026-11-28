import 'package:egeon_deck/commons/widgets/eg/eg_icon.dart';
import 'package:egeon_deck/commons/widgets/eg/status_dot.dart';
import 'package:egeon_deck/commons/widgets/workspace_mark.dart';
import 'package:egeon_deck/core/domain/entities/activity_summary.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/sidebar_tree.dart';
import 'package:egeon_deck/features/usage/domain/entities/usage_view.dart';
import 'package:egeon_deck/features/sidebar/domain/entities/stack_badge.dart';
import 'package:egeon_deck/features/sidebar/presentation/widgets/sidebar_item.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';
import '../../support/fake_usage_repository.dart';
import '../../support/inject_fakes.dart';
import '../../support/sidebar_fixtures.dart';

const _c = EgeonColors.dark;

Widget _host(Widget child) => egHost(SizedBox(width: 320, child: child));

void main() {
  testEg(
    'workspace: 44 de altura mínima, inicial em quadrado de 26, nome e contagem',
    (tester) async {
      await tester.pumpWidget(
        _host(
          SidebarItem.workspace(
            workspace: const SidebarWorkspace(id: 'w', name: 'duck'),
            onPressed: () {},
            onMenu: (_) {},
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(SidebarItem)).height,
        greaterThanOrEqualTo(44),
      );
      expect(find.text('D'), findsOneWidget);
      expect(tester.getSize(find.byType(WorkspaceMark)), const Size(26, 26));
      expect(find.text('duck'), findsOneWidget);
      expect(find.text('0 bancadas'), findsOneWidget);
      expect(find.byType(StatusDot), findsNothing);
    },
  );

  testEg('workspace: o ponto laranja aparece quando algo precisa de você', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SidebarItem.workspace(
          workspace: const SidebarWorkspace(
            id: 'w',
            name: 'duck',
            activity: ActivitySummary(attention: 1),
          ),
          onPressed: () {},
          onMenu: (_) {},
        ),
      ),
    );
    expect(find.byType(StatusDot), findsOneWidget);
  });

  testEg('workspace com foto cai na inicial se o arquivo não abre', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const WorkspaceMark(name: 'casa', iconPath: '/nao/existe.png')),
    );
    await tester.pump();
    expect(find.text('C'), findsOneWidget);
  });

  testEg('projeto: pasta, nome em textPrimary e a contagem sempre à vista', (
    tester,
  ) async {
    final project = SidebarProject(
      id: 'p',
      name: 'egeon',
      path: '~/egeon',
      benches: [bench('a'), bench('b')],
    );
    await tester.pumpWidget(
      _host(
        SidebarItem.project(
          project: project,
          owner: const SidebarWorkspace(id: 'w', name: 'W'),
          onPressed: () {},
          onMenu: (_) {},
          onAdd: () {},
        ),
      ),
    );
    expect(tester.getSize(find.byType(SidebarItem)).height, 32);
    expect(
      tester.widgetList<EgIcon>(find.byType(EgIcon)).map((i) => i.icon.name),
      contains('folder'),
    );
    expect(find.text('2'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('egeon')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('2'), findsOneWidget, reason: 'a contagem fica no hover');
    expect(
      tester.widget<Text>(find.text('egeon')).style!.color,
      EgeonColors.dark.textPrimary,
    );
    await mouse.removePointer();
  });

  testEg('projeto guardado leva o ícone da gaveta; sem caminho, o alerta', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SidebarItem.project(
          project: const SidebarProject(
            id: 'p',
            name: 'velho',
            path: '~/velho',
            pathExists: false,
            stored: true,
          ),
          owner: const SidebarWorkspace(id: 'w', name: 'W'),
          onPressed: () {},
          onMenu: (_) {},
          onAdd: () {},
        ),
      ),
    );
    final icons = tester
        .widgetList<EgIcon>(find.byType(EgIcon))
        .map((i) => i.icon.name);
    expect(icons, containsAll(['archive', 'alert']));
    expect(tester.widget<Text>(find.text('velho')).style!.color, _c.danger);
  });

  testEg('bancada: nome na cor, 500; selecionada 600 com fundo a 12% e traço', (
    tester,
  ) async {
    injectFakes();
    Future<void> show({required bool selected}) => tester.pumpWidget(
      _host(
        SidebarItem.bench(
          bench: bench('deck', selected: selected, color: 'red'),
          onPressed: () {},
          onMenu: (_) {},
        ),
      ),
    );
    await show(selected: false);
    var name = tester.widget<Text>(find.text('deck'));
    expect(name.style!.color, _c.idRose);
    expect(name.style!.fontWeight, FontWeight.w500);

    await show(selected: true);
    name = tester.widget<Text>(find.text('deck'));
    expect(name.style!.fontWeight, FontWeight.w600);
    final fills = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((d) => (d.decoration as BoxDecoration).color);
    expect(fills, contains(_c.idRose.withValues(alpha: 0.12)));
    expect(fills, contains(_c.idRose), reason: 'o traço da selecionada');
  });

  testEg('bancada de nome longo vai a duas linhas e corta', (tester) async {
    injectFakes();
    await tester.pumpWidget(
      _host(
        SidebarItem.bench(
          bench: bench(
            'x',
            name: 'Atualizar planilhas a partir de books e fichas ' * 3,
          ),
          onPressed: () {},
          onMenu: (_) {},
        ),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testEg('a gaveta dos guardados: "Gaveta vazia" não abre, "Gaveta · N" abre', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(DrawerRow(count: 0, open: false, onToggle: () => taps++)),
    );
    expect(find.text('Gaveta vazia'), findsOneWidget);
    await tester.tap(find.text('Gaveta vazia'));
    expect(taps, 0);
    await tester.pumpWidget(
      _host(DrawerRow(count: 2, open: false, onToggle: () => taps++)),
    );
    expect(find.text('Gaveta · 2'), findsOneWidget);
    await tester.tap(find.text('Gaveta · 2'));
    expect(taps, 1);
    expect(tester.getSize(find.byType(DrawerRow)).height, DrawerRow.height);
    expect(EgeonSize.row, 32);
  });

  testEg('o hover revela o ⋯ e o botão direito pede o menu no ponto', (
    tester,
  ) async {
    injectFakes();
    final anchors = <Rect>[];
    await tester.pumpWidget(
      _host(
        SidebarItem.bench(
          bench: bench('deck'),
          onPressed: () {},
          onMenu: anchors.add,
        ),
      ),
    );
    final opacity = tester
        .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
        .opacity;
    expect(opacity, 0);
    await tester.tapAt(
      tester.getCenter(find.text('deck')),
      buttons: kSecondaryButton,
    );
    expect(anchors.single.width, 0, reason: 'âncora é um ponto');
  });

  testEg(
    'bancada: os estados dos agentes aparecem juntos; Parada só sem nenhum',
    (tester) async {
      injectFakes();
      Widget item(ActivitySummary activity, {bool selected = false}) => _host(
        SidebarItem.bench(
          bench: bench('a', activity: activity, selected: selected),
          onPressed: () {},
          onMenu: (_) {},
        ),
      );
      await tester.pumpWidget(
        item(const ActivitySummary(attention: 2, working: 2, done: 1)),
      );
      expect(find.text('2 esperando você'), findsOneWidget);
      expect(find.text('1 terminou'), findsOneWidget);
      expect(find.text('2 em trabalho'), findsOneWidget);
      expect(find.text('Parada'), findsNothing);

      // Na bancada selecionada também: o estado é o dos agentes.
      await tester.pumpWidget(
        item(const ActivitySummary(done: 1), selected: true),
      );
      expect(find.text('1 terminou'), findsOneWidget);
      expect(find.text('Parada'), findsNothing);

      await tester.pumpWidget(item(ActivitySummary.none));
      expect(find.text('Parada'), findsOneWidget);
    },
  );

  testEg(
    'bancada: o traço fica 11 à esquerda do cartão, curto e inteiro no hover',
    (tester) async {
      injectFakes();
      await tester.pumpWidget(
        _host(
          SidebarItem.bench(
            bench: bench('a'),
            onPressed: () {},
            onMenu: (_) {},
          ),
        ),
      );
      final card = tester.getTopLeft(find.byType(SidebarItem));
      final bar = find.byKey(const ValueKey('bench-bar'));
      expect(tester.getTopLeft(bar).dx, card.dx - 11);
      expect(tester.getSize(bar).width, 2);
      final resting = tester.getSize(bar).height;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(SidebarItem)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getSize(bar).height, greaterThan(resting));
      expect(
        tester.getSize(bar).height,
        tester.getSize(find.byType(SidebarItem)).height,
      );
      await mouse.removePointer();
    },
  );

  testEg(
    'bancada: o preço fica sempre embaixo, numa linha só dele, mesmo cabendo',
    (tester) async {
      final usage = FakeUsageRepository(
        const UsageView(pill: UsagePillView(text: 'US\$ 3,04')),
      );
      injectFakes(usage: usage);
      Future<void> mount(ActivitySummary activity) => tester.pumpWidget(
        _host(
          SidebarItem.bench(
            bench: bench('a', activity: activity),
            onPressed: () {},
            onMenu: (_) {},
          ),
        ),
      );
      Future<void> check(ActivitySummary activity, Finder state) async {
        await mount(activity);
        await tester.pump();
        await tester.pump();
        final cost = find.byKey(const ValueKey('bench-cost-a'));
        expect(cost, findsOneWidget);
        expect(
          tester.getTopLeft(cost).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(state).dy),
          reason: 'o preço desce para a própria linha',
        );
        expect(tester.getTopLeft(cost).dx, tester.getTopLeft(state).dx);
      }

      // Um estado só cabia ao lado do preço; mesmo assim o preço desce.
      await check(
        const ActivitySummary(done: 1),
        find.byKey(const ValueKey('state-done')),
      );
      // Vários estados: o preço continua abaixo de todos.
      await check(
        const ActivitySummary(attention: 2, working: 2, done: 1),
        find.byKey(const ValueKey('state-work')),
      );
    },
  );

  testEg('projeto: os selos de stack vêm sob o nome; sem eles, nada', (
    tester,
  ) async {
    Widget item(List<StackBadge> stacks) => _host(
      SidebarItem.project(
        project: SidebarProject(
          id: 'p',
          name: 'egeon',
          path: '~/egeon',
          stacks: stacks,
        ),
        owner: const SidebarWorkspace(id: 'w', name: 'W'),
        onPressed: () {},
        onMenu: (_) {},
        onAdd: () {},
      ),
    );
    await tester.pumpWidget(item(const []));
    expect(find.byKey(const ValueKey('stack-Rs')), findsNothing);
    expect(tester.getSize(find.byType(SidebarItem)).height, 32);

    await tester.pumpWidget(
      item(const [
        StackBadge(abbr: 'Rs', name: 'Rust'),
        StackBadge(abbr: 'Dt', name: 'Flutter'),
      ]),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('stack-Rs'))),
      const Size(16, 16),
    );
    expect(find.text('Dt'), findsOneWidget);
    final name = tester.getBottomLeft(find.text('egeon')).dy;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('stack-Rs'))).dy,
      greaterThan(name),
    );
  });
}
