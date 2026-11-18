import '../repository/app_repository.dart';

/// Os gestos do menu e do aviso de atualização.
class AnswerApp {
  const AnswerApp(this._repository);
  final AppRepository _repository;

  Future<void> answerUpdate({
    required String version,
    required bool accept,
    required bool auto,
  }) => _repository.answerUpdate(version: version, accept: accept, auto: auto);

  Future<void> setUpdateAuto({required bool on}) =>
      _repository.setUpdateAuto(on: on);

  Future<void> pressUpdateMenu() => _repository.pressUpdateMenu();

  Future<void> setReaperEnabled({required bool on}) =>
      _repository.setReaperEnabled(on: on);
}
