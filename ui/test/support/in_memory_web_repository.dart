import 'dart:async';

import 'package:egeon_deck/features/node/web/domain/entities/web_node.dart';
import 'package:egeon_deck/features/node/web/domain/repository/web_repository.dart';

/// Nó web em memória, com a regra de endereço que o core vai ter, até o
/// contrato.
class InMemoryWebRepository implements WebRepository {
  InMemoryWebRepository({WebNode? state})
    : _state =
          state ??
          const WebNode(
            url: 'https://www.google.com',
            profile: 'pessoal',
            profiles: ['pessoal', 'trabalho'],
            profileId: '3f2a9c1e-5b7d-4e8a-9c0b-1d2e3f4a5b6c',
          );

  WebNode _state;
  final _changes = StreamController<void>.broadcast();
  final reported = <String>[];

  WebNode get state => _state;

  void _set(WebNode state) {
    _state = state;
    _changes.add(null);
  }

  @override
  Stream<WebNode> watch(String nodeId) {
    late final StreamController<WebNode> controller;
    StreamSubscription<void>? changes;
    controller = StreamController<WebNode>(
      onListen: () {
        controller.add(_state);
        changes = _changes.stream.listen((_) => controller.add(_state));
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  /// Barra de endereço de navegador: com esquema, vai direto; parecendo um
  /// host, vira https; o resto vira busca.
  static String? normalize(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.contains('://')) return text;
    final head = text.split('/').first;
    final looksLikeHost =
        !head.contains(' ') &&
        (head.contains('.') ||
            head.startsWith('localhost') ||
            head.startsWith('127.0.0.1'));
    if (looksLikeHost) return 'https://$text';
    return 'https://www.google.com/search?q=${Uri.encodeQueryComponent(text)}';
  }

  @override
  Future<void> navigate(String nodeId, String typed) async {
    final url = normalize(typed);
    if (url == null) return;
    _set(
      WebNode(
        url: url,
        profile: _state.profile,
        profiles: _state.profiles,
        profileId: _state.profileId,
      ),
    );
  }

  @override
  Future<void> reportNavigated(String nodeId, String url) async {
    reported.add(url);
    _set(
      WebNode(
        url: url,
        profile: _state.profile,
        profiles: _state.profiles,
        profileId: _state.profileId,
      ),
    );
  }

  @override
  Future<void> setProfile(String nodeId, String profile) async => _set(
    WebNode(
      url: _state.url,
      profile: profile,
      profiles: {..._state.profiles, profile}.toList(),
      // O core cria o UUID do perfil novo; o falso inventa um por nome.
      profileId: 'uuid-$profile',
    ),
  );
}
