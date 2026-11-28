/// O que salvar o canvas como template vai gravar, para o diálogo: a linha de
/// resumo do core, quantos nós (zero é "Canvas vazio"), o nome resolvido (o de
/// origem, quando se atualiza) e se ele já existe.
class TemplatePlan {
  const TemplatePlan({
    required this.summary,
    this.nodes = 0,
    this.template,
    this.exists = false,
  });

  factory TemplatePlan.fromMap(Map<String, Object?> map) => TemplatePlan(
    summary: map['summary'] as String? ?? '',
    nodes: (map['nodes'] as num?)?.toInt() ?? 0,
    template: map['template'] as String?,
    exists: map['exists'] as bool? ?? false,
  );

  final String summary;
  final int nodes;
  final String? template;
  final bool exists;

  bool get empty => nodes == 0;
}
