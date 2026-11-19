/// O que salvar o workspace não conseguiu fazer, para o aviso depois: os
/// projetos que ficaram porque têm bancadas, e a imagem que não foi copiada.
class WorkspaceSaved {
  const WorkspaceSaved({this.refused = const [], this.warning});

  factory WorkspaceSaved.fromMap(Map<String, Object?> map) => WorkspaceSaved(
    refused: [
      for (final name in map['refused'] as List<Object?>? ?? const [])
        name! as String,
    ],
    warning: map['warning'] as String?,
  );

  final List<String> refused;
  final String? warning;
}
