import '../../../../core/domain/entities/organization.dart';
import '../../../../core/domain/entities/workbench.dart';

/// A cortina de "sem acesso à pasta" da bancada.
class AccessLock {
  const AccessLock({required this.text, this.asking = false});

  final String text;

  /// O macOS está perguntando: o texto é o aviso dele, não o nosso.
  final bool asking;
}

/// O que a casca mostra agora: a bancada na tela e as duas cortinas.
class ShellState {
  const ShellState({this.bench, this.busy, this.lock});

  final Workbench? bench;

  /// Texto do "um instante"; ausente, sem cortina.
  final String? busy;
  final AccessLock? lock;

  /// A bancada na tela é a da aba ativa. A cortina de acesso vem do core, com o
  /// texto pronto; a de "um instante" ainda não.
  factory ShellState.fromOrganization(Organization org) {
    final b = org.activeBench;
    return ShellState(
      bench: b == null
          ? null
          : Workbench(
              id: b.id,
              name: b.name,
              path: b.path,
              color: b.color,
              view: b.view,
            ),
      lock: b?.access == null ? null : AccessLock(text: b!.access!.message),
    );
  }
}
