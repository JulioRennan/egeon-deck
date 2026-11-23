import 'dart:async';

import 'package:egeon_deck/features/processes/domain/entities/processes_view.dart';
import 'package:egeon_deck/features/processes/domain/errors/processes_error.dart';
import 'package:egeon_deck/features/processes/domain/repository/processes_repository.dart';
import 'package:egeon_deck/features/processes/domain/usecase/manage_processes.dart';
import 'package:egeon_deck/features/processes/presentation/cubit/processes_cubit.dart';
import 'package:egeon_deck/features/processes/presentation/widgets/processes_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';
import '../../support/fake_processes_repository.dart';
import '../../support/inject_fakes.dart';
import '../../support/pump.dart';

/// A lista na tela; o teste só lê depois da primeira varredura.
ProcessesLoaded loaded(ProcessesCubit cubit) => cubit.state as ProcessesLoaded;

void main() {
  late FakeProcessesRepository repo;

  group('o cubit', () {
    Future<ProcessesCubit> make({
      Duration every = const Duration(hours: 1),
    }) async {
      repo = FakeProcessesRepository(sampleProcesses());
      final cubit = ProcessesCubit(manage: ManageProcesses(repo), every: every);
      await pump();
      return cubit;
    }

    test('varre ao abrir e mostra a lista pronta do core', () async {
      final cubit = await make();
      expect(cubit.state, isA<ProcessesLoaded>());
      expect(loaded(cubit).view.rows.map((r) => r.pid), [100, 200, 300, 400]);
      expect(loaded(cubit).view.summary, '2 no app · 2 órfãos');
      expect(loaded(cubit).view.orphans, 2, reason: 'o número vem do core');
      await cubit.close();
    });

    test('varre de novo a cada tempo, uma por vez', () async {
      final cubit = await make(every: const Duration(milliseconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(repo.lists, greaterThan(2));
      await cubit.close();
      final after = repo.lists;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(repo.lists, after, reason: 'fechou: o relógio parou');
    });

    test('o filtro de órfãos mostra só eles', () async {
      final cubit = await make();
      cubit.setFilter(ProcessFilter.orphans);
      expect(loaded(cubit).rows.map((r) => r.pid), [300, 400]);
      cubit.setFilter(ProcessFilter.all);
      expect(loaded(cubit).rows, hasLength(4));
      await cubit.close();
    });

    test('escolher passa a escolhendo; tirar tudo volta a só listar', () async {
      final cubit = await make();
      expect(cubit.state, isA<ProcessesListing>());
      cubit.select(100);
      expect(cubit.state, isA<ProcessesSelecting>());
      cubit.select(100, additive: true);
      expect(cubit.state, isA<ProcessesListing>());
      await cubit.close();
    });

    test('a seleção: um, vários com ⌘ e faixa com ⇧', () async {
      final cubit = await make();
      cubit.select(100);
      expect(loaded(cubit).selected, {100});
      cubit.select(300, additive: true);
      expect(loaded(cubit).selected, {100, 300});
      cubit.select(300, additive: true);
      expect(loaded(cubit).selected, {100});
      cubit.select(300, range: true);
      expect(loaded(cubit).selected, {100, 200, 300});
      cubit.select(400);
      expect(loaded(cubit).selected, {400});
      await cubit.close();
    });

    test('a seleção sobrevive à varredura e perde quem morreu', () async {
      final cubit = await make();
      cubit.select(200);
      cubit.select(300, additive: true);
      repo.rows = [
        for (final r in repo.rows)
          if (r.pid != 200) r,
      ];
      await cubit.refresh();
      expect(loaded(cubit).selected, {300});
      await cubit.close();
    });

    test('trocar o filtro tira da seleção o que sumiu da tabela', () async {
      final cubit = await make();
      cubit.select(100);
      cubit.select(300, additive: true);
      cubit.setFilter(ProcessFilter.orphans);
      expect(loaded(cubit).selected, {300});
      await cubit.close();
    });

    test(
      'encerrar órfãos e escolhidos usa a lista que o core devolve',
      () async {
        final cubit = await make();
        await cubit.reapOrphans();
        expect(repo.reaps, 1);
        expect(loaded(cubit).view.rows.map((r) => r.pid), [100, 200]);

        cubit.select(200);
        await cubit.killSelected();
        expect(repo.kills.single, [200]);
        expect(loaded(cubit).view.rows.map((r) => r.pid), [100]);
        expect(loaded(cubit).selected, isEmpty);
        await cubit.close();
      },
    );

    test('a pergunta de encerrar vem do core, escrita', () async {
      final cubit = await make();
      final reap = await cubit.confirmReap();
      expect(reap!.title, 'Encerrar 2 processos órfãos?');
      cubit.select(100);
      final kill = await cubit.confirmKill();
      expect(
        kill!.title,
        'Encerrar 1 processo? 1 ainda são de terminal aberto.',
      );
      await cubit.close();
    });

    test('sem resposta do core, não há pergunta', () async {
      final cubit = ProcessesCubit(
        manage: ManageProcesses(_Failing()),
        every: const Duration(hours: 1),
      );
      await pump();
      expect(await cubit.confirmReap(), isNull);
      expect(await cubit.confirmKill(), isNull);
      await cubit.close();
    });

    test('falha do core não derruba o cubit', () async {
      final failing = _Failing();
      final cubit = ProcessesCubit(
        manage: ManageProcesses(failing),
        every: const Duration(hours: 1),
      );
      await pump();
      await cubit.reapOrphans();
      expect(cubit.state, isA<ProcessesScanning>());
      await cubit.close();
    });
  });

  group('a janela', () {
    late BuildContext below;
    late List<LogicalKeyboardKey> terminalKeys;
    late int belowTaps;

    /// Por baixo, no canto: um "terminal" focado que anota as teclas e um
    /// botão que conta cliques — a janela flutua sem barreira por cima.
    Future<void> pumpPanel(WidgetTester tester) async {
      repo = FakeProcessesRepository(sampleProcesses());
      terminalKeys = [];
      belowTaps = 0;
      tester.view
        ..physicalSize = const Size(1000, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      injectFakes(processes: repo);
      await tester.pumpWidget(
        egHost(
          Align(
            alignment: Alignment.topLeft,
            child: Builder(
              builder: (context) {
                below = context;
                return Focus(
                  autofocus: true,
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent) {
                      terminalKeys.add(event.logicalKey);
                    }
                    return KeyEventResult.handled;
                  },
                  child: GestureDetector(
                    key: const ValueKey('open'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      belowTaps++;
                      showProcessesPanel(context);
                    },
                    child: const SizedBox(width: 40, height: 40),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    final title = find.text('Processos do Egeon Deck');

    testWidgets('não trava o app: o clique fora chega ao que está embaixo', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(belowTaps, 1);
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      expect(belowTaps, 2, reason: 'sem barreira por cima do app');
      expect(title, findsOneWidget, reason: 'clicar fora não fecha');
    });

    testWidgets('abrir de novo traz a mesma janela, não uma segunda', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.byKey(const ValueKey('process-100')));
      await tester.pump();
      final first = showProcessesPanel(below);
      final second = showProcessesPanel(below);
      await tester.pump();
      expect(title, findsOneWidget);
      expect(identical(first, second), isTrue);
      expect(
        tester
            .widget<Container>(
              find
                  .descendant(
                    of: find.byKey(const ValueKey('process-100')),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration,
        isA<BoxDecoration>().having((d) => d.color, 'cor', isNotNull),
        reason: 'o estado (a seleção) segue o mesmo',
      );
      var closed = false;
      unawaited(first.then((_) => closed = true));
      await tester.tap(find.byKey(const ValueKey('processes-close')));
      await tester.pump();
      expect(closed, isTrue);
      expect(title, findsNothing);
    });

    testWidgets('o foco vem para ela: o Esc fecha e não chega ao terminal', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(title, findsNothing);
      expect(terminalKeys, isEmpty, reason: 'o terminal de trás não ouviu');
    });

    testWidgets('com a confirmação aberta, o Esc fecha só a confirmação', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Encerrar órfãos'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Encerrar 2 processos órfãos?'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Encerrar 2 processos órfãos?'), findsNothing);
      expect(title, findsOneWidget);
    });

    testWidgets('arrasta pelo título, redimensiona pelo canto e reabre ali', (
      tester,
    ) async {
      await pumpPanel(tester);
      final start = tester.getTopLeft(title);
      await tester.drag(
        find.byKey(const ValueKey('processes-title')),
        const Offset(-30, -40),
      );
      await tester.pump();
      final moved = tester.getTopLeft(title);
      expect(moved.dx, lessThan(start.dx));
      expect(moved.dy, lessThan(start.dy));

      final grip = find.byKey(const ValueKey('processes-resize'));
      final before = tester.getBottomRight(grip);
      await tester.drag(grip, const Offset(-60, -100));
      await tester.pump();
      expect(tester.getBottomRight(grip).dx, lessThan(before.dx));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      unawaited(showProcessesPanel(below));
      await tester.pump();
      expect(tester.getTopLeft(title), moved);
    });

    testWidgets('mostra a tabela, o resumo do core e a etiqueta de órfão', (
      tester,
    ) async {
      await pumpPanel(tester);
      expect(find.text('Processos do Egeon Deck'), findsOneWidget);
      expect(find.byKey(const ValueKey('processes-summary')), findsOneWidget);
      expect(find.text('2 no app · 2 órfãos'), findsOneWidget);
      for (final pid in [100, 200, 300, 400]) {
        expect(find.byKey(ValueKey('process-$pid')), findsOneWidget);
      }
      expect(find.text('claude --resume'), findsOneWidget);
      expect(find.text('—'), findsOneWidget, reason: 'sem nó é o app');
      expect(find.text('órfão'), findsNWidgets(2));
    });

    testWidgets('o filtro de órfãos esconde os do app', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Órfãos'));
      await tester.pump();
      expect(find.byKey(const ValueKey('process-100')), findsNothing);
      expect(find.byKey(const ValueKey('process-300')), findsOneWidget);
    });

    testWidgets('encerrar órfãos pede confirmação com o texto do Swift', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Encerrar órfãos'));
      await tester.pump();
      expect(find.text('Encerrar 2 processos órfãos?'), findsOneWidget);
      expect(
        find.text('Recebem SIGTERM — o mesmo que fechar o terminal deles.'),
        findsOneWidget,
      );
      expect(repo.reaps, 0, reason: 'ainda não confirmou');
      await tester.tap(find.text('Encerrar'));
      await tester.pump();
      await tester.pump();
      expect(repo.reaps, 1);
      expect(find.byKey(const ValueKey('process-300')), findsNothing);
    });

    testWidgets('cancelar não encerra nada', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Encerrar órfãos'));
      await tester.pump();
      await tester.tap(find.text('Cancelar'));
      await tester.pump();
      expect(repo.reaps, 0);
    });

    testWidgets(
      'encerrar selecionados avisa de quantos ainda são de terminal aberto',
      (tester) async {
        await pumpPanel(tester);
        // Um do app, um órfão: um deles ainda é de terminal aberto.
        await tester.tap(find.byKey(const ValueKey('process-100')));
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.tap(find.byKey(const ValueKey('process-300')));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();

        await tester.tap(find.text('Encerrar selecionados'));
        await tester.pump();
        expect(
          find.text('Encerrar 2 processos? 1 ainda são de terminal aberto.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Encerrar'));
        await tester.pump();
        await tester.pump();
        expect(repo.kills.single.toSet(), {100, 300});
      },
    );

    testWidgets('sem seleção e sem órfãos, os botões ficam desligados', (
      tester,
    ) async {
      await pumpPanel(tester);
      await tester.tap(find.text('Encerrar selecionados'));
      await tester.pump();
      expect(find.textContaining('Encerrar 0'), findsNothing);

      repo.rows = [
        for (final r in repo.rows)
          if (!r.orphan) r,
      ];
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await tester.tap(find.text('Encerrar órfãos'));
      await tester.pump();
      expect(find.textContaining('órfãos?'), findsNothing);
    });

    testWidgets('a lista se atualiza sozinha a cada 3 s', (tester) async {
      await pumpPanel(tester);
      final before = repo.lists;
      repo.rows = [
        ...repo.rows,
        const ProcessRow(pid: 500, age: '1 s', command: 'novo'),
      ];
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump();
      expect(repo.lists, greaterThan(before));
      expect(find.byKey(const ValueKey('process-500')), findsOneWidget);
    });

    testWidgets('Esc e o X fecham, e o relógio para', (tester) async {
      await pumpPanel(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.text('Processos do Egeon Deck'), findsNothing);
      final lists = repo.lists;
      await tester.pump(const Duration(seconds: 7));
      expect(repo.lists, lists, reason: 'janela fechada não varre');
    });

    testWidgets('mão em tudo que responde a clique', (tester) async {
      await pumpPanel(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final target in [
        find.text('Todos'),
        find.text('Órfãos'),
        find.byKey(const ValueKey('process-100')),
        find.byKey(const ValueKey('processes-close')),
      ]) {
        await mouse.moveTo(tester.getCenter(target));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
          reason: '$target',
        );
      }
    });
  });
}

class _Failing implements ProcessesRepository {
  @override
  Future<ProcessesView> list() => Future.error(const ProcessesOffline());

  @override
  Future<ProcessesView> reap() => Future.error(const ProcessesOffline());

  @override
  Future<ProcessConfirm> confirmReap() =>
      Future.error(const ProcessesOffline());

  @override
  Future<ProcessConfirm> confirmKill(List<int> pids) =>
      Future.error(const ProcessesOffline());

  @override
  Future<ProcessesView> kill(List<int> pids) =>
      Future.error(const ProcessesOffline());
}
