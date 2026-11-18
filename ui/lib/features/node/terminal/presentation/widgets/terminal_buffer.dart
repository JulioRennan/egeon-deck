import 'package:flutter/foundation.dart';

import '../../domain/entities/terminal_cursor.dart';
import '../../domain/entities/terminal_frame.dart';
import '../../domain/entities/terminal_line.dart';
import '../../domain/entities/terminal_scrollbar.dart';

/// A tela que o widget está mostrando: um notificador por linha, para que só
/// as linhas alteradas sejam repintadas. Notifica a si mesmo quando o
/// tamanho da grade muda.
class TerminalBuffer extends ChangeNotifier {
  int _columns = 0;
  List<ValueNotifier<TerminalLine>> _lines = const [];

  final cursor = ValueNotifier<TerminalCursor>(TerminalCursor.hidden);

  /// A última barra que o core mandou: no `delta` ela só vem quando mudou.
  final scrollbar = ValueNotifier<TerminalScrollbar?>(null);

  int get columns => _columns;
  int get rows => _lines.length;
  List<ValueNotifier<TerminalLine>> get lines => _lines;

  void apply(TerminalFrame frame) {
    final resized = frame.columns != _columns || frame.rows != _lines.length;
    if (resized) {
      final old = _lines;
      _lines = List.generate(
        frame.rows,
        (i) =>
            ValueNotifier(i < old.length ? old[i].value : TerminalLine.empty),
      );
      for (final n in old) {
        n.dispose();
      }
      _columns = frame.columns;
    }
    if (frame.full) {
      for (final line in _lines) {
        line.value = TerminalLine.empty;
      }
    }
    frame.lines.forEach((index, line) {
      if (index >= 0 && index < _lines.length) _lines[index].value = line;
    });
    cursor.value = frame.cursor;
    if (frame.scrollbar != null) {
      scrollbar.value = frame.scrollbar;
    } else if (frame.full) {
      scrollbar.value = null;
    }
    if (resized) notifyListeners();
  }

  @override
  void dispose() {
    for (final n in _lines) {
      n.dispose();
    }
    cursor.dispose();
    scrollbar.dispose();
    super.dispose();
  }
}
