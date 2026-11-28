import '../entities/ui_request.dart';

/// Os pedidos que o core faz à tela, e a resposta dela.
abstract interface class UiRequestRepository {
  Stream<UiRequest> watch();

  Future<void> reply(Object request, UiReply reply);

  /// O core pediu a janela para a frente (clique numa notificação).
  Stream<void> activations();
}
