import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/processes_view.dart';
import '../../domain/errors/processes_error.dart';
import '../../domain/usecase/manage_processes.dart';

part 'processes_state.dart';

/// O cubit da janela Processos: varre ao abrir e a cada [every], e solta o
/// relógio no `close()`. A lista, o resumo e a ordem vêm prontos do core.
class ProcessesCubit extends Cubit<ProcessesState> {
  ProcessesCubit({
    required this._manage,
    this.every = const Duration(seconds: 3),
  }) : super(const ProcessesScanning()) {
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
    } on ProcessesError {
      // A próxima varredura tenta de novo.
    } finally {
      _scanning = false;
    }
  }

  /// O que está escolhido; nada antes da primeira lista.
  Set<int> get _selected => switch (state) {
    ProcessesScanning() => const {},
    ProcessesLoaded(:final selected) => selected,
  };

  /// A lista com [selected]: escolhendo, ou só listando quando nada sobrou.
  static ProcessesLoaded _listed(
    ProcessesView view,
    ProcessFilter filter,
    Set<int> selected,
  ) => selected.isEmpty
      ? ProcessesListing(view: view, filter: filter)
      : ProcessesSelecting(view: view, filter: filter, selected: selected);

  /// Mantém a seleção pelo pid: a lista se refaz a cada varredura, e o que
  /// você marcou continua marcado enquanto o processo existir.
  void _show(ProcessesView view) {
    if (isClosed) return;
    final alive = {for (final r in view.rows) r.pid};
    emit(_listed(view, state.filter, _selected.where(alive.contains).toSet()));
  }

  void setFilter(ProcessFilter filter) {
    switch (state) {
      case ProcessesScanning():
        emit(ProcessesScanning(filter: filter));
      case final ProcessesLoaded loaded:
        final shown = ProcessesListing(view: loaded.view, filter: filter);
        final visible = {for (final r in shown.rows) r.pid};
        emit(
          _listed(
            loaded.view,
            filter,
            loaded.selected.where(visible.contains).toSet(),
          ),
        );
    }
  }

  /// Clique numa linha: escolhe só ela; com [additive] (⌘ ou Ctrl) liga e
  /// desliga; com [range] (⇧) vai da última escolhida até ela.
  void select(int pid, {bool additive = false, bool range = false}) {
    if (state case final ProcessesLoaded loaded) {
      emit(
        _listed(
          loaded.view,
          loaded.filter,
          _picked(loaded, pid, additive, range),
        ),
      );
    }
  }

  Set<int> _picked(ProcessesLoaded loaded, int pid, bool additive, bool range) {
    final selected = loaded.selected;
    final rows = loaded.rows.map((r) => r.pid).toList();
    if (range && selected.isNotEmpty) {
      final anchor = rows.indexWhere(selected.contains);
      final to = rows.indexOf(pid);
      if (anchor >= 0 && to >= 0) {
        final from = anchor < to ? anchor : to;
        final end = anchor < to ? to : anchor;
        return rows.sublist(from, end + 1).toSet();
      }
    }
    if (additive) {
      final next = {...selected};
      next.contains(pid) ? next.remove(pid) : next.add(pid);
      return next;
    }
    return {pid};
  }

  /// A pergunta de encerrar os órfãos, como o core a escreve; nula se ele não
  /// respondeu (a janela não pergunta o que não sabe).
  Future<ProcessConfirm?> confirmReap() => _ask(_manage.confirmReap);

  /// A pergunta de encerrar os escolhidos, como o core a escreve.
  Future<ProcessConfirm?> confirmKill() =>
      _ask(() => _manage.confirmKill(_selected.toList()));

  Future<ProcessConfirm?> _ask(Future<ProcessConfirm> Function() ask) async {
    try {
      return await ask();
    } on ProcessesError {
      return null;
    }
  }

  /// Os órfãos têm SIGTERM e a lista nova volta na resposta.
  Future<void> reapOrphans() => _run(_manage.reap);

  /// Os escolhidos têm SIGTERM.
  Future<void> killSelected() {
    final pids = _selected.toList();
    return _run(() => _manage.kill(pids));
  }

  Future<void> _run(Future<ProcessesView> Function() action) async {
    try {
      _show(await action());
    } on ProcessesError {
      // A varredura seguinte mostra o que de fato aconteceu.
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
