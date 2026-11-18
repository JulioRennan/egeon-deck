import 'package:egeon_deck/theme/app_colors.dart';
import 'package:egeon_deck/theme/workbench_palette.dart';
import 'package:flutter_test/flutter_test.dart';

// O que sobra de WorkbenchColorTests.swift do lado da UI: a escolha da cor é
// do core; aqui a paleta tem de ser a mesma e ler o que já está gravado.
void main() {
  test('a paleta tem 24 cores com rótulo e nome únicos', () {
    final labels = WorkbenchPalette.all.map((s) => s.label).toList();
    final names = WorkbenchPalette.all.map((s) => s.name).toList();
    expect(labels.length, 24);
    expect(labels.toSet().length, 24);
    expect(names.toSet().length, 24);
  });

  test('as cores gravadas antes da paleta grande continuam lendo', () {
    for (final name in [
      'blue',
      'violet',
      'pink',
      'cyan',
      'indigo',
      'sand',
      'magenta',
    ]) {
      expect(WorkbenchPalette.of(name), isNot(AppColors.accent), reason: name);
    }
  });

  test('sem cor, ou com cor que saiu da paleta, vale o destaque do app', () {
    expect(WorkbenchPalette.of(null), AppColors.accent);
    expect(WorkbenchPalette.of('dourado'), AppColors.accent);
  });

  test('os nomes seguem o formato do arquivo', () {
    final names = WorkbenchPalette.all.map((s) => s.name);
    expect(names, containsAll(['lightGreen', 'deepPurple', 'raspberry']));
    expect(WorkbenchPalette.of('teal').toARGB32(), 0xFF26A69A);
  });
}
