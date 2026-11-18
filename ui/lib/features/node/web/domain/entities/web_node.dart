/// O que o core sabe de um nó web: a página, o perfil de navegação (cookies e
/// bancada isolados por nome) e os perfis que existem.
class WebNode {
  const WebNode({
    required this.url,
    required this.profile,
    this.profiles = const [],
    this.profileId,
  });

  final String url;
  final String profile;
  final List<String> profiles;

  /// O UUID do data store do perfil (`web-profiles.json`, do core): é ele que
  /// faz o mesmo perfil abrir logado depois de reiniciar.
  final String? profileId;

  factory WebNode.fromMap(Map<String, Object?> map) => WebNode(
    url: map['url'] as String? ?? '',
    profile: map['profile'] as String? ?? 'pessoal',
    profiles: [
      for (final p in (map['profiles'] as List<Object?>? ?? const []))
        p! as String,
    ],
    profileId: map['profile_id'] as String?,
  );

  Map<String, Object?> toMap() => {
    'url': url,
    'profile': profile,
    'profiles': profiles,
    'profile_id': ?profileId,
  };

  /// Os perfis do menu: em ordem, e o do nó mesmo que o arquivo não o liste.
  List<String> get menu {
    final all = {...profiles, profile}.toList()..sort();
    return all;
  }
}
