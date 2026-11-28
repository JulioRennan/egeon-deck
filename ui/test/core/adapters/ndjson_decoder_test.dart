import 'dart:convert';

import 'package:egeon_deck/core/adapters/ndjson_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uma mensagem por linha, mesmo vindo em pedaços', () {
    final decoder = NdjsonDecoder();
    expect(decoder.add(utf8.encode('{"a":1}\n{"b"')), [
      {'a': 1},
    ]);
    expect(decoder.add(utf8.encode(':2}\n')), [
      {'b': 2},
    ]);
  });

  test('caractere UTF-8 partido entre pacotes não quebra', () {
    final bytes = utf8.encode('{"t":"ação"}\n');
    final decoder = NdjsonDecoder();
    expect(decoder.add(bytes.sublist(0, 9)), isEmpty);
    expect(decoder.add(bytes.sublist(9)), [
      {'t': 'ação'},
    ]);
  });

  test('várias linhas num pacote e linha vazia ignorada', () {
    final decoder = NdjsonDecoder();
    expect(decoder.add(utf8.encode('{"a":1}\n\n{"a":2}\n')), [
      {'a': 1},
      {'a': 2},
    ]);
  });
}
