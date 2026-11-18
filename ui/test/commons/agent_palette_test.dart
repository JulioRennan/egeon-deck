import 'package:egeon_deck/commons/utils/agent_palette.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cor do agente é estável: FNV-1a de 64 bits sobre o id, módulo 6. Os índices
/// esperados saíram de uma conta independente (Python), não desta implementação.
void main() {
  const expected = {
    'claude': 3, // ciano
    'dev': 4, // amarelo
    'front': 4,
    'sh': 2, // rosa
    'rev': 2,
    'órfão': 4, // UTF-8, não pontos de código
    'a': 4,
    '': 5, // o hash do vazio é a semente
  };

  test('o mesmo id dá sempre a mesma cor, a de FNV-1a', () {
    expected.forEach((id, index) {
      expect(AgentPalette.of(id), AgentPalette.colors[index], reason: '"$id"');
      expect(AgentPalette.of(id), AgentPalette.of(id));
    });
  });

  test('a paleta tem seis cores distintas', () {
    expect(AgentPalette.colors.toSet(), hasLength(6));
  });
}
