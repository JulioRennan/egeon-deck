import '../entities/ui_request.dart';
import '../repository/ui_request_repository.dart';

class WatchUiRequests {
  const WatchUiRequests(this._repository);

  final UiRequestRepository _repository;

  Stream<UiRequest> call() => _repository.watch();
}
