import 'dart:async';
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
/// (`kill -9` inclusive). O ⌘Q passa por [stop], que manda SIGTERM; no Windows
/// não há sinal (o `kill` seria o encerramento seco, sem o `stop` ordenado do
/// core), então [stop] fecha o cano e espera o core sair.
class EgeonAppLauncher {
  EgeonAppLauncher({
    required this.paths,
    required this._probe,
    this._executable,
    ProcessStarter? starter,
    Map<String, String>? environment,
    String? uiExecutable,
    bool? windows,
    this.stopTimeout = const Duration(seconds: 5),
  }) : _starter = starter ?? _defaultStarter,
       _environment = environment ?? Platform.environment,
       _uiExecutable = uiExecutable ?? Platform.resolvedExecutable,
       _windows = windows ?? Platform.isWindows;

  final EgeonPaths paths;

  /// Quanto o core tem para sair sozinho depois do cano fechado, no Windows;
  /// passado o prazo, é encerrado à força.
  final Duration stopTimeout;
  final EgeonTransport _probe;
  final String? _executable;
  final ProcessStarter _starter;
  final Map<String, String> _environment;
  final String _uiExecutable;
  final bool _windows;

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
    if (child == null) return;
    if (!_windows) {
      child.kill();
      return;
    }
    // O mesmo caminho do SIGTERM: o core encerra os terminais e sai.
    try {
      await child.stdin.close();
      await child.exitCode.timeout(stopTimeout);
    } on TimeoutException {
      child.kill();
    } on IOException {
      // O cano já estava quebrado: o core não está mais lendo.
      child.kill();
    }
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

  /// `EGEON_APP_BIN`, o irmão do executável da UI (dentro do `.app` no macOS;
  /// em `build/linux/<arch>/<modo>/bundle/` no Linux, onde o `scripts/linux/package.sh` o põe;
  /// o `egeon-app.exe` na pasta do `egeon_deck.exe` no Windows) ou,
  /// em desenvolvimento, o binário de `rust/target` mais perto da pasta atual.
  String? locate() {
    final fromEnv = _environment['EGEON_APP_BIN'];
    if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;

    final name = _windows ? 'egeon-app.exe' : 'egeon-app';
    final folder = File(_uiExecutable).parent.path;
    final separator = folder.contains(r'\') ? r'\' : '/';
    final sibling = File('$folder$separator$name');
    if (sibling.existsSync()) return sibling.path;

    // No Windows o core compila para o alvo `-gnu` (decisão 54), que o cargo
    // põe numa pasta com o nome do alvo.
    final targets = _windows
        ? const ['', 'x86_64-pc-windows-gnu/']
        : const [''];
    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      for (final target in targets) {
        for (final profile in const ['debug', 'release']) {
          final candidate = File(
            '${dir.path}/rust/target/$target$profile/$name',
          );
          if (candidate.existsSync()) return candidate.path;
        }
      }
      if (dir.parent.path == dir.path) break;
      dir = dir.parent;
    }
    return null;
  }
}
