/// O que pode dar errado ao subir o core Rust.
sealed class CoreError implements Exception {
  const CoreError();
}

/// O `egeon-app` não subiu: não foi achado, ou o processo não abriu.
final class CoreLaunchFailed extends CoreError {
  const CoreLaunchFailed(this.message);

  final String message;

  @override
  String toString() => message;
}
