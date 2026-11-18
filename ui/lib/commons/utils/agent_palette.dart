import 'dart:convert';
import 'dart:ui';

/// Cada agente tem uma cor própria, estável entre arranques — é ela que liga a
/// linha do participante, o chip do composer, a bolha na thread e a barra de
/// consumo.
abstract final class AgentPalette {
  /// Hex fixo, não cor dinâmica: a cor do sistema muda com o tema e quebraria o
  /// "reconheço o agente pela cor de longe".
  static const colors = <Color>[
    Color(0xFFC887FA), // roxo
    Color(0xFF41C3F2), // azul
    Color(0xFFF0648C), // rosa
    Color(0xFF67D8E8), // ciano
    Color(0xFFD7B45A), // amarelo
    Color(0xFF43D17C), // verde
  ];

  /// O terminal comum, sem agente.
  static const shell = Color(0xFF9AA7BB);

  /// FNV-1a de 64 bits sobre o id, e não `hashCode`: o hash do Dart muda de
  /// execução para execução, e a cor do agente não pode trocar entre um
  /// arranque e outro.
  static Color of(String id) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    for (final byte in utf8.encode(id)) {
      hash = ((hash ^ BigInt.from(byte)) * prime).toUnsigned(64);
    }
    return colors[(hash % BigInt.from(colors.length)).toInt()];
  }
}
