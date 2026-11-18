import 'package:flutter/painting.dart';

import '../../domain/entities/chat_block.dart';

/// As cores do chat: a bolha de quem escreve (você) e a dos agentes.
abstract final class ChatPalette {
  static const youFill = Color(0xFF1C3D75);
  static const youBorder = Color(0xB33D70BF);
  static const agentFill = Color(0xEB131826);
  static const link = Color(0xFF73ADFF);
  static const boxFill = Color(0x08FFFFFF);
  static const boxBorder = Color(0x14FFFFFF);
  static const titleFill = Color(0x0DFFFFFF);
  static const titleHover = Color(0x1AFFFFFF);
  static const contentFill = Color(0x33000000);

  /// As cores que um agente pode ter, e que a conversa reconhece de longe.
  static const _participants = [
    Color(0xFF4A8FFF),
    Color(0xFF9E6BFF),
    Color(0xFFFF73B3),
    Color(0xFF40D1F2),
    Color(0xFF666BF2),
    Color(0xFFEDCC73),
    Color(0xFFE04DE6),
  ];

  /// Estável: o mesmo id é sempre da mesma cor, em qualquer sessão.
  static Color of(ChatWho who) {
    var hash = 0;
    for (final unit in who.id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _participants[hash % _participants.length];
  }
}
