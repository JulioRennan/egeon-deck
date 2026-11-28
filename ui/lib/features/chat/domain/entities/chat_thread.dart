import 'chat_block.dart';
import 'chat_participant.dart';
import 'chat_queue.dart';
import 'chat_update.dart';
import 'permission_request.dart';

/// A thread inteira num instante: as linhas e a revisão do core a que valem,
/// quem está na conversa e os pedidos de permissão em aberto.
class ChatThread {
  const ChatThread({
    this.rev = 0,
    this.blocks = const [],
    this.participants = const [],
    this.queues = const [],
    this.permissions = const [],
  });

  final int rev;
  final List<ChatBlock> blocks;
  final List<ChatParticipantInfo> participants;
  final List<ChatQueueInfo> queues;

  /// Os pedidos em aberto, na ordem em que o core os empilha.
  final List<PermissionRequest> permissions;

  /// Esta thread depois de [update]: as linhas pelo diff, a lista de
  /// participantes, as filas e os pedidos de permissão quando o evento os traz.
  ChatThread apply(ChatUpdate update) {
    var participants = this.participants;
    var queues = this.queues;
    var permissions = this.permissions;
    for (final op in update.ops) {
      switch (op) {
        case ParticipantsOp(:final list):
          participants = list;
        case QueuesOp(:final list):
          queues = list;
        case PermissionsOp(:final list):
          permissions = list;
        default:
          break;
      }
    }
    return ChatThread(
      rev: update.rev,
      blocks: applyOps(blocks, update.ops),
      participants: participants,
      queues: queues,
      permissions: permissions,
    );
  }
}
