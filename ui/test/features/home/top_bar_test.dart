import 'package:egeon_deck/core/adapters/window_chrome.dart';
import 'package:egeon_deck/core/domain/entities/workbench.dart';
import 'package:egeon_deck/features/home/presentation/widgets/bench_frame.dart';
import 'package:egeon_deck/features/home/presentation/widgets/top_bar.dart';
import 'package:egeon_deck/commons/widgets/eg/menu.dart';
import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';

class _FakeChrome implements WindowChrome {
  var drags = 0;
  var zooms = 0;

  @override
  void startDrag() => drags++;

  @override
  void toggleZoom() => zooms++;
}

const _bench = Workbench(id: 'b', name: 'deck', path: '~', color: 'blue');

Widget _bar({
  required _FakeChrome chrome,
  Workbench? bench = _bench,
  bool back = true,
  bool forward = false,
  List<String>? log,
}) => SizedBox(
  width: 1000,
  child: TopBar(
    bench: bench,
    projectName: 'loja',
    chrome: chrome,
    canGoBack: back,
    canGoForward: forward,
    onBack: () => log?.add('voltar'),
    onForward: () => log?.add('avançar'),
    onSelectView: (mode) => log?.add('modo:${mode.wire}'),
    onPickBench: () => log?.add('trilha'),
  ),
);

