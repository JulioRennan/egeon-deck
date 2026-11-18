import '../../domain/entities/chat_block.dart';
import '../../domain/entities/chat_participant.dart';
import '../../domain/entities/chat_queue.dart';
import '../../domain/entities/permission_request.dart';

class ChatState {
  const ChatState({
    this.blocks = const [],
    this.participants = const [],
    this.permission,
    this.loaded = false,
    this.sends = 0,
    this.quote,
    this.focus,
    this.queues = const [],
    this.shownQueue,
    this.notice,
  });

  final List<ChatBlock> blocks;
  final List<ChatParticipantInfo> participants;

  /// O pedido de permissão em aberto, se houver.
  final PermissionRequest? permission;

  /// Já chegou a primeira entrega do core.
  final bool loaded;

  /// Quantas mensagens o usuário mandou: a thread desce até o fim a cada uma,
  /// mesmo vindo de um ponto acima dele.
  final int sends;

  /// A linha que o composer está citando, se houver.
  final ChatBlock? quote;

  /// O participante em foco: é para ele que o composer manda.
  final String? focus;

  /// As filas da bancada, como o core as manda.
  final List<ChatQueueInfo> queues;

  /// A fila aberta no painel ao lado da conversa, se houver. Estado de tela: só
  /// vale enquanto a fila continua na lista.
  final String? shownQueue;

  /// Um aviso de uma linha (a recusa do core ao criar uma fila); some sozinho.
  final String? notice;

  /// A fila aberta, ou nula se ela saiu da bancada.
  ChatQueueInfo? get openQueue {
    for (final queue in queues) {
      if (queue.id == shownQueue) return queue;
    }
    return null;
  }

  List<ChatParticipantInfo> get agents => [
    for (final p in participants)
      if (p.isAgent) p,
  ];

  /// O destino do composer: o que está em foco, se ainda está na conversa; senão
  /// o primeiro agente.
  ChatParticipantInfo? get target {
    for (final p in participants) {
      if (p.id == focus) return p;
    }
    final all = agents;
    return all.isEmpty ? null : all.first;
  }

  ChatState copyWith({
    List<ChatBlock>? blocks,
    List<ChatParticipantInfo>? participants,
    PermissionRequest? permission,
    bool clearPermission = false,
    bool? loaded,
    int? sends,
    ChatBlock? quote,
    bool clearQuote = false,
    String? focus,
    List<ChatQueueInfo>? queues,
    String? shownQueue,
    bool clearShownQueue = false,
    String? notice,
    bool clearNotice = false,
  }) => ChatState(
    blocks: blocks ?? this.blocks,
    participants: participants ?? this.participants,
    permission: clearPermission ? null : (permission ?? this.permission),
    loaded: loaded ?? this.loaded,
    sends: sends ?? this.sends,
    quote: clearQuote ? null : (quote ?? this.quote),
    focus: focus ?? this.focus,
    queues: queues ?? this.queues,
    shownQueue: clearShownQueue ? null : (shownQueue ?? this.shownQueue),
    notice: clearNotice ? null : (notice ?? this.notice),
  );
}
