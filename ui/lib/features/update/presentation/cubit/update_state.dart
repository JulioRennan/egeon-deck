part of 'update_cubit.dart';

/// O menu do app: esperando o tópico `app`, ou com o que o core mandou.
sealed class UpdateState {
  const UpdateState();
}

/// Antes da primeira entrega: o menu com os padrões dele.
final class UpdateWaiting extends UpdateState {
  const UpdateWaiting();
}

final class UpdateShown extends UpdateState {
  const UpdateShown(this.app);

  final AppSnapshot app;
}
