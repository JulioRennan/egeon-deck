import 'package:egeon_deck/core/domain/entities/workbench.dart';
import 'package:egeon_deck/features/home/domain/entities/shell_snapshot.dart';
import 'package:egeon_deck/features/home/domain/usecase/copy_dispatch_targets.dart';
import 'package:egeon_deck/features/home/domain/usecase/resolve_access_lock.dart';
import 'package:egeon_deck/features/home/domain/usecase/set_view_mode.dart';
import 'package:egeon_deck/features/home/domain/usecase/watch_shell.dart';
import 'package:egeon_deck/features/home/presentation/cubit/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_menu.dart';
import '../../support/fake_shell_repository.dart';

ShellSnapshot _on(String id) => ShellSnapshot(
  bench: Workbench(id: id, name: id, path: '~'),
);

void main() {
  late FakeShellRepository shell;

  ShellCubit make() => ShellCubit(
    watch: WatchShell(shell),
    setView: SetViewMode(shell),
    access: ResolveAccessLock(shell),
    copyTargets: CopyDispatchTargets(FakeMenuRepository(''), FakeClipboard()),
  );

  setUp(() => shell = FakeShellRepository());

  test('a gaveta sempre abre fechada: não passa do app', () async {
    final first = make();
    first.setCollapsed(false);
    expect(first.state, isA<ShellExpanded>());
    await first.close();
    final second = make();
    expect(second.state, isA<ShellCollapsed>());
    expect(second.state.drawerOpen, isFalse);
    await second.close();
  });

  test('só abre e fecha', () async {
    final cubit = make();
    cubit.setCollapsed(false);
    expect(cubit.state, isA<ShellExpanded>());
    expect(cubit.state.drawerOpen, isTrue);
    cubit.toggleCollapsed();
    expect(cubit.state, isA<ShellCollapsed>());
    cubit.toggleCollapsed();
    expect(cubit.state, isA<ShellExpanded>());
    await cubit.close();
  });

  test('a gaveta aberta continua aberta ao escolher outra bancada', () async {
    final cubit = make();
    shell.push(_on('a'));
    await Future<void>.delayed(Duration.zero);
    cubit.setCollapsed(false);
    shell.push(_on('a'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, isA<ShellExpanded>());
    shell.push(_on('b'));
    await Future<void>.delayed(Duration.zero);
    expect(cubit.state, isA<ShellExpanded>());
    expect(cubit.state.snapshot.bench?.id, 'b');
    await cubit.close();
  });

  test('o mouse abre e, ao sair, fecha só a que ele abriu', () async {
    final cubit = make();
    cubit.peek();
    expect(cubit.state, isA<ShellPeeking>());
    expect(cubit.state.drawerOpen, isTrue);
    cubit.endPeek();
    expect(cubit.state, isA<ShellCollapsed>());

    cubit.setCollapsed(false);
    cubit.peek();
    cubit.endPeek();
    expect(cubit.state, isA<ShellExpanded>(), reason: 'aberta por clique fica');
    await cubit.close();
  });

  test('clicar com ela aberta pelo mouse a deixa aberta de vez', () async {
    final cubit = make();
    cubit.peek();
    cubit.toggleCollapsed();
    expect(cubit.state, isA<ShellExpanded>());
    cubit.endPeek();
    expect(cubit.state, isA<ShellExpanded>());
    await cubit.close();
  });

  test(
    'aberta pelo mouse, continua aberta ao escolher outra bancada',
    () async {
      final cubit = make();
      shell.push(_on('a'));
      await Future<void>.delayed(Duration.zero);
      cubit.peek();
      shell.push(_on('b'));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<ShellPeeking>());
      expect(cubit.state.snapshot.bench?.id, 'b');
      await cubit.close();
    },
  );
}
