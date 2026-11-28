import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'egeon_transport.dart';
import 'ndjson_decoder.dart';

typedef EgeonMessage = Map<String, Object?>;

enum EgeonLink { disconnected, connected }

/// O core Rust respondeu `ok: false` a um comando.
class EgeonCommandError implements Exception {
  EgeonCommandError(this.cmd, this.reply);

  final String cmd;
  final EgeonMessage reply;

  /// O motivo, no texto do core Rust.
  String get message => '${reply['error'] ?? 'O core recusou.'}';

  @override
  String toString() => 'EgeonCommandError($cmd): ${reply['error']}';
}

/// A conexão caiu antes da resposta chegar.
class EgeonDisconnected implements Exception {
  @override
  String toString() => 'EgeonDisconnected';
}

/// Para o repositório trocar as falhas do socket pelos erros do domínio dele:
/// a recusa do core leva o texto do core; a queda, nada.
extension EgeonFailures<T> on Future<T> {
  Future<T> failingAs({
    required Exception Function(String message) refused,
    required Exception Function() offline,
  }) async {
    try {
      return await this;
    } on EgeonCommandError catch (error) {
      throw refused(error.message);
    } on EgeonDisconnected {
      throw offline();
    }
  }
}

/// O único cliente do socket do core Rust. Nenhuma feature abre conexão.
///
/// Fala o canal `/ui`: um `GET /ui` com `Upgrade: egeon-ndjson`, a resposta
/// `101` e, dali em diante, uma mensagem JSON por linha. Comando
/// `{"id","cmd",…}` volta como `{"re":id,"ok",…}`; evento chega como
/// `{"topic",…}`. Se a conexão cai, o cliente reconecta sozinho e reassina
/// os tópicos abertos (o core manda o estado inteiro de novo).
class EgeonSocketClient {
  EgeonSocketClient(
    this._transport, {
    this.retryDelay = const Duration(milliseconds: 500),
  });

  final EgeonTransport _transport;
  final Duration retryDelay;

  final _events = StreamController<EgeonMessage>.broadcast();
  final _links = StreamController<EgeonLink>.broadcast();
  final _pending = <int, (String, Completer<EgeonMessage>)>{};
  final _topics = <String, int>{};

  EgeonConnection? _connection;
  final Completer<void> _firstConnection = Completer<void>();
  EgeonLink _link = EgeonLink.disconnected;
  var _nextId = 1;
  var _started = false;
  var _disposed = false;

  EgeonLink get link => _link;
  Stream<EgeonLink> get links => _links.stream;

  /// Completa na primeira vez que o canal `/ui` está aberto.
  Future<void> get whenConnected => _firstConnection.future;

