import 'package:egeon_deck/core/domain/entities/view_mode.dart';
import 'package:flutter_test/flutter_test.dart';

// Porte de ViewModeTests.swift, o lado que a UI lê.
void main() {
  test('os nomes são formato de arquivo e parâmetro de rota', () {
    expect(ViewMode.canvas.wire, 'canvas');
    expect(ViewMode.chat.wire, 'chat');
  });

  test('ausente vira canvas e chat é lido', () {
    expect(ViewMode.fromWire(null), ViewMode.canvas);
    expect(ViewMode.fromWire('chat'), ViewMode.chat);
  });

  test('modo desconhecido ou aposentado (mosaico) abre no canvas', () {
    expect(ViewMode.fromWire('holograma'), ViewMode.canvas);
    expect(ViewMode.fromWire('mosaic'), ViewMode.canvas);
    expect(ViewMode.values, [ViewMode.canvas, ViewMode.chat]);
  });
}
