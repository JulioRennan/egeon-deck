import 'package:egeon_deck/features/tabs/domain/entities/workbench_tab.dart';
import 'package:egeon_deck/features/tabs/domain/repository/tabs_repository.dart';
import 'package:egeon_deck/features/tabs/presentation/page/tabs_page.dart';
import 'package:egeon_deck/features/tabs/presentation/widgets/workbench_tabs_bar.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_tabs_repository.dart';

WorkbenchTab tab(String id, {bool active = false}) =>
    WorkbenchTab(id: id, name: id, isActive: active);

Widget host(FakeTabsRepository repository) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepositoryProvider<TabsRepository>.value(
    value: repository,
    child: Builder(
      builder: (context) => BlocProvider(
        create: (_) => createTabsCubit(context.read<TabsRepository>()),
        child: const Align(alignment: Alignment.topLeft, child: TabsPage()),
      ),
    ),
  ),
);

void main() {
  testWidgets('com menos de duas abas a faixa some; com duas, aparece', (
    tester,
  ) async {
    final repository = FakeTabsRepository();
    await tester.pumpWidget(host(repository));
    expect(find.byType(WorkbenchTabsBar), findsNothing);

    repository.push([tab('a', active: true)]);
    await tester.pump();
    await tester.pump();
    expect(
      find.byType(WorkbenchTabsBar),
      findsNothing,
      reason: 'uma só não vira faixa',
    );

    repository.push([tab('a', active: true), tab('b')]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(WorkbenchTabsBar), findsOneWidget);

    repository.push([]);
    await tester.pump();
    await tester.pump();
    expect(find.byType(WorkbenchTabsBar), findsNothing);
  });

  testWidgets('os gestos viram comandos do repository', (tester) async {
    final repository = FakeTabsRepository();
    await tester.pumpWidget(host(repository));
    repository.push([tab('a', active: true), tab('b')]);
    await tester.pump();
    await tester.pump();

    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('tab-b'))) -
          const Offset(20, 0),
    );
    await tester.tap(find.text('✕'));
    await tester.pump();

    expect(repository.picked, ['b']);
    expect(repository.closed, ['a']);
  });

  testWidgets('o cubit assina ao nascer e cancela ao sair da tela', (
    tester,
  ) async {
    final repository = FakeTabsRepository();
    await tester.pumpWidget(host(repository));
    expect(repository.watchers, 1);

    await tester.pumpWidget(const SizedBox());
    expect(repository.watchers, 0);
  });
}
