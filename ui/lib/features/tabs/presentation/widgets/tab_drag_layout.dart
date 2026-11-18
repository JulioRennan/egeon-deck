/// A conta do arrasto da faixa, sem widget nenhum: onde cada pastilha pousa e
/// para qual posição a que está na mão deve ir.
///
/// A pastilha acompanha o cursor e as vizinhas deslizam para abrir espaço, como
/// no VS Code; por isso a ordem é recalculada a cada passo do mouse.
abstract final class TabDragLayout {
  /// O x de cada pastilha, na ordem, começando em [start] com [gap] entre elas.
  static List<double> offsets({
    required List<double> widths,
    required double start,
    required double gap,
  }) {
    final out = <double>[];
    var x = start;
    for (final width in widths) {
      out.add(x);
      x += width + gap;
    }
    return out;
  }

  /// Para qual índice vai a pastilha arrastada, dado o CENTRO dela.
  ///
  /// A troca acontece quando o centro da arrastada passa o centro da vizinha —
  /// com as bordas, abas de larguras diferentes trocavam duas vezes no mesmo
  /// movimento e a faixa tremia.
  static int destination({
    required double center,
    required int dragging,
    required List<double> widths,
    required double start,
    required double gap,
  }) {
    if (dragging < 0 || dragging >= widths.length) return dragging;
    final xs = offsets(widths: widths, start: start, gap: gap);
    var target = dragging;
    for (var i = dragging + 1; i < widths.length; i++) {
      if (center > xs[i] + widths[i] / 2) target = i;
    }
    if (target == dragging) {
      for (var i = dragging - 1; i >= 0; i--) {
        if (center < xs[i] + widths[i] / 2) target = i;
      }
    }
    return target;
  }

  /// Reordena tirando de [from] e enfiando em [to]; índice impossível não mexe.
  static List<T> moved<T>(List<T> list, int from, int to) {
    final valid =
        from >= 0 && from < list.length && to >= 0 && to < list.length;
    if (!valid || from == to) return list;
    final out = [...list];
    out.insert(to, out.removeAt(from));
    return out;
  }
}
