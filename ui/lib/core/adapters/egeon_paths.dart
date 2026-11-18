/// Onde o app novo guarda as coisas: `$EGEON_HOME` ou `~/.egeon-next`.
/// Nunca `~/.egeon`, que é do Egeon estável.
class EgeonPaths {
  EgeonPaths(Map<String, String> environment) : _env = environment;

  final Map<String, String> _env;

  String get home {
    final custom = _env['EGEON_HOME'];
    if (custom != null && custom.isNotEmpty) return custom;
    return '${_env['HOME'] ?? ''}/.egeon-next';
  }

  String get socket => '$home/sock';
}
