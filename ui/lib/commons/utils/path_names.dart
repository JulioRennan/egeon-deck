/// Caminho do Windows: de unidade (`C:\…`) ou de rede (`\\servidor\…`). Só
/// nele a `\` separa; no Unix ela é parte válida do nome de uma pasta.
bool isWindowsPath(String path) =>
    path.startsWith(r'\\') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

/// O caminho partido nos separadores, com os vazios (`/a` dá `['', 'a']`). O
/// Windows escreve com `\` e aceita `/`; o core devolve o que o sistema deu.
List<String> splitPath(String path) =>
    path.split(isWindowsPath(path) ? RegExp(r'[\\/]') : '/');

/// Os componentes de um caminho, sem vazios.
List<String> pathComponents(String path) => [
  for (final part in splitPath(path))
    if (part.isNotEmpty) part,
];

/// O último componente: o nome da pasta ou do arquivo; vazio na raiz.
String lastPathComponent(String path) {
  final parts = pathComponents(path);
  return parts.isEmpty ? '' : parts.last;
}

/// Caminho do disco: com `~`, absoluto (`/…`) ou do Windows. Endereço web e
/// texto solto não são.
bool looksLikePath(String text) =>
    text.startsWith('~') || text.startsWith('/') || isWindowsPath(text);
