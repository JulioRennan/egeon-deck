/// Os componentes de um caminho, sem vazios. O Windows escreve com `\` e
/// aceita `/`, e o core devolve o que o sistema deu (`C:\a\b`, `~/a/b`).
List<String> pathComponents(String path) => [
  for (final part in path.split(RegExp(r'[\\/]')))
    if (part.isNotEmpty) part,
];

/// O último componente: o nome da pasta ou do arquivo; vazio na raiz.
String lastPathComponent(String path) {
  final parts = pathComponents(path);
  return parts.isEmpty ? '' : parts.last;
}

/// Caminho do disco: com `~`, absoluto (`/…`), de unidade (`C:\…`) ou de rede
/// (`\\servidor\…`). Endereço web e texto solto não são.
bool looksLikePath(String text) =>
    text.startsWith('~') ||
    text.startsWith('/') ||
    text.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(text);
