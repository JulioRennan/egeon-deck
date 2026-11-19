part of 'usage_cubit.dart';

/// O consumo da bancada: esperando o core, ou com o que ele mandou.
sealed class UsageState {
  const UsageState();
}

/// Antes da primeira entrega: a pastilha vazia.
final class UsageWaiting extends UsageState {
  const UsageWaiting();
}

final class UsageShown extends UsageState {
  const UsageShown(this.view);

  final UsageView view;
}
