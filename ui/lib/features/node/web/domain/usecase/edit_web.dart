import '../repository/web_repository.dart';

/// Os gestos do nó web: digitar um endereço, a página navegar, trocar de perfil.
class EditWeb {
  const EditWeb(this._repository);
  final WebRepository _repository;

  Future<void> navigate(String nodeId, String typed) =>
      _repository.navigate(nodeId, typed);
  Future<void> reportNavigated(String nodeId, String url) =>
      _repository.reportNavigated(nodeId, url);
  Future<void> setProfile(String nodeId, String profile) =>
      _repository.setProfile(nodeId, profile);
}
