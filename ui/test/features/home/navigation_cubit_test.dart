import 'package:egeon_deck/core/domain/entities/workbench.dart';
import 'package:egeon_deck/features/home/domain/entities/shell_snapshot.dart';
import 'package:egeon_deck/features/home/domain/usecase/go_to_bench.dart';
import 'package:egeon_deck/features/home/domain/usecase/watch_shell.dart';
import 'package:egeon_deck/features/home/presentation/cubit/navigation_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_shell_repository.dart';

void main() {
  late FakeShellRepository repository;
  late NavigationCubit cubit;
  var open = <String>{'a', 'b', 'c', 'd'};

  setUp(() {
    repository = FakeShellRepository();
    open = {'a', 'b', 'c', 'd'};
    cubit = NavigationCubit(
      watch: WatchShell(repository),
      goTo: GoToBench(repository),
    );
  });

  tearDown(() => cubit.close());

  /// O core pondo [id] na tela; [open] diz quais abas existem nesse instante.
  Future<void> visit(String? id) async {
    repository.push(
      ShellSnapshot(
        bench: id == null ? null : Workbench(id: id, name: id, path: '~'),
        openBenchIds: {...open},
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  test('começa sem histórico, e a primeira bancada não é uma volta', () async {
    expect(cubit.state, isA<NavigationFresh>());
    await visit('a');
    expect(cubit.state, isA<NavigationFresh>());
    expect(cubit.state.canGoBack, isFalse);
    expect(cubit.state.canGoForward, isFalse);
  });

  test(
    'cada troca empilha a anterior; voltar pede a de antes ao core',
    () async {
      await visit('a');
      await visit('b');
      await visit('c');
      expect(cubit.state.back, ['a', 'b']);
      cubit.back();
      expect(repository.activated, ['b']);
      expect(cubit.state.back, ['a']);
      expect(cubit.state.forward, ['c']);
    },
  );

  test('a bancada que chega por voltar não conta como visita nova', () async {
    await visit('a');
    await visit('b');
    await visit('c');
    cubit.back();
    await visit('b');
    expect(cubit.state.back, ['a']);
    expect(cubit.state.forward, ['c'], reason: 'a pilha de avançar fica');
  });

  test('avançar refaz o caminho', () async {
    await visit('a');
    await visit('b');
    await visit('c');
    cubit.back();
    await visit('b');
    cubit.forward();
    expect(repository.activated, ['b', 'c']);
    await visit('c');
    expect(cubit.state.back, ['a', 'b']);
    expect(cubit.state.canGoForward, isFalse);
  });

  test('uma troca nova (clique) joga fora o que havia para avançar', () async {
    await visit('a');
    await visit('b');
    await visit('c');
    cubit.back();
    await visit('b');
    expect(cubit.state.canGoForward, isTrue);
    await visit('d');
    expect(cubit.state.forward, isEmpty);
    expect(cubit.state.back, ['a', 'b']);
  });

  test('fechar a aba tira a bancada do histórico, e o botão apaga', () async {
    await visit('a');
    await visit('b');
    await visit('c');
    expect(cubit.state.canGoBack, isTrue);
    open
      ..remove('a')
      ..remove('b');
    await visit('c');
    expect(cubit.state.back, isEmpty);
    expect(cubit.state.canGoBack, isFalse);
    cubit.back();
    expect(repository.activated, isEmpty);
  });

  test('uma aba fechada no meio do caminho é pulada', () async {
    await visit('a');
    await visit('b');
    await visit('c');
    open.remove('b');
    await visit('c');
    expect(cubit.state.back, ['a']);
    cubit.back();
    expect(repository.activated, ['a']);
  });

  test(
    'a mesma bancada repetida e o "nenhuma" não mexem no histórico',
    () async {
      await visit('a');
      await visit('a');
      await visit(null);
      await visit('b');
      expect(cubit.state.back, ['a']);
    },
  );

  test('o histórico guarda as últimas 50', () async {
    open = {for (var i = 0; i < 60; i++) 'b$i'};
    for (var i = 0; i < 60; i++) {
      await visit('b$i');
    }
    expect(cubit.state.back.length, 50);
    expect(cubit.state.back.last, 'b58');
    expect(cubit.state.back.first, 'b9');
  });

  test('se o core recusar a troca, o histórico fica como estava', () async {
    await visit('a');
    await visit('b');
    await visit('c');
    repository.refuseActivate = true;
    cubit.back();
    await Future<void>.delayed(Duration.zero);
    expect(repository.activated, ['b']);
    expect(cubit.state.back, ['a', 'b']);
    expect(cubit.state.forward, isEmpty);
    // A bancada seguinte que chegar é uma visita normal, não a esperada.
    await visit('d');
    expect(cubit.state.back, ['a', 'b', 'c']);
  });

  test('o cubit cancela a assinatura ao fechar', () async {
    expect(repository.watchers, 1);
    await cubit.close();
    expect(repository.watchers, 0);
  });
}
