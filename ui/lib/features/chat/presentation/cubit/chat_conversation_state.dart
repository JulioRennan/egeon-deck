part of 'chat_conversation_cubit.dart';

/// A thread como o core a manda.
sealed class ChatConversationState {
  const ChatConversationState({
    this.blocks = const [],
    this.participants = const [],
    this.permissions = const [],
  });

  final List<ChatBlock> blocks;
  final List<ChatParticipantInfo> participants;

  /// Os pedidos de permissão em aberto, empilhados na bandeja.
  final List<PermissionRequest> permissions;
}

/// Antes da primeira thread do core.
final class ChatOpening extends ChatConversationState {
  const ChatOpening();
}

/// A thread que o core mandou por último.
final class ChatShown extends ChatConversationState {
  const ChatShown({
    required super.blocks,
    required super.participants,
    required super.permissions,
  });
}
