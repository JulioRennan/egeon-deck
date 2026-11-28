import '../entities/ui_request.dart';
import '../repository/ui_request_repository.dart';

class ReplyUiRequest {
  const ReplyUiRequest(this._repository);

  final UiRequestRepository _repository;

  Future<void> call(Object request, UiReply reply) =>
      _repository.reply(request, reply);
}
