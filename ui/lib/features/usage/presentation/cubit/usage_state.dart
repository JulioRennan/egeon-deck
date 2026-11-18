part of 'usage_cubit.dart';

/// O consumo da bancada como o core manda; antes da primeira entrega, a
/// pastilha vazia.
final class UsageState {
  const UsageState({this.view = const UsageView()});

  final UsageView view;
}
