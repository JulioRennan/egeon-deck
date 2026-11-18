import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/ui_request.dart';
import '../../domain/usecase/answer_ui_request.dart';
import '../../domain/usecase/reply_ui_request.dart';
import '../../domain/usecase/watch_ui_requests.dart';
import '../../domain/errors/home_error.dart';

/// Dono da assinatura dos pedidos do core: abre ao nascer, cancela no `close()`.
/// Não tem estado — cada pedido é atendido e respondido na hora.
class UiRequestCubit extends Cubit<void> {
  UiRequestCubit({
    required WatchUiRequests watch,
    required this._answer,
    required this._reply,
    required this._activate,
    required Stream<void> activations,
  }) : super(null) {
    _subscription = watch().listen(_onRequest);
    _activations = activations.listen((_) => _activate());
  }

  final AnswerUiRequest _answer;
  final ReplyUiRequest _reply;
  final Future<void> Function() _activate;
  StreamSubscription<UiRequest>? _subscription;
  StreamSubscription<void>? _activations;

  Future<void> _onRequest(UiRequest request) async {
    UiReply reply;
    try {
      reply = await _answer(request);
    } on Object {
      // A resposta é da própria tela (captura, geometria), não do socket: o que
      // quer que falhe nela, para o core é "não deu" — sem resposta, o cliente
      // HTTP dele ficaria pendurado.
      reply = const UiReply(null);
    }
    // Sem resposta o cliente HTTP fica pendurado até o tempo esgotar; se a
    // conexão caiu, o core já respondeu por conta própria.
    await _reply(
      request.id,
      reply,
    ).catchError((_) {}, test: (error) => error is HomeError);
  }

  @override
  Future<void> close() async {
    // As duas saem juntas: esperar a primeira atrasaria o corte da segunda.
    await Future.wait([?_subscription?.cancel(), ?_activations?.cancel()]);
    return super.close();
  }
}
