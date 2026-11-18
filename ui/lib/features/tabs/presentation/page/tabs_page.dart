import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repository/tabs_repository.dart';
import '../../domain/usecase/close_tab.dart';
import '../../domain/usecase/pick_tab.dart';
import '../../domain/usecase/reorder_tabs.dart';
import '../../domain/usecase/watch_tabs.dart';
import '../cubit/tabs_cubit.dart';
import '../cubit/tabs_state.dart';
import '../widgets/workbench_tabs_bar.dart';

/// O cubit das abas, para quem o hospeda (a casca): a faixa e os atalhos de
/// teclado leem do mesmo.
TabsCubit createTabsCubit(TabsRepository repository) => TabsCubit(
  watch: WatchTabs(repository),
  pick: PickTab(repository),
  close: CloseTab(repository),
  reorder: ReorderTabs(repository),
);

/// A faixa das bancadas abertas. Com uma só (ou nenhuma) ela some: a barra
/// lateral já diz qual está na tela, e a faixa comeria altura do canvas.
/// Precisa de um [TabsCubit] acima, que a casca provê.
class TabsPage extends StatelessWidget {
  const TabsPage({this.leftInset = 0, super.key});

  /// Quanto a barra lateral cobre da borda esquerda.
  final double leftInset;

  @override
  Widget build(BuildContext context) => BlocBuilder<TabsCubit, TabsState>(
    builder: (context, state) {
      if (state.tabs.length < 2) return const SizedBox.shrink();
      final cubit = context.read<TabsCubit>();
      return WorkbenchTabsBar(
        tabs: state.tabs,
        leftInset: leftInset,
        onPick: cubit.select,
        onClose: cubit.closeTab,
        onReorder: cubit.reorder,
      );
    },
  );
}