void main() {
  testEg('44 de altura, com voltar, avançar, Canvas | Chat e a trilha', (
    tester,
  ) async {
    await tester.pumpWidget(egHost(_bar(chrome: _FakeChrome())));
    expect(tester.getSize(find.byType(TopBar)).height, EgeonSize.titlebar);
    expect(find.byKey(const ValueKey('view-canvas')), findsOneWidget);
    expect(find.byKey(const ValueKey('view-chat')), findsOneWidget);
    expect(find.text('Canvas'), findsNothing);
    expect(find.text('Chat'), findsNothing);
    expect(find.text('loja'), findsOneWidget);
    expect(find.text('deck'), findsOneWidget);
  });

  testEg('a trilha tem 32 de altura, 14/20 e vão de 8 entre as partes', (
    tester,
  ) async {
    await tester.pumpWidget(egHost(_bar(chrome: _FakeChrome())));
    expect(tester.getSize(find.byType(Breadcrumb)).height, 32);
    final style = tester.widget<Text>(find.text('deck')).style!;
    expect(style.fontSize, 14);
    expect(style.height, closeTo(20 / 14, 1e-3));
    final project = tester.getRect(find.text('loja'));
    final slash = tester.getRect(find.text('/'));
    final name = tester.getRect(find.text('deck'));
    expect(slash.left - project.right, 8);
    expect(name.left - slash.right, 8);
  });

  testEg('voltar e avançar têm 4 de vão entre si', (tester) async {
    await tester.pumpWidget(egHost(_bar(chrome: _FakeChrome())));
    final voltar = tester.getRect(find.bySemanticsLabel('Voltar'));
    final avancar = tester.getRect(find.bySemanticsLabel('Avançar'));
    expect(avancar.left - voltar.right, 4);
  });

  testEg('o foco da trilha não desloca o conteúdo', (tester) async {
    await tester.pumpWidget(egHost(_bar(chrome: _FakeChrome())));
    final rest = tester.getTopLeft(find.text('deck'));
    final focus = FocusManager.instance;
    expect(focus.primaryFocus, isNull);
    // Foco por teclado: Tab até a trilha.
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(tester.getTopLeft(find.text('deck')), rest);
  });

  testEg('voltar e avançar só respondem quando há para onde ir', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      egHost(_bar(chrome: _FakeChrome(), back: true, forward: false, log: log)),
    );
    final buttons = find.byType(Breadcrumb).evaluate().isEmpty ? null : null;
    expect(buttons, isNull);
    // O primeiro botão da faixa é Voltar, o segundo Avançar.
    final voltar = find.bySemanticsLabel('Voltar');
    final avancar = find.bySemanticsLabel('Avançar');
    await tester.tap(voltar);
    await tester.tap(avancar, warnIfMissed: false);
    expect(log, ['voltar']);
  });

  testEg('trocar a visão e a trilha chamam o que a casca pediu', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(egHost(_bar(chrome: _FakeChrome(), log: log)));
    await tester.tap(find.byKey(const ValueKey('view-chat')));
    await tester.tap(find.text('deck'));
    expect(log, ['modo:chat', 'trilha']);
  });

  testEg('sem bancada: sem trilha e sem troca de visão', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      egHost(_bar(chrome: _FakeChrome(), bench: null, log: log)),
    );
    expect(find.byType(Breadcrumb), findsNothing);
    await tester.tap(find.byKey(const ValueKey('view-chat')));
    expect(log, isEmpty);
  });

  testEg('a trilha escreve a bancada em 600 na cor dela', (tester) async {
    await tester.pumpWidget(egHost(_bar(chrome: _FakeChrome())));
    final name = tester.widget<Text>(find.text('deck'));
    expect(name.style!.fontWeight, FontWeight.w600);
    expect(name.style!.color, EgeonColors.dark.idSlate);
    final project = tester.widget<Text>(find.text('loja'));
    expect(project.style!.color, EgeonColors.dark.textSecondary);
  });

  testEg('a parte vazia arrasta a janela e maximiza no duplo clique', (
    tester,
  ) async {
    final chrome = _FakeChrome();
    await tester.pumpWidget(egHost(_bar(chrome: chrome)));
    // Bem à direita da trilha, ainda no vazio.
    final empty = Offset(700, EgeonSize.titlebar / 2);
    final drag = await tester.startGesture(empty);
    await drag.moveBy(const Offset(20, 10));
    await drag.up();
    await tester.pump();
    expect(chrome.drags, 1);

    await tester.tapAt(empty);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(empty);
    await tester.pump(const Duration(milliseconds: 400));
    expect(chrome.zooms, 1);
  });

  testEg('arrastar um botão não arrasta a janela', (tester) async {
    final chrome = _FakeChrome();
    await tester.pumpWidget(egHost(_bar(chrome: chrome)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('view-chat'))),
    );
    await gesture.moveBy(const Offset(30, 0));
    await gesture.up();
    expect(chrome.drags, 0);
  });

  testEg('no macOS a faixa deixa o lugar dos semáforos; nos outros, 16', (
    tester,
  ) async {
    // O override tem de sair antes de o teste acabar: o binding confere.
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(egHost(_bar(chrome: _FakeChrome())));
      expect(
        tester.getTopLeft(find.bySemanticsLabel('Voltar')).dx,
        TopBar.trafficLights,
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(egHost(_bar(chrome: _FakeChrome())));
      expect(
        tester.getTopLeft(find.bySemanticsLabel('Voltar')).dx,
        EgeonSpace.s4,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testEg('H6b: os flutuantes abrem a partir da faixa, sob o tema', (
    tester,
  ) async {
    await tester.pumpWidget(egHost(_bar(chrome: _FakeChrome())));
    final context = tester.element(find.byType(TopBar));
    showMenu(
      context,
      anchor: tester.getRect(find.byType(Breadcrumb)),
      items: [MenuItem('Trocar bancada', onSelected: () {})],
    );
    await tester.pumpAndSettle();
    expect(find.text('Trocar bancada'), findsOneWidget);
  });

  group('BenchFrame', () {
    testEg('desenha o fio a 18% e o brilho a 14% na cor da bancada', (
      tester,
    ) async {
      expect(GlowPainter.edgeAlpha, 0.18);
      expect(GlowPainter.glowAlpha, 0.14);
      expect(GlowPainter.glowBlur, 32);
      await tester.pumpWidget(
        egHost(
          fill: true,
          const BenchFrame(colorName: 'sand', child: SizedBox.expand()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final paint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<GlowPainter>()
          .single;
      expect(paint.color, EgeonColors.dark.idSand);
    });

    testEg('trocar de bancada troca a cor, e sem bancada não há brilho', (
      tester,
    ) async {
      Future<Color?> glow(String? name, {bool lit = true}) async {
        await tester.pumpWidget(
          egHost(
            fill: true,
            BenchFrame(
              colorName: name,
              lit: lit,
              child: const SizedBox.expand(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final found = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((c) => c.painter)
            .whereType<GlowPainter>();
        return found.isEmpty ? null : found.single.color;
      }

      expect(await glow('red'), EgeonColors.dark.idRose);
      expect(await glow('indigo'), EgeonColors.dark.idIris);
      expect(await glow(null), EgeonColors.dark.idSlate);
      expect(await glow('red', lit: false), isNull);
    });

    testEg('o painel é graphite com raio 16 e fio de vidro', (tester) async {
      await tester.pumpWidget(
        egHost(fill: true, const BenchFrame(child: SizedBox.expand())),
      );
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(BenchFrame),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, EgeonColors.dark.graphite);
      expect(decoration.borderRadius, BorderRadius.circular(16));
    });
  });
}
