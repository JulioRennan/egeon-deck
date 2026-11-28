/// Em que pé está a atualização.
enum UpdatePhase {
  idle,
  checking,
  available,
  downloading,
  ready;

  static UpdatePhase parse(Object? raw) =>
      values.firstWhere((p) => p.name == raw, orElse: () => UpdatePhase.idle);
}

/// O item de menu "Procurar atualizações…" e o que há por trás dele. O core
/// manda o título já escolhido pelo estado.
class UpdateView {
  const UpdateView({
    this.phase = UpdatePhase.idle,
    this.menu = 'Procurar atualizações…',
    this.menuEnabled = true,
    this.auto = false,
    this.installed = '',
    this.staged = false,
    this.version,
  });

  final UpdatePhase phase;

  /// A versão disponível, baixando ou pronta.
  final String? version;
  final String menu;
  final bool menuEnabled;

  /// "Atualizar automaticamente" ligado.
  final bool auto;
  final String installed;

  /// Há um app novo esperando ao lado do instalado.
  final bool staged;

  factory UpdateView.fromMap(Map<String, Object?> map) => UpdateView(
    phase: UpdatePhase.parse(map['state']),
    version: map['version'] as String?,
    menu: map['menu'] as String? ?? 'Procurar atualizações…',
    menuEnabled: map['menu_enabled'] as bool? ?? true,
    auto: map['auto'] as bool? ?? false,
    installed: map['installed'] as String? ?? '',
    staged: map['staged'] as bool? ?? false,
  );
}

/// O estado inteiro do tópico `app`: vai na assinatura e a cada mudança.
class AppSnapshot {
  const AppSnapshot({
    this.update = const UpdateView(),
    this.reaperEnabled = true,
  });

  final UpdateView update;

  /// A limpeza automática de órfãos (ADR-083), do menu.
  final bool reaperEnabled;

  factory AppSnapshot.fromMap(Map<String, Object?> map) => AppSnapshot(
    update: UpdateView.fromMap(
      map['update'] as Map<String, Object?>? ?? const {},
    ),
    reaperEnabled:
        (map['reaper'] as Map<String, Object?>?)?['enabled'] as bool? ?? true,
  );
}
