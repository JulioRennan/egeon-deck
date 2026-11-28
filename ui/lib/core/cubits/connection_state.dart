part of 'connection_cubit.dart';

/// Se o app está falando com o core Rust.
sealed class CoreStatus {
  const CoreStatus();
}

/// Subindo o core, ou esperando o canal abrir (de novo).
final class CoreConnecting extends CoreStatus {
  const CoreConnecting();
}

final class CoreConnected extends CoreStatus {
  const CoreConnected();
}

/// O core não subiu.
final class CoreFailed extends CoreStatus {
  const CoreFailed(this.error);

  final CoreError error;
}
