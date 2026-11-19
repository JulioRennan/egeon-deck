part of 'queue_notice_cubit.dart';

/// A linha de aviso da fila.
sealed class QueueNoticeState {
  const QueueNoticeState();
}

/// Nada a dizer.
final class QueueQuiet extends QueueNoticeState {
  const QueueQuiet();
}

/// Por que a fila não anda, no texto do core.
final class QueueBlocked extends QueueNoticeState {
  const QueueBlocked(this.text);

  final String text;
}

/// O último envio não foi; some sozinho.
final class QueueSendFailed extends QueueNoticeState {
  const QueueSendFailed(this.failure);

  final QueueSendFailure failure;
}
