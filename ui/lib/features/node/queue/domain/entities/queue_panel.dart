import 'dart:math' as math;

/// A largura do painel da fila ao lado da conversa (no chat).
abstract final class QueuePanel {
  static const minPanel = 300.0;
  static const minThread = 400.0;

  /// A que você arrastou ([preferred]) ou, sem isso, bastante para a lista. Nos
  /// dois casos sem espremer a thread: em janela estreita ela é quem manda, e
  /// a escolha volta quando a janela crescer.
  static double width({required double content, double? preferred}) => math.max(
    minPanel,
    math.min(preferred ?? math.max(420, content * 0.42), content - minThread),
  );
}