  /// Liga o laço de conexão. Idempotente.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    unawaited(_run());
  }

  Future<void> dispose() async {
    _disposed = true;
    final connection = _connection;
    _connection = null;
    await connection?.close();
    _failPending();
    await _events.close();
    await _links.close();
  }

  Future<EgeonMessage> request(String cmd, [EgeonMessage args = const {}]) {
    final connection = _connection;
    if (connection == null) return Future.error(EgeonDisconnected());
    final id = _nextId++;
    final completer = Completer<EgeonMessage>();
    _pending[id] = (cmd, completer);
    _write(connection, {...args, 'id': id, 'cmd': cmd});
    return completer.future;
  }

  /// Eventos de um tópico. Assina ao primeiro ouvinte e desassina quando o
  /// último sai; reassina sozinho depois de uma reconexão.
  Stream<EgeonMessage> subscribe(String topic) {
    late StreamController<EgeonMessage> controller;
    StreamSubscription<EgeonMessage>? inner;
    controller = StreamController<EgeonMessage>(
      onListen: () {
        inner = _events.stream
            .where((m) => m['topic'] == topic)
            .listen(controller.add);
        _topics[topic] = (_topics[topic] ?? 0) + 1;
        // Toda assinatura nova pede o estado: o core manda o quadro inteiro a
        // cada `subscribe`, e um 2º ouvinte do mesmo tópico (um cubit que nasce
        // antes de o antigo fechar) ficaria em branco até o próximo quadro. O
        // estado que chega de novo vale também para os ouvintes que já estavam.
        if (_link == EgeonLink.connected) _sendSubscribe(topic);
      },
      onCancel: () async {
        await inner?.cancel();
        final left = (_topics[topic] ?? 1) - 1;
        if (left > 0) {
          _topics[topic] = left;
          return;
        }
        _topics.remove(topic);
        if (_link == EgeonLink.connected) _sendUnsubscribe(topic);
      },
    );
    return controller.stream;
  }

  // O formato exato de assinatura vem do core Rust; mudar só aqui.
  void _sendSubscribe(String topic) => unawaited(
    request('subscribe', {'topic': topic}).then((_) {}, onError: (_) {}),
  );

  void _sendUnsubscribe(String topic) => unawaited(
    request('unsubscribe', {'topic': topic}).then((_) {}, onError: (_) {}),
  );

  Future<void> _run() async {
    while (!_disposed) {
      try {
        await _session();
      } catch (_) {
        // Sem socket ainda ou conexão recusada: tenta de novo.
      }
      if (_disposed) return;
      await Future<void>.delayed(retryDelay);
    }
  }

  Future<void> _session() async {
    final connection = await _transport.open();
    final closed = Completer<void>();
    final decoder = NdjsonDecoder();
    final head = BytesBuilder();
    var upgraded = false;

    connection.input.listen(
      (chunk) {
        try {
          var body = chunk;
          if (!upgraded) {
            head.add(chunk);
            final bytes = head.toBytes();
            final end = _headerEnd(bytes);
            if (end < 0) return;
            final status = ascii.decode(
              bytes.sublist(0, end),
              allowInvalid: true,
            );
            if (!status.startsWith('HTTP/1.1 101')) {
              throw StateError(
                'upgrade recusado: ${status.split('\r\n').first}',
              );
            }
            upgraded = true;
            body = bytes.sublist(end + 4);
            _connection = connection;
            _setLink(EgeonLink.connected);
            if (!_firstConnection.isCompleted) _firstConnection.complete();
            for (final topic in _topics.keys) {
              _sendSubscribe(topic);
            }
          }
          for (final message in decoder.add(body)) {
            if (message is Map<String, Object?>) _dispatch(message);
          }
        } catch (_) {
          if (!closed.isCompleted) closed.complete();
        }
      },
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
      onError: (_) {
        if (!closed.isCompleted) closed.complete();
      },
      cancelOnError: true,
    );

    connection.write(
      ascii.encode(
        'GET /ui HTTP/1.1\r\nHost: egeon\r\nConnection: Upgrade\r\n'
        'Upgrade: egeon-ndjson\r\n\r\n',
      ),
    );

    await closed.future;
    if (identical(_connection, connection)) _connection = null;
    _setLink(EgeonLink.disconnected);
    _failPending();
    try {
      await connection.close();
    } catch (_) {}
  }

  void _dispatch(EgeonMessage message) {
    final re = message['re'];
    if (re is int) {
      final entry = _pending.remove(re);
      if (entry == null) return;
      final (cmd, completer) = entry;
      if (message['ok'] == false) {
        completer.completeError(EgeonCommandError(cmd, message));
      } else {
        completer.complete(message);
      }
      return;
    }
    if (message['topic'] is String && !_events.isClosed) _events.add(message);
  }

  void _write(EgeonConnection connection, EgeonMessage message) =>
      connection.write(utf8.encode('${jsonEncode(message)}\n'));

  void _setLink(EgeonLink link) {
    if (_link == link) return;
    _link = link;
    if (!_links.isClosed) _links.add(link);
  }

  void _failPending() {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final (_, completer) in pending) {
      completer.completeError(EgeonDisconnected());
    }
  }

  static int _headerEnd(Uint8List bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 &&
          bytes[i + 1] == 10 &&
          bytes[i + 2] == 13 &&
          bytes[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }
}
