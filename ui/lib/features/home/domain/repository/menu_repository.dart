/// Os itens do menu do app que perguntam ao core Rust.
abstract interface class MenuRepository {
  /// Os alvos de dispatch vivos, um por linha (⇧⌘T).
  Future<String> dispatchTargets();
}
