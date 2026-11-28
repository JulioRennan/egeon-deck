import 'dart:typed_data';

/// Onde as páginas web vivas se registram para o `/shot` fotografá-las: o
/// `toImage` não pega a vista nativa, e quem a conhece é o cubit de cada nó.
/// A casca cria um só e entrega a todos os `WebBody` e ao canvas.
class WebCaptureRegistry {
  final _sources = <String, Future<Uint8List?> Function()>{};

  void register(String nodeId, Future<Uint8List?> Function() capture) =>
      _sources[nodeId] = capture;

  /// Só solta se ainda for a mesma: a página nova (troca de perfil) registra
  /// antes de a antiga sair.
  void unregister(String nodeId, Future<Uint8List?> Function() capture) {
    if (identical(_sources[nodeId], capture)) _sources.remove(nodeId);
  }

  /// A captura do nó, ou nulo se ele não é uma página viva.
  Future<Uint8List?> capture(String nodeId) async => _sources[nodeId]?.call();
}
