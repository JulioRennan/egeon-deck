import 'dart:ui';

import '../../../../commons/utils/agent_identity.dart';
import '../../../../commons/widgets/eg/identity.dart';
import '../../../../theme/egeon_colors.dart';
import '../../domain/entities/chat_block.dart';

/// A cor de quem fala na conversa: a identidade do agente (`agentIdentity`, a
/// mesma do card no canvas).
abstract final class ChatPalette {
  static Identity identityOf(ChatWho who) => agentIdentity(who.id);

  static Identity identityOfId(String id) => agentIdentity(id);

  static Color of(EgeonColors c, ChatWho who) => identityOf(who).color(c);

  static Color ofId(EgeonColors c, String id) => identityOfId(id).color(c);
}
