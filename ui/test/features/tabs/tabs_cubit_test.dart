import 'package:egeon_deck/features/tabs/domain/entities/workbench_tab.dart';
import 'package:egeon_deck/features/tabs/domain/usecase/close_tab.dart';
import 'package:egeon_deck/features/tabs/domain/usecase/pick_tab.dart';
import 'package:egeon_deck/features/tabs/domain/usecase/reorder_tabs.dart';
import 'package:egeon_deck/features/tabs/domain/usecase/watch_tabs.dart';
import 'package:egeon_deck/features/tabs/presentation/cubit/tabs_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_tabs_repository.dart';

void main() {
  late FakeTabsRepository repo;
  late TabsCubit cubit;

  const a = WorkbenchTab(id: 'a', name: 'a', isActive: true);
  const b = WorkbenchTab(id: 'b', name: 'b');
  const c = WorkbenchTab(id: 'c', name: 'c');

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    repo = FakeTabsRepository();
    cubit = TabsCubit(
      watch: WatchTabs(repo),
      pick: PickTab(repo),
      close: CloseTab(repo),
      reorder: ReorderTabs(repo),
    );
  });

  tearDown(() => cubit.close());

  test('assina ao nascer e cancela ao sair', () async {
    await settle();
    expect(repo.watchers, 1);
    await cubit.close();
    expect(repo.watchers, 0);
  });

  test('a lista do core vira o estado, inteira a cada evento', () async {
    await settle();
    repo.push([a, b]);
    await settle();
    expect(cubit.state.tabs.map((t) => t.id), ['a', 'b']);
    repo.push([b]);
    await settle();
    expect(cubit.state.tabs.map((t) => t.id), ['b']);
  });

  test('escolher, fechar e reordenar viram comandos do repository', () async {
    await settle();
    cubit
      ..select('b')
      ..closeTab('c')
      ..reorder(['b', 'a']);
    await settle();
    expect(repo.picked, ['b']);
    expect(repo.closed, ['c']);
    expect(repo.reordered, [
      ['b', 'a'],
    ]);
  });

  test('⌘1…⌘9 vão à bancada n; número sem aba não faz nada', () async {
    await settle();
    repo.push([a, b, c]);
    await settle();
    cubit
      ..selectNumber(3)
      ..selectNumber(9)
      ..selectNumber(0);
    await settle();
    expect(repo.picked, ['c']);
  });

  test('⌘W fecha a da frente; ⌘] e ⌘[ dão a volta', () async {
    await settle();
    repo.push([a, b, c]);
    await settle();
    cubit
      ..closeActive()
      ..next()
      ..previous();
    await settle();
    expect(repo.closed, ['a']);
    expect(repo.picked, ['b', 'c']);
  });
}
