import 'dart:convert';
import 'dart:typed_data';

/// Corta o fluxo de bytes em linhas e decodifica cada uma como JSON.
///
/// Só decodifica linha completa, então um caractere UTF-8 partido entre dois
/// pacotes nunca é lido pela metade.
class NdjsonDecoder {
  final _pending = BytesBuilder(copy: false);

  List<Object?> add(List<int> chunk) {
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    final messages = <Object?>[];
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != 0x0A) continue;
      _pending.add(Uint8List.sublistView(bytes, start, i));
      start = i + 1;
      final line = _pending.takeBytes();
      if (line.isNotEmpty) messages.add(jsonDecode(utf8.decode(line)));
    }
    if (start < bytes.length) {
      _pending.add(Uint8List.sublistView(bytes, start));
    }
    return messages;
  }
}
