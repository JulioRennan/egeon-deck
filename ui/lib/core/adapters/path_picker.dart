import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// Os seletores de pasta e de imagem do sistema. É o único lugar que conhece a
/// biblioteca que abre as janelas do macOS. As pastas voltam como o usuário as
/// vê: com `~` no lugar da pasta pessoal, que é como o core as guarda.
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
    : _home = home ?? Platform.environment['HOME'];

  final String? _home;

  @override
  Future<List<String>> folders({String? prompt, String? initialDirectory}) =>
      getDirectoryPaths(
        confirmButtonText: prompt,
        initialDirectory: _expand(initialDirectory),
      ).then((paths) => [for (final p in paths) ?_abbreviate(p)]);

  @override
  Future<String?> folder({String? prompt, String? initialDirectory}) =>
      getDirectoryPath(
        confirmButtonText: prompt,
        initialDirectory: _expand(initialDirectory),
      ).then(_abbreviate);

  @override
  Future<String?> image() async {
    const types = XTypeGroup(
      label: 'Imagens',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'tiff', 'heic'],
    );
    final file = await openFile(acceptedTypeGroups: const [types]);
    return file?.path;
  }

  String? _abbreviate(String? path) {
    final home = _home;
    if (path == null || home == null || home.isEmpty) return path;
    final clean = path.length > 1 ? path.replaceAll(RegExp(r'/+$'), '') : path;
    if (clean == home) return '~';
    return clean.startsWith('$home/')
        ? '~${clean.substring(home.length)}'
        : clean;
  }

  String? _expand(String? path) {
    final home = _home;
    if (path == null || home == null) return path;
    if (path == '~') return home;
    return path.startsWith('~/') ? '$home${path.substring(1)}' : path;
  }
}
