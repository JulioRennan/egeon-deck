part of 'update_cubit.dart';

/// O que o menu do app mostra: o tópico `app` como o core o manda. Antes da
/// primeira entrega, os padrões dele.
final class UpdateState {
  const UpdateState({this.app = const AppSnapshot()});

  final AppSnapshot app;
}
