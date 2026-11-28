import '../../../../commons/widgets/eg/diff_view.dart';

/// O diff unificado que o core manda (linhas `@@ -a,b +c,d @@`, `+`, `-` e
/// contexto) como as linhas lado a lado do `DiffView`: remoções à esquerda,
/// adições à direita, pareadas em ordem; contexto nos dois lados.
({List<DiffRow> rows, int added, int removed}) diffRowsOf(List<String> lines) {
  final rows = <DiffRow>[];
  final hunk = RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@');
  var oldN = 1;
  var newN = 1;
  var added = 0;
  var removed = 0;
  final dels = <DiffCell>[];
  final adds = <DiffCell>[];

  void flush() {
    final n = dels.length > adds.length ? dels.length : adds.length;
    for (var i = 0; i < n; i++) {
      rows.add(
        DiffRow(
          left: i < dels.length ? dels[i] : null,
          right: i < adds.length ? adds[i] : null,
        ),
      );
    }
    dels.clear();
    adds.clear();
  }

  for (final line in lines) {
    // Cabeçalhos do git e o aviso de fim de arquivo não são linhas do arquivo:
    // não andam os contadores.
    if (line.startsWith(r'\') ||
        line.startsWith('diff --git') ||
        line.startsWith('index ') ||
        line.startsWith('new file mode') ||
        line.startsWith('deleted file mode') ||
        line.startsWith('similarity index') ||
        line.startsWith('rename ')) {
      continue;
    }
    final m = hunk.firstMatch(line);
    if (m != null) {
      flush();
      oldN = int.parse(m.group(1)!);
      newN = int.parse(m.group(2)!);
      rows.add(DiffRow.fold(line));
    } else if (line.startsWith('+') && !line.startsWith('+++')) {
      adds.add(DiffCell(newN++, line.substring(1), sign: DiffSign.added));
      added++;
    } else if (line.startsWith('-') && !line.startsWith('---')) {
      dels.add(DiffCell(oldN++, line.substring(1), sign: DiffSign.removed));
      removed++;
    } else if (line.startsWith('+++') || line.startsWith('---')) {
      continue;
    } else {
      flush();
      final text = line.startsWith(' ') ? line.substring(1) : line;
      rows.add(
        DiffRow(left: DiffCell(oldN++, text), right: DiffCell(newN++, text)),
      );
    }
  }
  flush();
  return (rows: rows, added: added, removed: removed);
}
