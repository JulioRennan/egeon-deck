import '../entities/app_effect.dart';
import '../entities/app_state.dart';
import '../repository/app_repository.dart';

class WatchApp {
  const WatchApp(this._repository);
  final AppRepository _repository;

  Stream<AppState> state() => _repository.watch();

  Stream<AppEffect> effects() => _repository.effects();
}
