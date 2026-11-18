/// Qual cópia do app novo está rodando, como no Swift: o estável segura os
/// agentes de verdade, e o dev é o que se derruba e reconstrói. Com uma pasta
/// só, os dois subiriam os mesmos terminais e brigariam pelo workbenches.json.
///
/// Quem diz é `EGEON_FLAVOR=dev`, que o `scripts/make.sh` grava no
/// `LSEnvironment` do bundle dev; o lançador repassa a variável ao core.
enum EgeonFlavor {
  stable(folder: '.egeon-next', title: 'Egeon Deck'),
  dev(folder: '.egeon-next-dev', title: 'Egeon Deck (dev)');

  const EgeonFlavor({required this.folder, required this.title});

  final String folder;
  final String title;

  static EgeonFlavor fromEnvironment(Map<String, String> environment) =>
      environment['EGEON_FLAVOR'] == 'dev' ? dev : stable;
}

/// Onde o app novo guarda as coisas: `$EGEON_HOME` ou a pasta do flavor
/// (`~/.egeon-next`, `~/.egeon-next-dev`). Nunca `~/.egeon`, que é do Egeon
/// estável.
class EgeonPaths {
  EgeonPaths(Map<String, String> environment)
    : _env = environment,
      flavor = EgeonFlavor.fromEnvironment(environment);

  final Map<String, String> _env;
  final EgeonFlavor flavor;

  String get home {
    final custom = _env['EGEON_HOME'];
    if (custom != null && custom.isNotEmpty) return custom;
    return '${_env['HOME'] ?? ''}/${flavor.folder}';
  }

  String get socket => '$home/sock';
}
