import 'package:flutter/foundation.dart';

/// A largura que a pessoa escolheu para o painel da fila no chat. É uma só para
/// todas as bancadas (como no Swift), por isso é única no injector; `null` é a
/// largura padrão.
class QueuePanelWidth {
  QueuePanelWidth([double? value]) : notifier = ValueNotifier(value);

  final ValueNotifier<double?> notifier;

  void dispose() => notifier.dispose();
}
