import 'package:egeon_deck/features/tabs/presentation/widgets/tab_drag_layout.dart';
import 'package:flutter_test/flutter_test.dart';

// Porte de TabDragLayoutTests.swift: o que se segura aqui é o tremor, que
// aparece quando um critério mal escolhido troca as abas duas vezes no mesmo
// movimento.
void main() {
  const widths = <double>[100, 160, 120];
  const start = 10.0;
  const gap = 4.0;

  double center(int index) {
    final xs = TabDragLayout.offsets(widths: widths, start: start, gap: gap);
    return xs[index] + widths[index] / 2;
  }

  int destination(double center, int dragging) => TabDragLayout.destination(
    center: center,
    dragging: dragging,
    widths: widths,
    start: start,
    gap: gap,
  );

  test('os x empilham com o espaço entre as pastilhas', () {
    expect(TabDragLayout.offsets(widths: widths, start: start, gap: gap), [
      10,
      114,
      278,
    ]);
  });

  test('parado, a pastilha mantém a posição', () {
    for (var i = 0; i < widths.length; i++) {
      expect(destination(center(i), i), i);
    }
  });

  test('encostar na vizinha não basta: só troca depois do centro dela', () {
    expect(destination(center(1) - 1, 0), 0);
    expect(destination(center(1) + 1, 0), 1);
  });

  test('arrastar até o fim e até o começo', () {
    expect(destination(10000, 0), 2);
    expect(destination(-10000, 2), 0);
  });

  test('para fora da faixa prende nas pontas em vez de estourar o índice', () {
    final alvo = destination(99999, 1);
    expect(alvo, 2);
    expect(alvo, lessThan(widths.length));
  });

  test('moved tira de um lugar e põe no outro', () {
    expect(TabDragLayout.moved(['a', 'b', 'c'], 0, 2), ['b', 'c', 'a']);
    expect(TabDragLayout.moved(['a', 'b', 'c'], 2, 0), ['c', 'a', 'b']);
    expect(TabDragLayout.moved(['a', 'b', 'c'], 1, 1), ['a', 'b', 'c']);
    expect(TabDragLayout.moved(['a', 'b', 'c'], 5, 0), ['a', 'b', 'c']);
    expect(TabDragLayout.moved(<String>[], 0, 0), isEmpty);
  });

  test('índice desconhecido é inerte: bancada que saiu no meio do arrasto', () {
    expect(destination(50, 9), 9);
  });
}
