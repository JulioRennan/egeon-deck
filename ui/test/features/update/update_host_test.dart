import 'package:egeon_deck/features/update/domain/entities/app_effect.dart';
import 'package:egeon_deck/features/update/domain/entities/app_snapshot.dart';
import 'package:egeon_deck/features/update/presentation/cubit/update_cubit.dart';
import 'package:egeon_deck/features/update/presentation/widgets/update_host.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/eg_host.dart';
import '../../support/fake_app_repository.dart';
import '../../support/inject_fakes.dart';

const _prompt = UpdatePrompt(
  version: '1.7.0',
  title: 'Versão 1.7.0 do Egeon Deck disponível',
  text: 'novidades\n\nReiniciar encerra o que estiver rodando.',
  auto: false,
  autoLabel: 'Atualizar automaticamente',
  acceptLabel: 'Atualizar e reiniciar',
  laterLabel: 'Depois',
);

void main() {
  late FakeAppRepository repo;
  late UpdateCubit cubit;
  var processes = 0;
  var terminated = 0;

  Future<void> pumpHost(WidgetTester tester) async {
    repo = FakeAppRepository();
    processes = 0;
    terminated = 0;
    tester.view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    injectFakes(app: repo);
    await tester.pumpWidget(
      egHost(
        UpdateHost(
          onShowProcesses: () => processes++,
          onTerminate: () => terminated++,
          child: Builder(
            builder: (context) {
              cubit = context.read<UpdateCubit>();
              return BlocBuilder<UpdateCubit, UpdateState>(
                builder: (context, state) => Text(
                  'menu: ${switch (state) {
                    UpdateWaiting() => '',
                    UpdateShown(:final app) => app.update.menu,
                  }}',
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('o menu mostra o que o core mandou', (tester) async {
    await pumpHost(tester);
    repo.push(
      const AppSnapshot(
        update: UpdateView(
          phase: UpdatePhase.ready,
          menu: 'Reiniciar para atualizar para a versão 1.7.0',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.text('menu: Reiniciar para atualizar para a versão 1.7.0'),
      findsOneWidget,
    );
  });

  testWidgets('os gestos do menu vão ao core', (tester) async {
    await pumpHost(tester);
    cubit.pressMenu();
    cubit.setUpdateAuto(on: true);
    cubit.setReaperEnabled(on: false);
    await tester.pump();
    expect(repo.menuPresses, 1);
    expect(repo.autos, [true]);
    expect(repo.reapers, [false]);
  });

  group('o aviso de versão nova', () {
    testWidgets('mostra título, texto e os rótulos do core', (tester) async {
      await pumpHost(tester);
      repo.effect(_prompt);
      await tester.pump();
      await tester.pump();
      expect(find.text(_prompt.title), findsOneWidget);
      expect(find.textContaining('Reiniciar encerra'), findsOneWidget);
      expect(find.text('Atualizar e reiniciar'), findsOneWidget);
      expect(find.text('Depois'), findsOneWidget);
      expect(find.text('Atualizar automaticamente'), findsOneWidget);
    });

    testWidgets('atualizar devolve a versão e a caixa como ficou', (
      tester,
    ) async {
      await pumpHost(tester);
      repo.effect(_prompt);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('update-auto')));
      await tester.pump();
      await tester.tap(find.text('Atualizar e reiniciar'));
      await tester.pump();
      await tester.pump();

      expect(repo.answers.single, (version: '1.7.0', accept: true, auto: true));
      expect(find.text(_prompt.title), findsNothing);
    });

    testWidgets('"Depois" não atualiza, e a caixa vai como ficou', (
      tester,
    ) async {
      await pumpHost(tester);
      repo.effect(_prompt);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Depois'));
      await tester.pump();
      await tester.pump();
      expect(repo.answers.single, (
        version: '1.7.0',
        accept: false,
        auto: false,
      ));
    });

    testWidgets('a caixa começa como o core mandou', (tester) async {
      await pumpHost(tester);
      repo.effect(
        const UpdatePrompt(
          version: '1.8.0',
          title: 'x',
          text: 'y',
          auto: true,
          autoLabel: 'auto',
          acceptLabel: 'Sim',
          laterLabel: 'Não',
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Sim'));
      await tester.pump();
      await tester.pump();
      expect(repo.answers.single.auto, isTrue);
    });

    testWidgets('Esc é "Depois", com a caixa do core', (tester) async {
      await pumpHost(tester);
      repo.effect(_prompt);
      await tester.pump();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      expect(repo.answers.single, (
        version: '1.7.0',
        accept: false,
        auto: false,
      ));
    });

    testWidgets('um segundo aviso não empilha sobre o aberto', (tester) async {
      await pumpHost(tester);
      repo.effect(_prompt);
      await tester.pump();
      await tester.pump();
      repo.effect(_prompt);
      await tester.pump();
      await tester.pump();
      expect(find.text(_prompt.title), findsOneWidget);
    });

    testWidgets('mão em tudo que responde a clique', (tester) async {
      await pumpHost(tester);
      repo.effect(_prompt);
      await tester.pump();
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      for (final finder in [
        find.byKey(const ValueKey('update-auto')),
        find.text('Depois'),
        find.text('Atualizar e reiniciar'),
      ]) {
        await mouse.moveTo(tester.getCenter(finder));
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          SystemMouseCursors.click,
        );
      }
    });
  });

  testWidgets('a mensagem de uma linha vira um aviso passageiro', (
    tester,
  ) async {
    await pumpHost(tester);
    repo.effect(
      const UpdateMessage(
        title: 'Você está na última versão',
        text: 'Egeon Deck 1.6.0.',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Você está na última versão'), findsOneWidget);
    expect(find.text('Egeon Deck 1.6.0.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Você está na última versão'), findsNothing);
  });

  testWidgets('encerrar e abrir Processos vão à casca', (tester) async {
    await pumpHost(tester);
    repo.effect(const Terminate());
    repo.effect(const ShowProcesses());
    await tester.pump();
    expect(terminated, 1);
    expect(processes, 1);
  });
}
