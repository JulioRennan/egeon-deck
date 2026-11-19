part of 'chat_queue_panel_cubit.dart';

/// As filas da bancada, como o core as manda, e se uma está aberta.
sealed class ChatQueuePanelState {
  const ChatQueuePanelState([this.queues = const []]);

  final List<ChatQueueInfo> queues;
}

/// Nenhuma fila aberta ao lado da conversa.
final class QueuePanelClosed extends ChatQueuePanelState {
  const QueuePanelClosed([super.queues]);
}

/// A fila [queue] aberta no painel ao lado da conversa.
final class QueuePanelOpen extends ChatQueuePanelState {
  const QueuePanelOpen(super.queues, this.queue);

  final ChatQueueInfo queue;
}
