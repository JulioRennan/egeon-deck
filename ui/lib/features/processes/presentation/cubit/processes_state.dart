part of 'processes_cubit.dart';

enum ProcessFilter { all, orphans }

/// A janela Processos: varrendo pela primeira vez, ou com a lista do core. O
/// filtro vale nas duas fases.
sealed class ProcessesState {
  const ProcessesState({this.filter = ProcessFilter.all});

  final ProcessFilter filter;
}

/// Ainda não chegou lista nenhuma.
final class ProcessesScanning extends ProcessesState {
  const ProcessesScanning({super.filter});
}

/// A lista que o core mandou, com o que a pessoa escolheu nela.
final class ProcessesLoaded extends ProcessesState {
  const ProcessesLoaded({
    required this.view,
    super.filter,
    this.selected = const {},
  });

  final ProcessesView view;

  /// Os pids escolhidos na tabela.
  final Set<int> selected;

  /// As linhas da tabela, pelo filtro.
  List<ProcessRow> get rows => filter == ProcessFilter.orphans
      ? [
          for (final r in view.rows)
            if (r.orphan) r,
        ]
      : view.rows;

  ProcessesLoaded copyWith({
    ProcessesView? view,
    ProcessFilter? filter,
    Set<int>? selected,
  }) => ProcessesLoaded(
    view: view ?? this.view,
    filter: filter ?? this.filter,
    selected: selected ?? this.selected,
  );
}
