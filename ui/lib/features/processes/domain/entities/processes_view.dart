/// Um processo do app ou órfão dele.
class ProcessRow {
  const ProcessRow({
    required this.pid,
    required this.command,
    required this.age,
    this.node,
    this.orphan = false,
  });

  final int pid;

  /// O nó do terminal a que pertence; nulo é o app.
  final String? node;
  final bool orphan;

  /// "3 min": a idade já escrita pelo core.
  final String age;
  final String command;

  factory ProcessRow.fromMap(Map<String, Object?> map) => ProcessRow(
    pid: (map['pid']! as num).toInt(),
    node: map['node'] as String?,
    orphan: map['orphan'] as bool? ?? false,
    age: map['age'] as String? ?? '',
    command: map['command'] as String? ?? '',
  );
}

/// A pergunta antes de encerrar, escrita pelo core (o texto do `NSAlert`).
class ProcessConfirm {
  const ProcessConfirm({required this.title, required this.detail});

  final String title;
  final String detail;

  factory ProcessConfirm.fromMap(Map<String, Object?> map) => ProcessConfirm(
    title: map['title'] as String? ?? '',
    detail: map['detail'] as String? ?? '',
  );
}

/// A lista da janela "Processos", como o core a manda: já ordenada, com o
/// resumo escrito e o que os botões precisam.
class ProcessesView {
  const ProcessesView({
    this.rows = const [],
    this.summary = '',
    this.orphans = 0,
    this.enabled = true,
  });

  final List<ProcessRow> rows;

  /// "3 no app · 1 órfão · limpeza a cada 60 min".
  final String summary;

  /// Quantos órfãos há: habilita o "Encerrar órfãos".
  final int orphans;

  /// A limpeza automática está ligada (o item de menu).
  final bool enabled;

  factory ProcessesView.fromMap(Map<String, Object?> map) {
    final rows = [
      for (final p in (map['processes'] as List<Object?>? ?? const []))
        ProcessRow.fromMap(p! as Map<String, Object?>),
    ];
    return ProcessesView(
      rows: rows,
      summary: map['summary'] as String? ?? '',
      orphans: (map['orphans'] as num?)?.toInt() ?? 0,
      enabled: map['enabled'] as bool? ?? true,
    );
  }
}
