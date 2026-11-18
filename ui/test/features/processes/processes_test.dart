import 'package:egeon_deck/features/processes/domain/entities/processes_view.dart';
import 'package:egeon_deck/features/processes/domain/repository/processes_repository.dart';
import 'package:egeon_deck/features/processes/domain/usecase/manage_processes.dart';
import 'package:egeon_deck/features/processes/presentation/cubit/processes_cubit.dart';
import 'package:egeon_deck/features/processes/presentation/cubit/processes_state.dart';
import 'package:egeon_deck/features/processes/presentation/widgets/processes_panel.dart';
import 'package:egeon_deck/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_processes_repository.dart';
import '../../support/pump.dart';

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
      expect(cubit.state.loaded, isTrue);
      expect(cubit.state.view.rows.map((r) => r.pid), [100, 200, 300, 400]);
      expect(cubit.state.view.summary, '2 no app · 2 órfãos');
      expect(cubit.state.view.orphans, 2, reason: 'o número vem do core');
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
      expect(cubit.state.rows.map((r) => r.pid), [300, 400]);
      cubit.setFilter(ProcessFilter.all);
      expect(cubit.state.rows, hasLength(4));
      await cubit.close();
    });

    test('a seleção: um, vários com ⌘ e faixa com ⇧', () async {
      final cubit = await make();
      cubit.select(100);
      expect(cubit.state.selected, {100});
      cubit.select(300, additive: true);
      expect(cubit.state.selected, {100, 300});
      cubit.select(300, additive: true);
      expect(cubit.state.selected, {100});
      cubit.select(300, range: true);
      expect(cubit.state.selected, {100, 200, 300});
      cubit.select(400);
      expect(cubit.state.selected, {400});
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
      expect(cubit.state.selected, {300});
      await cubit.close();
    });

    test('trocar o filtro tira da seleção o que sumiu da tabela', () async {
      final cubit = await make();
      cubit.select(100);
      cubit.select(300, additive: true);
      cubit.setFilter(ProcessFilter.orphans);
      expect(cubit.state.selected, {300});
      await cubit.close();
    });

    test(
      'encerrar órfãos e escolhidos usa a lista que o core devolve',
      () async {
        final cubit = await make();
        await cubit.reapOrphans();
        expect(repo.reaps, 1);
        expect(cubit.state.view.rows.map((r) => r.pid), [100, 200]);

        cubit.select(200);
        await cubit.killSelected();
        expect(repo.kills.single, [200]);
        expect(cubit.state.view.rows.map((r) => r.pid), [100]);
        expect(cubit.state.selected, isEmpty);
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
      expect(cubit.state.loaded, isFalse);
      await cubit.close();
    });
  });

  group('a janela', () {
    Future<void> pumpPanel(WidgetTester tester) async {
      repo = FakeProcessesRepository(sampleProcesses());
      tester.view
        ..physicalSize = const Size(1000, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var closed = 0;
      addTearDown(() => expect(closed >= 0, isTrue));
      await tester.pumpWidget(
        RepositoryProvider<ProcessesRepository>.value(
          value: repo,
          child: WidgetsApp(
            color: const Color(0xFF000000),
            textStyle: AppTheme.textStyle,
            builder: (context, _) => Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => Center(
                    child: Builder(
                      builder: (context) => GestureDetector(
                        key: const ValueKey('open'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => showProcessesPanel(context),
                        child: const SizedBox(width: 40, height: 40),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }

    testWidgets('mostra a tabela, o resumo do core e o órfão em laranja', (
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
      expect(find.text('app'), findsOneWidget, reason: 'sem nó é o app');
      expect(find.text('órfão'), findsNWidgets(2));
    });

    testWidgets('o filtro de órfãos esconde os do app', (tester) async {
      await pumpPanel(tester);
      await tester.tap(find.byKey(const ValueKey('filter-orphans')));
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
      for (final key in [
        'filter-all',
        'filter-orphans',
        'process-100',
        'processes-close',
      ]) {
        await mouse.moveTo(tester.getCenter(find.byKey(ValueKey(key))));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
          reason: key,
        );
      }
    });
  });
}

class _Failing implements ProcessesRepository {
  @override
  Future<ProcessesView> list() => Future.error(StateError('core fora'));

  @override
  Future<ProcessesView> reap() => Future.error(StateError('core fora'));

  @override
  Future<ProcessConfirm> confirmReap() => Future.error(StateError('core fora'));

  @override
  Future<ProcessConfirm> confirmKill(List<int> pids) =>
      Future.error(StateError('core fora'));

  @override
  Future<ProcessesView> kill(List<int> pids) =>
      Future.error(StateError('core fora'));
}
