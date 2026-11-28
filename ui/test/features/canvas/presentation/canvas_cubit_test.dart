import 'dart:ui';

import 'package:egeon_deck/features/canvas/domain/entities/canvas_tool.dart';
import 'package:egeon_deck/features/canvas/domain/entities/canvas_viewport.dart';
import 'package:egeon_deck/features/canvas/domain/entities/edge_link.dart';
import 'package:egeon_deck/features/canvas/domain/usecase/place_node.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_cubit.dart';
import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_tool_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/canvas_cubit_for.dart';
import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump.dart';

void main() {
  test('a bancada abre enquadrando todos os nós', () async {
    final (:cubit, repository: _) = await canvasCubitFor();
    final view = cubit.state.viewport;
    final union = cubit.state.union!;

    expect(view.zoom, lessThanOrEqualTo(1));
    // Cada canto da união cai dentro da janela.
    for (final corner in [union.topLeft, union.bottomRight]) {
      final p = view.toScreen(corner);
      expect(p.dx, inInclusiveRange(0, 1000));
      expect(p.dy, inInclusiveRange(0, 700));
    }
    await cubit.close();
  });

  test('o pan acompanha o dedo e a âncora não escorrega', () async {
    final (:cubit, repository: _) = await canvasCubitFor();
    cubit.resetZoom();
    final before = cubit.state.viewport.origin;

    cubit.beginPan(const Offset(500, 300));
    cubit.updatePan(const Offset(450, 280));
    // Arrastar 50px para a esquerda leva a vista 50px para a direita.
    expect(
      cubit.state.viewport.origin.dx,
      closeTo(before.dx + 50 / cubit.state.viewport.zoom, 0.001),
    );
    expect(cubit.state, isA<CanvasPanning>());
    cubit.endPan();
    expect(cubit.state, isA<CanvasIdle>());
    await cubit.close();
  });

  test('arrastar o pan além do canto abre espaço e desloca os cards', () async {
    final (:cubit, repository: _) = await canvasCubitFor();
    cubit.resetZoom();
    cubit.beginPan(const Offset(100, 100));
    final before = cubit.state.cards.first.frame;
    // Puxa tanto que a origem passaria de negativo.
    cubit.updatePan(Offset(100 + cubit.state.viewport.origin.dx + 400, 100));
    final after = cubit.state.cards.first.frame;
    expect(after.left, greaterThan(before.left));
    expect(cubit.state.viewport.origin.dx, greaterThanOrEqualTo(0));
    cubit.endPan();
    await cubit.close();
  });

  test('card arrastado além da borda esquerda desloca o mundo', () async {
    final (:cubit, repository: _) = await canvasCubitFor();
    cubit.resetZoom();
    final view = cubit.state.viewport;
    final a = cubit.state.cards.first;
    final grab = view.toScreen(a.frame.topLeft) + const Offset(20, 20);

    cubit.beginCardDrag('a', grab);
    // Move o mouse 300 unidades de documento para além do 0 da esquerda.
    cubit.dragCard(grab - Offset((a.frame.left + 300) * view.zoom, 0));
    final moved = cubit.state.cards.firstWhere((c) => c.id == 'a');
    final other = cubit.state.cards.firstWhere((c) => c.id == 'b');

    expect(moved.frame.left, greaterThanOrEqualTo(0));
    expect(other.frame.left, greaterThan(900), reason: 'o outro foi junto');
    cubit.endCardGesture();
    await cubit.close();
  });

  test('o frame só é gravado no fim do arrasto', () async {
    final (:cubit, :repository) = await canvasCubitFor();
    final seen = <Rect>[];
    final sub = repository
        .watch('bancada')
        .listen((s) => seen.add(s.cards.firstWhere((c) => c.id == 'a').frame));
    await pump();
    seen.clear();

    cubit.resetZoom();
    final view = cubit.state.viewport;
    final start = view.toScreen(const Offset(150, 120));
    cubit.beginCardDrag('a', start);
    cubit.dragCard(start + const Offset(40, 0));
    cubit.dragCard(start + const Offset(80, 0));
    await pump();
    expect(seen, isEmpty, reason: 'durante o gesto o core não é tocado');

    cubit.endCardGesture();
    await pump();
    expect(seen, hasLength(1));
    expect(seen.single.left, closeTo(180, 1));
    await sub.cancel();
    await cubit.close();
  });

  test('redimensionar divide o delta pelo zoom e respeita o mínimo', () async {
    final (:cubit, repository: _) = await canvasCubitFor();
    cubit.stepZoom(-1);
    final zoom = cubit.state.viewport.zoom;
    final before = cubit.state.cards.first.frame.size;

    cubit.resizeCard('a', Offset(10 * zoom, 0));
    expect(cubit.state.cards.first.frame.width, closeTo(before.width + 10, 1));

    cubit.resizeCard('a', const Offset(-100000, -100000));
    expect(cubit.state.cards.first.frame.width, 280);
    expect(cubit.state.cards.first.frame.height, 180);
    await cubit.close();
  });

  test(
    'clique com a ferramenta cria no tamanho padrão e volta ao cursor',
    () async {
      final (:cubit, :repository) = await canvasCubitFor();
      final tools = toolCubitFor(repository);
      cubit.resetZoom();
      tools.selectTool(CanvasTool.queue);

      await tools.placeByGesture(
        const Offset(200, 200),
        const Offset(203, 205),
        cubit.state.viewport,
      );
      await pump();

      expect(tools.state, isA<CanvasPointer>());
      final placed = cubit.state.cards.last;
      expect(placed.frame.size, CanvasTool.queue.defaultNodeSize);
      expect(placed.kind.name, 'queue');
      await tools.close();
      await cubit.close();
    },
  );

  test(
    'arrasto com a ferramenta desenha o retângulo, com piso no mínimo',
    () async {
      final (:cubit, :repository) = await canvasCubitFor();
      final tools = toolCubitFor(repository);
      cubit.resetZoom();
      tools.selectTool(CanvasTool.queue);
      await tools.placeByGesture(
        const Offset(200, 200),
        const Offset(300, 260),
        cubit.state.viewport,
      );
      await pump();
      final placed = cubit.state.cards.last;
      expect(placed.frame.width, 280);
      expect(placed.frame.height, 180);

      tools.selectTool(CanvasTool.web);
      await tools.placeByGesture(
        const Offset(100, 100),
        const Offset(900, 600),
        cubit.state.viewport,
      );
      await pump();
      expect(
        cubit.state.cards.last.frame.width,
        closeTo(800 / cubit.state.viewport.zoom, 1),
      );
      await tools.close();
      await cubit.close();
    },
  );

  test('o shell nasce na hora, sem formulário', () async {
    final (:cubit, :repository) = await canvasCubitFor();
    final tools = toolCubitFor(repository);
    final before = cubit.state.cards.length;
    final asked = <Rect>[];
    final subscription = tools.configureTerminal.listen(asked.add);
    cubit.resetZoom();
    tools.selectTool(CanvasTool.shell);
    await tools.placeByGesture(
      const Offset(200, 200),
      const Offset(300, 260),
      cubit.state.viewport,
    );
    await pump();
    expect(asked, isEmpty);
    expect(cubit.state.cards, hasLength(before + 1));
    await subscription.cancel();
    await tools.close();
    await cubit.close();
  });

  test('terminal de agente sem componente não nasce: pede o formulário com o retângulo', () async {
    final (:cubit, :repository) = await canvasCubitFor();
    final tools = toolCubitFor(repository);
    final before = cubit.state.cards.length;
    final asked = <Rect>[];
    final subscription = tools.configureTerminal.listen(asked.add);
    cubit.resetZoom();
    tools.selectTool(CanvasTool.agent);
    await tools.placeByGesture(
      const Offset(200, 200),
      const Offset(300, 260),
      cubit.state.viewport,
    );
    await pump();
    expect(asked, hasLength(1));
    expect(asked.single.width, 280, reason: 'o piso do mínimo vale aqui');
    expect(cubit.state.cards, hasLength(before), reason: 'nada criado');
    expect(tools.state, isA<CanvasPointer>());
    await subscription.cancel();
    await tools.close();
    await cubit.close();
  });

  test('escolher componente arma o terminal e avisa', () async {
    final (:cubit, :repository) = await canvasCubitFor();
    final tools = toolCubitFor(repository);
    tools.pickComponent('revisor');
    expect(tools.tool, CanvasTool.agent);
    expect(
      tools.state,
      isA<CanvasAnnouncing>().having(
        (s) => s.component,
        'component',
        'revisor',
      ),
    );

    await tools.placeByGesture(
      const Offset(100, 100),
      const Offset(100, 100),
      cubit.state.viewport,
    );
    await pump();
    expect(tools.state, isA<CanvasPointer>(), reason: 'vale para um nó só');
    expect(cubit.state.cards.last.title, 'revisor');
    await tools.close();
    await cubit.close();
  });

  test('o aviso do componente some e ele continua armado', () async {
    final tools = CanvasToolCubit(
      workbenchId: 'bancada',
      placeNode: PlaceNode(InMemoryCanvasRepository()),
      bannerTime: const Duration(milliseconds: 20),
    );
    tools.pickComponent(null);
    expect(tools.state, isA<CanvasAnnouncing>());
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(
      tools.state,
      isA<CanvasComponentArmed>().having((s) => s.component, 'shell', null),
    );
    tools.selectTool(CanvasTool.cursor);
    expect(tools.state, isA<CanvasPointer>());
    await tools.close();
  });

  test('a vista que se mexe avisa o movimento e depois assenta', () async {
    final (:cubit, repository: _) = await canvasCubitFor();
    final motion = <bool>[];
    final subscription = cubit.motion.listen(motion.add);
    cubit.stepZoom(1);
    await pump();
    expect(motion, [true]);
    await Future<void>.delayed(
      CanvasCubit.settleDelay + const Duration(milliseconds: 50),
    );
    expect(motion, [true, false]);
    await subscription.cancel();
    await cubit.close();
  });

  group('ligações', () {
    test('soltar o + sobre outro terminal cria a ligação', () async {
      final (:cubit, repository: _) = await canvasCubitFor();
      cubit.resetZoom();
      final view = cubit.state.viewport;

      cubit.portDrag('a', view.toScreen(const Offset(1000, 300)));
      expect(cubit.state, isA<CanvasLinking>());
      await cubit.portRelease('a', view.toScreen(const Offset(1000, 300)));
      await pump();

      expect(cubit.state, isA<CanvasIdle>());
      expect(cubit.state.links, hasLength(1));
      expect(cubit.state.links.single.aToB, isTrue);
      expect(cubit.state.links.single.bToA, isTrue);
      await cubit.close();
    });

    test('soltar no vazio, no web ou em si mesmo não cria nada', () async {
      final (:cubit, repository: _) = await canvasCubitFor();
      cubit.resetZoom();
      final view = cubit.state.viewport;
      for (final target in const [
        Offset(3000, 3000),
        Offset(300, 900),
        Offset(300, 300),
      ]) {
        await cubit.portRelease('a', view.toScreen(target));
      }
      await pump();
      expect(cubit.state.links, isEmpty);
      await cubit.close();
    });

    test('par já ligado, em qualquer sentido, não cria de novo', () async {
      final (:cubit, repository: _) = await canvasCubitFor(
        links: const [EdgeLink(a: 'a', b: 'b', aToB: false, bToA: true)],
      );
      cubit.resetZoom();
      final view = cubit.state.viewport;
      await cubit.portRelease('a', view.toScreen(const Offset(1000, 300)));
      await pump();
      expect(cubit.state.links, hasLength(1));
      await cubit.close();
    });

    test('o realce segue a linha e sobrevive aos controles', () async {
      final (:cubit, repository: _) = await canvasCubitFor(
        links: const [EdgeLink(a: 'a', b: 'b')],
      );
      cubit.resetZoom();
      final view = cubit.state.viewport;
      // O meio da linha entre a porta direita de a e a esquerda de b.
      final onLine = view.toScreen(const Offset(860, 330));
      cubit.hoverAt(onLine);
      expect(cubit.state, isA<CanvasLinkHovered>());

      // Subindo para os controles, fora da distância da linha, continua no ar.
      cubit.hoverAt(onLine + const Offset(0, -40));
      expect(cubit.state, isA<CanvasLinkHovered>());

      cubit.hoverAt(onLine + const Offset(0, -300));
      expect(cubit.state, isA<CanvasIdle>());
      await cubit.close();
    });

    test(
      'o realce continua durante o zoom: movimento é outro assunto',
      () async {
        final (:cubit, repository: _) = await canvasCubitFor(
          links: const [EdgeLink(a: 'a', b: 'b')],
        );
        cubit.resetZoom();
        cubit.hoverAt(cubit.state.viewport.toScreen(const Offset(860, 330)));
        expect(cubit.state, isA<CanvasLinkHovered>());
        cubit.stepZoom(1);
        expect(cubit.state, isA<CanvasLinkHovered>());
        await cubit.close();
      },
    );

    test('com a mão ocupada não há realce; sair tira o realce', () async {
      final (:cubit, repository: _) = await canvasCubitFor(
        links: const [EdgeLink(a: 'a', b: 'b')],
      );
      cubit.resetZoom();
      final onLine = cubit.state.viewport.toScreen(const Offset(860, 330));
      cubit.hoverAt(onLine);
      expect(cubit.state, isA<CanvasLinkHovered>());
      cubit.clearHover();
      expect(cubit.state, isA<CanvasIdle>());
      cubit.beginPan(onLine);
      cubit.hoverAt(onLine);
      expect(cubit.state, isA<CanvasPanning>());
      await cubit.close();
    });

    test('o botão de direção cicla ida → ida e volta → volta → ida', () async {
      final (:cubit, repository: _) = await canvasCubitFor(
        links: const [EdgeLink(a: 'a', b: 'b')],
      );
      final link = cubit.state.links.single;
      final seen = <(bool, bool)>[];
      for (var i = 0; i < 3; i++) {
        await cubit.cycleDirection(cubit.state.links.single);
        await pump();
        seen.add((
          cubit.state.links.single.aToB,
          cubit.state.links.single.bToA,
        ));
      }
      expect(seen, [(true, true), (false, true), (true, false)]);
      expect(link, cubit.state.links.single);
      await cubit.close();
    });

    test('remover a ligação e editar o limite passam pelo core', () async {
      final (:cubit, repository: _) = await canvasCubitFor(
        links: const [EdgeLink(a: 'a', b: 'b')],
      );
      await cubit.setLimit(cubit.state.links.single, null);
      await pump();
      expect(cubit.state.links.single.maxSends, isNull);
      await cubit.removeLink(cubit.state.links.single);
      await pump();
      expect(cubit.state.links, isEmpty);
      await cubit.close();
    });
  });

  test('zoom pela roda com âncora não move o ponto sob o cursor', () async {
    final (:cubit, repository: _) = await canvasCubitFor();
    cubit.resetZoom();
    const anchor = Offset(400, 300);
    final before = cubit.state.viewport.toDocument(anchor);
    cubit.wheelZoom(-40, anchor);
    expect(cubit.state.viewport.zoom, isNot(1));
    final after = cubit.state.viewport.toDocument(anchor);
    expect(after.dx, closeTo(before.dx, 0.01));
    expect(after.dy, closeTo(before.dy, 0.01));
    await cubit.close();
  });

  test('a roda comum anda a vista e cresce o documento à frente', () async {
    final (:cubit, repository: _) = await canvasCubitFor();
    cubit.resetZoom();
    final before = cubit.state.viewport;
    cubit.scroll(const Offset(0, 120));
    expect(
      cubit.state.viewport.origin.dy,
      closeTo(before.origin.dy + 120, 0.001),
    );
    expect(
      cubit.state.viewport.document.height,
      greaterThanOrEqualTo(before.origin.dy + 120 + before.visible.height),
    );
    expect(CanvasViewport.wheelChunk, 512);
    await cubit.close();
  });
}
