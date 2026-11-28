import 'dart:io';

import 'package:flutter/foundation.dart';

/// Qual cópia do app novo está rodando, como no Swift: o estável segura os
/// agentes de verdade, e o dev é o que se derruba e reconstrói. Com uma pasta
/// só, os dois subiriam os mesmos terminais e brigariam pelo workbenches.json.
///
/// O estável só vale num build release, fora de um bundle "Dev" e sem
/// `EGEON_FLAVOR=dev`; na dúvida, dev. O `LSEnvironment` que o
/// `scripts/make.sh` grava sozinho não basta: o macOS guarda o Info.plist em
/// cache e o bundle reconstruído no mesmo caminho subiu sem a variável — ligado
/// ao core e aos agentes de verdade. O lançador repassa o flavor ao core.
enum EgeonFlavor {
  stable(folder: '.egeon-next', title: 'Egeon Deck'),
  dev(folder: '.egeon-next-dev', title: 'Egeon Deck (dev)');

  const EgeonFlavor({required this.folder, required this.title});

  final String folder;
  final String title;

  static EgeonFlavor resolve(
    Map<String, String> environment, {
    required bool release,
    required String executable,
  }) {
    final isDev =
        environment['EGEON_FLAVOR'] == 'dev' ||
        !release ||
        executable.contains('Dev.app/');
    return isDev ? dev : stable;
  }
}

/// Onde o app novo guarda as coisas: `$EGEON_HOME` ou a pasta do flavor
/// (`~/.egeon-next`, `~/.egeon-next-dev`). Nunca `~/.egeon`, que é do Egeon
/// estável.
///
/// No Windows a pasta pessoal vem sempre de `USERPROFILE` (o `HOME` é ignorado), com os mesmos nomes de pasta; o separador é o da pasta
/// pessoal, para o caminho sair como o sistema o escreve (decisão 54).
class EgeonPaths {
  EgeonPaths(
    Map<String, String> environment, {
    bool release = kReleaseMode,
    String? executable,
    bool? windows,
  }) : _env = environment,
       _windows = windows ?? Platform.isWindows,
       flavor = EgeonFlavor.resolve(
         environment,
         release: release,
         executable: executable ?? Platform.resolvedExecutable,
       );

  final Map<String, String> _env;
  final bool _windows;
  final EgeonFlavor flavor;

  String get home {
    final custom = _env['EGEON_HOME'];
    if (custom != null && custom.isNotEmpty) return custom;
    final user = userHome(_env, windows: _windows) ?? '';
    return '$user${_separatorOf(user)}${flavor.folder}';
  }

  String get socket => '$home${_separatorOf(home)}sock';

  /// A pasta pessoal: `HOME`; no Windows só `USERPROFILE`, porque o `HOME` de
  /// um Git Bash ou MSYS mudaria a pasta de dados conforme de onde o app foi
  /// aberto (o core Rust faz igual).
  static String? userHome(
    Map<String, String> environment, {
    required bool windows,
  }) {
    for (final name
        in windows ? const ['USERPROFILE'] : const ['HOME', 'USERPROFILE']) {
      final value = environment[name];
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String _separatorOf(String path) => path.contains(r'\') ? r'\' : '/';
}
