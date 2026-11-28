import 'dart:convert';
import 'dart:io';

/// As fixtures são gravadas pelo core Rust; os testes só conferem que a UI lê
/// e escreve exatamente o que ele fala. Cada arquivo é {nome_do_exemplo: msg}.
Map<String, Map<String, Object?>> loadProtocolFixture(String name) {
  final raw = jsonDecode(
    File('../rust/crates/egeon-core/fixtures/protocol/$name.json')
        .readAsStringSync(),
  ) as Map<String, Object?>;
  return raw.map((k, v) => MapEntry(k, v! as Map<String, Object?>));
}

/// O comando como a fixture o grava, sem o id (que a UI escolhe).
Map<String, Object?> withoutId(Map<String, Object?> message) =>
    {...message}..remove('id');
