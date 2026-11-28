import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

/// As janelas do sistema que o app abre além da principal (decisão 51). Cada
/// uma roda num motor Flutter próprio, que liga ao socket do core como mais um
/// cliente.
enum WindowKind { processes }

/// O que a janela nova recebe ao nascer: que tela desenhar e o título.
class WindowArguments {
  const WindowArguments({required this.kind, required this.title});

  final WindowKind kind;
  final String title;

  String encode() => jsonEncode({'kind': kind.name, 'title': title});

  static WindowArguments? decode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final kind = WindowKind.values.asNameMap()[map['kind']];
      final title = map['title'];
      if (kind == null || title is! String) return null;
      return WindowArguments(kind: kind, title: title);
    } on FormatException {
      return null;
    }
  }

  /// O motor de uma janela aberta pelo pacote recebe
  /// `["multi_window", <id>, <argumentos>]` no `main`; a principal, nada.
  static WindowArguments? fromEntrypoint(List<String> args) =>
      args.length >= 3 && args.first == 'multi_window' ? decode(args[2]) : null;
}

abstract interface class AppWindows {
  /// Abre a janela de [arguments]; já aberta uma do mesmo tipo, traz essa
  /// para a frente em vez de abrir outra.
  Future<void> open(WindowArguments arguments);
}

class MultiWindowAppWindows implements AppWindows {
  const MultiWindowAppWindows();

  /// A abertura em curso de cada tipo: duas chamadas próximas (tecla repetida,
  /// dois cliques) veem a lista de janelas vazia e criariam dois motores, e a
  /// segunda espera a primeira em vez de criar outro.
  static final _opening = <WindowKind, Future<void>>{};

  @override
  Future<void> open(WindowArguments arguments) {
    final running = _opening[arguments.kind];
    if (running != null) return running;
    // Bloco, e não `=> remove(...)`: o `remove` devolve o próprio Future, e o
    // `whenComplete` esperaria por ele mesmo.
    return _opening[arguments.kind] = _open(arguments).whenComplete(() {
      _opening.remove(arguments.kind);
    });
  }

  Future<void> _open(WindowArguments arguments) async {
    for (final window in await WindowController.getAll()) {
      if (WindowArguments.decode(window.arguments)?.kind == arguments.kind) {
        await window.show();
        return;
      }
    }
    // Nasce escondida: o runner a ajusta (título, tamanho) antes de mostrar.
    await WindowController.create(
      WindowConfiguration(arguments: arguments.encode()),
    );
  }
}

/// A janela deste motor, pelo canal que cada runner registra nas janelas que
/// o pacote cria.
abstract interface class CurrentWindow {
  /// Título, tamanho e mínimo; [autosave] guarda onde ela estava entre as
  /// aberturas, como o `setFrameAutosaveName` do Swift. Depois, mostra.
  Future<void> present({
    required String title,
    required Size size,
    required Size minSize,
    required String autosave,
  });

  Future<void> close();
}

class ChannelCurrentWindow implements CurrentWindow {
  const ChannelCurrentWindow();

  static const _channel = MethodChannel('egeon/window');

  @override
  Future<void> present({
    required String title,
    required Size size,
    required Size minSize,
    required String autosave,
  }) async {
    final arguments = {
      'title': title,
      'width': size.width,
      'height': size.height,
      'minWidth': minSize.width,
      'minHeight': minSize.height,
      'autosave': autosave,
    };
    // No Windows o motor da janela já roda o Dart quando o runner registra o
    // canal, e nos primeiros quadros ele pode ainda não existir: sem a
    // repetição a janela, que nasce escondida, nunca apareceria.
    for (var attempt = 0; ; attempt++) {
      try {
        return await _channel.invokeMethod<void>('present', arguments);
      } on MissingPluginException {
        if (attempt == _presentAttempts) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  static const _presentAttempts = 20;

  @override
  Future<void> close() => _channel.invokeMethod<void>('close');
}
