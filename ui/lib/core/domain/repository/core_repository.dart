/// O core Rust visto pela UI: garantir que ele roda, ligar o canal e saber se
/// a conexão está de pé.
abstract interface class CoreRepository {
  /// `true` quando o canal com o core abre, `false` quando cai.
  Stream<bool> watchLink();

  /// Garante um core atendendo: lança o `egeon-app` se nada responde.
  Future<void> launch();

  /// Liga o canal; ele reconecta sozinho depois de uma queda.
  void connect();

  /// Fecha o canal e encerra o core que a UI lançou.
  Future<void> stop();
}
