/// Um template de bancada (`templates.json`): o que o seletor do formulário
/// oferece. Só o nome vai ao `create_workbench`; o resto é o que o core diz dele.
class BenchTemplate {
  const BenchTemplate({
    required this.name,
    this.nodes = 0,
    this.basePath,
    this.view,
  });

  factory BenchTemplate.fromMap(Map<String, Object?> map) => BenchTemplate(
    name: map['name']! as String,
    nodes: (map['nodes'] as num?)?.toInt() ?? 0,
    basePath: map['base_path'] as String?,
    view: map['view'] as String?,
  );

  final String name;
  final int nodes;

  /// A pasta do projeto que o molde usava; valor inicial ao criar.
  final String? basePath;
  final String? view;
}
