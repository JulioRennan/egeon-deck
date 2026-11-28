part of 'processes_cubit.dart';

enum ProcessFilter { all, orphans }

/// A janela Processos. O filtro vale em toda fase.
sealed class ProcessesState {
  const ProcessesState({this.filter = ProcessFilter.all});

  final ProcessFilter filter;
}

/// Ainda não chegou lista nenhuma.
final class ProcessesScanning extends ProcessesState {
  const ProcessesScanning({super.filter});
}

/// A lista que o core mandou.
sealed class ProcessesLoaded extends ProcessesState {
  const ProcessesLoaded({required this.view, super.filter});

  final ProcessesView view;

  /// Os pids escolhidos na tabela.
  Set<int> get selected;

  /// As linhas da tabela, pelo filtro.
  List<ProcessRow> get rows => filter == ProcessFilter.orphans
      ? [
          for (final r in view.rows)
            if (r.orphan) r,
        ]
      : view.rows;
}

/// A lista, sem nada escolhido.
final class ProcessesListing extends ProcessesLoaded {
  const ProcessesListing({required super.view, super.filter});

  @override
  Set<int> get selected => const {};
}

/// A lista com linhas escolhidas: os botões de encerrar valem para elas.
final class ProcessesSelecting extends ProcessesLoaded {
  const ProcessesSelecting({
    required super.view,
    required this.selected,
    super.filter,
  });

  @override
  final Set<int> selected;
}
