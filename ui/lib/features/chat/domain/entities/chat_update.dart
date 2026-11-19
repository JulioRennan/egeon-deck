import '../../../../commons/utils/wire.dart';
import 'chat_block.dart';
import 'chat_participant.dart';
import 'chat_queue.dart';
import 'permission_request.dart';

/// Uma operação sobre a lista de linhas, como o core manda.
sealed class BlockOp {
  const BlockOp();

  factory BlockOp.fromMap(Map<String, Object?> map) => switch (map['op']) {
    'reset' => ResetOp(mapList(map['blocks'], ChatBlock.fromMap)),
    'participants' => ParticipantsOp(
      mapList(map['list'], ChatParticipantInfo.fromMap),
    ),
    'queues' => QueuesOp(mapList(map['list'], ChatQueueInfo.fromMap)),
    'permissions' => PermissionsOp(
      mapList(map['list'], PermissionRequest.fromMap),
    ),
    'remove' => RemoveOp(map['id']! as String),
    'insert' => InsertOp(
      map['index']! as int,
      ChatBlock.fromMap(map['block']! as Map<String, Object?>),
    ),
    'update' => UpdateOp(
      ChatBlock.fromMap(map['block']! as Map<String, Object?>),
    ),
    // Op que esta versão não conhece: a lista de linhas segue valendo.
    _ => const UnknownOp(),
  };
}

/// A barra de quem está na conversa, inteira.
class ParticipantsOp extends BlockOp {
  const ParticipantsOp(this.list);

  final List<ChatParticipantInfo> list;
}

/// As filas da bancada, inteiras.
class QueuesOp extends BlockOp {
  const QueuesOp(this.list);

  final List<ChatQueueInfo> list;
}

/// Os pedidos de permissão em aberto, empilhados; vazia, a bandeja some.
class PermissionsOp extends BlockOp {
  const PermissionsOp(this.list);

  final List<PermissionRequest> list;
}

/// Uma op que a UI não conhece; aplicá-la não muda nada.
class UnknownOp extends BlockOp {
  const UnknownOp();
}

class ResetOp extends BlockOp {
  const ResetOp(this.blocks);

  final List<ChatBlock> blocks;
}

class RemoveOp extends BlockOp {
  const RemoveOp(this.id);

  final String id;
}

class InsertOp extends BlockOp {
  const InsertOp(this.index, this.block);

  final int index;
  final ChatBlock block;
}

class UpdateOp extends BlockOp {
  const UpdateOp(this.block);

  final ChatBlock block;
}

/// Uma linha do canal `/ui` do chat: a revisão e o que mudou.
class ChatUpdate {
  const ChatUpdate({
    required this.workbench,
    required this.rev,
    required this.ops,
  });

  final String workbench;

  /// Sobe um por evento; quem perde um pede o instantâneo.
  final int rev;
  final List<BlockOp> ops;

  factory ChatUpdate.fromMap(Map<String, Object?> map) => ChatUpdate(
    workbench: map['workbench']! as String,
    rev: map['rev']! as int,
    ops: mapList(map['ops'], BlockOp.fromMap),
  );
}

/// Aplica as operações a uma lista de linhas: `reset` troca tudo; `remove` por
/// id; `insert` no índice da lista FINAL (em ordem crescente, depois dos
/// `remove`); `update` troca a linha de mesmo id. É o que o core faz no teste
/// dele, do outro lado do canal.
List<ChatBlock> applyOps(List<ChatBlock> blocks, List<BlockOp> ops) {
  var out = [...blocks];
  for (final op in ops) {
    switch (op) {
      case ResetOp(:final blocks):
        out = [...blocks];
      case RemoveOp(:final id):
        out.removeWhere((b) => b.id == id);
      case InsertOp(:final index, :final block):
        out.insert(index.clamp(0, out.length), block);
      case UpdateOp(:final block):
        final at = out.indexWhere((b) => b.id == block.id);
        if (at >= 0) out[at] = block;
      case UnknownOp() || ParticipantsOp() || QueuesOp() || PermissionsOp():
        break;
    }
  }
  return out;
}
