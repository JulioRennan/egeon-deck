import '../../../../../core/domain/entities/workbench_node.dart';

import 'dart:ui';

/// A cor do tipo do nó: título, borda e o resto da moldura. Guardada à parte
/// porque o alerta troca a borda e precisa saber para o que voltar.
abstract final class CardAccent {
  static const shell = Color(0xFF40C8E0);
  static const agent = Color(0xFFBF5AF2);
  static const web = Color(0xFF0A84FF);
  static const queue = Color(0xFF40C8E0);

  /// O dourado do maestro: borda, título e o ✦.
  static const maestro = Color(0xFFF2C24A);

  static Color of(NodeKind kind) => switch (kind) {
    NodeKind.shell => shell,
    NodeKind.agent => agent,
    NodeKind.web => web,
    NodeKind.queue => queue,
  };
}
