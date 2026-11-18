import '../../domain/entities/processes_view.dart';

enum ProcessFilter { all, orphans }

class ProcessesState {
  const ProcessesState({
    this.view = const ProcessesView(),
    this.filter = ProcessFilter.all,
    this.selected = const {},
    this.loaded = false,
  });

  final ProcessesView view;
  final ProcessFilter filter;

  /// Os pids escolhidos na tabela.
  final Set<int> selected;

  /// Já chegou uma lista.
  final bool loaded;

  /// As linhas da tabela, pelo filtro.
  List<ProcessRow> get rows => filter == ProcessFilter.orphans
      ? [
          for (final r in view.rows)
            if (r.orphan) r,
        ]
      : view.rows;

  ProcessesState copyWith({
    ProcessesView? view,
    ProcessFilter? filter,
    Set<int>? selected,
    bool? loaded,
  }) => ProcessesState(
    view: view ?? this.view,
    filter: filter ?? this.filter,
    selected: selected ?? this.selected,
    loaded: loaded ?? this.loaded,
  );
}
