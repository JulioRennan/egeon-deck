import '../../../../core/domain/entities/organization.dart';
import '../../../../core/domain/entities/workbench.dart';
import '../../../../core/domain/entities/workbench_clock.dart';

/// A cortina de "sem acesso à pasta" da bancada.
class AccessLock {
  const AccessLock({required this.text, this.asking = false});

  final String text;

  /// O macOS está perguntando: o texto é o aviso dele, não o nosso.
  final bool asking;
}

/// O que o core diz da casca agora: a bancada na tela e as duas cortinas.
class ShellSnapshot {
  const ShellSnapshot({
    this.bench,
    this.busy,
    this.lock,
    this.banner,
    this.clock,
    this.projectName,
    this.openBenchIds = const {},
  });

  final Workbench? bench;

  /// Texto do "um instante"; ausente, sem cortina.
  final String? busy;
  final AccessLock? lock;

  /// A faixa laranja sobre o conteúdo; ausente, nenhuma.
  final String? banner;

  /// O cronômetro da bancada na tela; ausente até ela ter rodado.
  final WorkbenchClock? clock;

  /// O projeto da bancada na tela, para a trilha `projeto / bancada`; ausente
  /// quando ela é órfã.
  final String? projectName;

  /// As bancadas com aba aberta: para onde o voltar e o avançar ainda podem ir.
  final Set<String> openBenchIds;

  /// A bancada na tela é a da aba ativa. As cortinas e a faixa vêm do core,
  /// com o texto pronto.
  factory ShellSnapshot.fromOrganization(Organization org) {
    final b = org.activeBench;
    return ShellSnapshot(
      bench: b == null
          ? null
          : Workbench(
              id: b.id,
              name: b.name,
              path: b.path,
              color: b.color,
              view: b.view,
              template: b.template,
            ),
      projectName: b?.project == null ? null : org.project(b!.project!)?.name,
      openBenchIds: {for (final t in org.openTabs) t.id},
      busy: b?.busy,
      banner: b?.banner,
      clock: b?.clock,
      lock: b?.access == null ? null : AccessLock(text: b!.access!.message),
    );
  }
}
