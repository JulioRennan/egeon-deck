import 'dart:async';

import 'package:egeon_deck/features/home/domain/entities/ui_request.dart';
import 'package:egeon_deck/features/home/domain/repository/ui_request_repository.dart';

/// O core falso pedindo coisas à tela: o teste empurra pedidos e lê as
/// respostas.
class FakeUiRequestRepository implements UiRequestRepository {
  final _requests = StreamController<UiRequest>.broadcast();
  final replies = <(Object, UiReply)>[];

  bool get hasListener => _requests.hasListener || _activations.hasListener;

  void ask(String route, [Map<String, String> params = const {}, int id = 1]) =>
      _requests.add(UiRequest(id: id, route: route, params: params));

  @override
  Stream<UiRequest> watch() => _requests.stream;

  final _activations = StreamController<void>.broadcast();

  void activate() => _activations.add(null);

  @override
  Stream<void> activations() => _activations.stream;

  @override
  Future<void> reply(Object request, UiReply reply) async =>
      replies.add((request, reply));
}
