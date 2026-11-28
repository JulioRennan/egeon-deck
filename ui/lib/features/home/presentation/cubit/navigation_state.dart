part of 'navigation_cubit.dart';

/// Por onde o usuário passou entre as bancadas: [back] do mais antigo ao mais
/// recente, [forward] do mais distante ao mais próximo.
sealed class NavigationState {
  const NavigationState({this.back = const [], this.forward = const []});

  final List<String> back;
  final List<String> forward;

  bool get canGoBack => back.isNotEmpty;
  bool get canGoForward => forward.isNotEmpty;
}

/// Ainda não houve troca de bancada: nada a voltar nem a avançar.
final class NavigationFresh extends NavigationState {
  const NavigationFresh();
}

/// Há por onde voltar, avançar ou os dois.
final class NavigationVisited extends NavigationState {
  const NavigationVisited({required super.back, required super.forward});
}
