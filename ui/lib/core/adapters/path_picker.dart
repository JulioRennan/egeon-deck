import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'egeon_paths.dart';

/// Os seletores de pasta e de imagem do sistema. É o único lugar que conhece a
/// biblioteca que abre as janelas do sistema. As pastas voltam como o usuário as
/// vê: com `~` no lugar da pasta pessoal, que é como o core as guarda. No
/// Windows o que vem depois do `~` leva `/` (`~/proj`) e a comparação com a
/// pasta pessoal ignora maiúsculas, como o sistema de arquivos.
abstract interface class PathPicker {
  /// Uma ou mais pastas; lista vazia se cancelou.
  Future<List<String>> folders({String? prompt, String? initialDirectory});

  /// Uma pasta; `null` se cancelou.
  Future<String?> folder({String? prompt, String? initialDirectory});

  /// Uma imagem; `null` se cancelou.
  Future<String?> image();
}

class SystemPathPicker implements PathPicker {
  SystemPathPicker({String? home})
    : _home = home ?? EgeonPaths.userHome(
        Platform.environment,
        windows: Platform.isWindows,
      );

  final String? _home;

  @override
  Future<List<String>> folders({String? prompt, String? initialDirectory}) =>
      getDirectoryPaths(
        confirmButtonText: prompt,
        initialDirectory: expand(initialDirectory),
      ).then((paths) => [for (final p in paths) ?abbreviate(p)]);

  @override
  Future<String?> folder({String? prompt, String? initialDirectory}) =>
      getDirectoryPath(
        confirmButtonText: prompt,
        initialDirectory: expand(initialDirectory),
      ).then(abbreviate);

  @override
  Future<String?> image() async {
    const types = XTypeGroup(
      label: 'Imagens',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'tiff', 'heic'],
    );
    final file = await openFile(acceptedTypeGroups: const [types]);
    return file?.path;
  }

  @visibleForTesting
  String? abbreviate(String? path) {
    final home = _home;
    if (path == null || home == null || home.isEmpty) return path;
    final windows = home.contains(r'\');
    final clean = path.length > 1
        ? path.replaceAll(windows ? RegExp(r'[\\/]+$') : RegExp(r'/+$'), '')
        : path;
    if (!windows) {
      if (clean == home) return '~';
      return clean.startsWith('$home/')
          ? '~${clean.substring(home.length)}'
          : clean;
    }
    final base = home.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');
    final normal = clean.replaceAll(r'\', '/');
    if (normal.toLowerCase() == base.toLowerCase()) return '~';
    return normal.length > base.length &&
            normal.substring(0, base.length + 1).toLowerCase() ==
                '${base.toLowerCase()}/'
        ? '~${normal.substring(base.length)}'
        : clean;
  }

  @visibleForTesting
  String? expand(String? path) {
    final home = _home;
    if (path == null || home == null) return path;
    if (path == '~') return home;
    if (!path.startsWith('~/')) return path;
    final rest = path.substring(1);
    return home.contains(r'\')
        ? '$home${rest.replaceAll('/', r'\')}'
        : '$home$rest';
  }
}
