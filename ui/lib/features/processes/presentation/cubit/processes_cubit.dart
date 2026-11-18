import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/processes_view.dart';
import '../../domain/usecase/manage_processes.dart';
import 'processes_state.dart';

/// O cubit da janela Processos: varre ao abrir e a cada [every], e solta o
/// relógio no `close()`. A lista, o resumo e a ordem vêm prontos do core.
class ProcessesCubit extends Cubit<ProcessesState> {
  ProcessesCubit({
    required this._manage,
    this.every = const Duration(seconds: 3),
  }) : super(const ProcessesState()) {
    unawaited(refresh());
    _timer = Timer.periodic(every, (_) => unawaited(refresh()));
  }

  final ManageProcesses _manage;
  final Duration every;
  Timer? _timer;
  var _scanning = false;

  /// Uma varredura por vez: a anterior pode ainda estar de pé.
  Future<void> refresh() async {
    if (_scanning || isClosed) return;
    _scanning = true;
    try {
      _show(await _manage.list());
    } on Object {
      // A próxima varredura tenta de novo.
    } finally {
      _scanning = false;
    }
  }

  /// Mantém a seleção pelo pid: a lista se refaz a cada varredura, e o que
  /// você marcou continua marcado enquanto o processo existir.
  void _show(ProcessesView view) {
    if (isClosed) return;
    final alive = {for (final r in view.rows) r.pid};
    emit(
      state.copyWith(
        view: view,
        loaded: true,
        selected: state.selected.where(alive.contains).toSet(),
      ),
    );
  }

  void setFilter(ProcessFilter filter) {
    final visible = {
      for (final r
          in filter == ProcessFilter.orphans
              ? state.view.rows.where((r) => r.orphan)
              : state.view.rows)
        r.pid,
    };
    emit(
      state.copyWith(
        filter: filter,
        selected: state.selected.where(visible.contains).toSet(),
      ),
    );
  }

  /// Clique numa linha: escolhe só ela; com [additive] (⌘ ou Ctrl) liga e
  /// desliga; com [range] (⇧) vai da última escolhida até ela.
  void select(int pid, {bool additive = false, bool range = false}) {
    final rows = state.rows.map((r) => r.pid).toList();
    if (range && state.selected.isNotEmpty) {
      final anchor = rows.indexWhere(state.selected.contains);
      final to = rows.indexOf(pid);
      if (anchor >= 0 && to >= 0) {
        final from = anchor < to ? anchor : to;
        final end = anchor < to ? to : anchor;
        emit(state.copyWith(selected: rows.sublist(from, end + 1).toSet()));
        return;
      }
    }
    if (additive) {
      final next = {...state.selected};
      next.contains(pid) ? next.remove(pid) : next.add(pid);
      emit(state.copyWith(selected: next));
      return;
    }
    emit(state.copyWith(selected: {pid}));
  }

  /// A pergunta de encerrar os órfãos, como o core a escreve; nula se ele não
  /// respondeu (a janela não pergunta o que não sabe).
  Future<ProcessConfirm?> confirmReap() => _ask(_manage.confirmReap);

  /// A pergunta de encerrar os escolhidos, como o core a escreve.
  Future<ProcessConfirm?> confirmKill() =>
      _ask(() => _manage.confirmKill(state.selected.toList()));

  Future<ProcessConfirm?> _ask(Future<ProcessConfirm> Function() ask) async {
    try {
      return await ask();
    } on Object {
      return null;
    }
  }

  /// Os órfãos têm SIGTERM e a lista nova volta na resposta.
  Future<void> reapOrphans() => _run(_manage.reap);

  /// Os escolhidos têm SIGTERM.
  Future<void> killSelected() {
    final pids = state.selected.toList();
    return _run(() => _manage.kill(pids));
  }

  Future<void> _run(Future<ProcessesView> Function() action) async {
    try {
      _show(await action());
    } on Object {
      // A varredura seguinte mostra o que de fato aconteceu.
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
