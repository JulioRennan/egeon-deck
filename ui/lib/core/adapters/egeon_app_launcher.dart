import 'dart:io';

import 'egeon_paths.dart';
import 'egeon_transport.dart';

typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  ProcessStartMode mode,
});

/// Lança o `egeon-app` (o executável do core Rust) como processo filho.
///
/// Se já há um core atendendo no socket, não lança outro, e então também não
/// encerra nenhum: só se encerra o filho que este lançador criou.
///
/// O filho nasce com o stdin em cano e a opção `--exit-with-stdin`: o core
/// sai quando o cano fecha, o que acontece com a UI morta de qualquer jeito
/// (`kill -9` inclusive). O ⌘Q passa por [stop], que manda SIGTERM.
class EgeonAppLauncher {
  EgeonAppLauncher({
    required this.paths,
    required this._probe,
    this._executable,
    ProcessStarter? starter,
    Map<String, String>? environment,
  }) : _starter = starter ?? _defaultStarter,
       _environment = environment ?? Platform.environment;

  final EgeonPaths paths;
  final EgeonTransport _probe;
  final String? _executable;
  final ProcessStarter _starter;
  final Map<String, String> _environment;

  Process? _child;

  static Future<Process> _defaultStarter(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) => Process.start(
    executable,
    arguments,
    environment: environment,
    mode: mode,
  );

  /// O core vigia o stdin: o cano é da UI, que nunca escreve nele.
  static const watchStdinFlag = '--exit-with-stdin';

  /// Garante um core rodando; devolve se foi esta chamada que o lançou.
  Future<bool> ensureRunning() async {
    if (await _alreadyListening()) return false;
    final executable = _executable ?? locate();
    if (executable == null) {
      throw StateError(
        'egeon-app não encontrado: defina EGEON_APP_BIN ou compile com '
        '`cargo build` em rust/',
      );
    }
    final child = await _starter(
      executable,
      const [watchStdinFlag],
      // O core decide identificador e nome pelo flavor; a pasta ele recebe
      // pronta, para os dois lados nunca discordarem dela.
      environment: {
        ..._environment,
        'EGEON_HOME': paths.home,
        'EGEON_FLAVOR': paths.flavor.name,
      },
      mode: ProcessStartMode.normal,
    );
    _child = child;
    // O log do core vai para <EGEON_HOME>/egeon.log, mas o cano precisa ser
    // drenado: cheio, travaria o core.
    child.stdout.listen(stdout.add, onError: (_) {});
    child.stderr.listen(stderr.add, onError: (_) {});
    return true;
  }

  Future<void> stop() async {
    final child = _child;
    _child = null;
    child?.kill();
  }

  Future<bool> _alreadyListening() async {
    try {
      final connection = await _probe.open();
      await connection.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// `EGEON_APP_BIN`, o irmão do executável da UI (dentro do `.app`) ou, em
  /// desenvolvimento, o binário de `rust/target` mais perto da pasta atual.
  String? locate() {
    final fromEnv = _environment['EGEON_APP_BIN'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

    final sibling = File(
      '${File(Platform.resolvedExecutable).parent.path}/egeon-app',
    );
    if (sibling.existsSync()) return sibling.path;

    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      for (final profile in const ['debug', 'release']) {
        final candidate = File('${dir.path}/rust/target/$profile/egeon-app');
        if (candidate.existsSync()) return candidate.path;
      }
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
    return null;
  }
}
