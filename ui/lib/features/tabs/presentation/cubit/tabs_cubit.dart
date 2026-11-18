import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/workbench_tab.dart';
import '../../domain/usecase/close_tab.dart';
import '../../domain/usecase/pick_tab.dart';
import '../../domain/usecase/reorder_tabs.dart';
import '../../domain/usecase/watch_tabs.dart';
import 'tabs_state.dart';

/// Dono da assinatura das abas: abre ao nascer e cancela no `close()`. Cada
/// evento do core traz a lista inteira.
class TabsCubit extends Cubit<TabsState> {
  TabsCubit({
    required WatchTabs watch,
    required this._pick,
    required this._close,
    required this._reorder,
  }) : super(const TabsState()) {
    _subscription = watch().listen(_onTabs);
  }

  final PickTab _pick;
  final CloseTab _close;
  final ReorderTabs _reorder;
  StreamSubscription<List<WorkbenchTab>>? _subscription;

  void _onTabs(List<WorkbenchTab> tabs) => emit(TabsState(tabs: tabs));

  void select(String id) => _fire(_pick(id));

  void closeTab(String id) => _fire(_close(id));

  void reorder(List<String> ids) => _fire(_reorder(ids));

  /// A aba ativa e a posição dela; `-1` sem nenhuma.
  int get _active => state.tabs.indexWhere((t) => t.isActive);

  /// ⌘→ / ⌘]: a aba da direita, e da última volta à primeira.
  void next() => _step(1);

  /// ⌘← / ⌘[: a da esquerda, e da primeira volta à última.
  void previous() => _step(-1);

  void _step(int by) {
    final tabs = state.tabs;
    if (tabs.length < 2) return;
    final at = _active < 0 ? 0 : _active;
    select(tabs[(at + by) % tabs.length].id);
  }

  /// ⌘1…⌘9: a aba de número [n] (a primeira é 1); número sem aba não faz nada.
  void selectNumber(int n) {
    if (n >= 1 && n <= state.tabs.length) select(state.tabs[n - 1].id);
  }

  /// ⌘W: fecha a aba da frente. A bancada continua rodando e volta pela barra.
  void closeActive() {
    final at = _active;
    if (at >= 0) closeTab(state.tabs[at].id);
  }

  /// Gesto é "mande e siga": o que vale é o estado que o core devolve.
  void _fire(Future<void> future) => unawaited(future.catchError((_) {}));

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
