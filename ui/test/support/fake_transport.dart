import 'dart:async';
import 'dart:convert';

import 'package:egeon_deck/core/adapters/egeon_transport.dart';

class FakeConnection implements EgeonConnection {
  final _input = StreamController<List<int>>();
  final written = <int>[];
  bool closed = false;

  @override
  Stream<List<int>> get input => _input.stream;

  @override
  void write(List<int> bytes) => written.addAll(bytes);

  @override
  Future<void> close() async {
    closed = true;
    if (!_input.isClosed) unawaited(_input.close());
  }

  /// O que a UI escreveu depois do cabeçalho HTTP, uma mensagem por linha.
  List<Map<String, Object?>> get sent {
    final text = utf8.decode(written);
    final split = text.indexOf('\r\n\r\n');
    final body = split < 0 ? '' : text.substring(split + 4);
    return body
        .split('\n')
        .where((l) => l.isNotEmpty)
        .map((l) => jsonDecode(l) as Map<String, Object?>)
        .toList();
  }

  String get head => ascii.decode(written, allowInvalid: true);

  void serve(String text) => _input.add(utf8.encode(text));
  void upgrade() => serve(
    'HTTP/1.1 101 Switching Protocols\r\n'
    'Upgrade: egeon-ndjson\r\nConnection: Upgrade\r\n\r\n',
  );
  void say(Map<String, Object?> message) => serve('${jsonEncode(message)}\n');
  Future<void> drop() => _input.close();
}

class FakeTransport implements EgeonTransport {
  final connections = <FakeConnection>[];
  var refuse = false;

  @override
  Future<EgeonConnection> open() async {
    if (refuse) throw StateError('recusado');
    final connection = FakeConnection();
    connections.add(connection);
    return connection;
  }
}
