/// Um pedido do core que só a tela sabe responder (decisão 35): as rotas HTTP
/// `/layout`, `/sidebar`, `/geometry` e `/shot`.
class UiRequest {
  const UiRequest({
    required this.id,
    required this.route,
    this.params = const {},
  });

  factory UiRequest.fromMap(Map<String, Object?> map) => UiRequest(
    id: map['id']!,
    route: map['route'] as String? ?? '',
    params: {
      for (final entry
          in (map['params'] as Map<Object?, Object?>? ?? const {}).entries)
        entry.key.toString(): entry.value.toString(),
    },
  );

  /// Devolvido do jeito que veio (número ou texto): é a chave que o core usa
  /// para achar o cliente HTTP à espera.
  final Object id;

  /// `layout`, `sidebar`, `geometry` ou `shot`.
  final String route;

  /// A query do HTTP, em texto.
  final Map<String, String> params;
}

/// A resposta da tela: só o valor que a ação devolve — o core monta o status e
/// o corpo HTTP. `null` é "não deu" (modo ou aba inválidos, sem bancada), que o
/// core responde como o Swift.
class UiReply {
  const UiReply(this.value);

  /// O modo ou a aba aplicados, o estado recolhido, o retrato do canvas ou o
  /// caminho gravado (`erro: …` quando não gravou).
  final Object? value;
}
