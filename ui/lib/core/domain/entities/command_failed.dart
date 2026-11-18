/// O core Rust recusou o comando e disse por quê. [message] já é texto para o
/// usuário ler.
class CommandFailed implements Exception {
  const CommandFailed(this.message);

  final String message;

  @override
  String toString() => message;
}
