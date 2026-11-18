import 'package:flutter/foundation.dart';

/// A largura que a pessoa escolheu para o painel da fila no chat. É uma só para
/// todas as bancadas (como no Swift), por isso mora acima do chat de cada uma;
/// `null` é a largura padrão. Guarda o notificador em vez de ser um: o
/// `RepositoryProvider` recusa entregar um `Listenable`.
class QueuePanelWidth {
  QueuePanelWidth([double? value]) : notifier = ValueNotifier(value);

  final ValueNotifier<double?> notifier;

  void dispose() => notifier.dispose();
}
