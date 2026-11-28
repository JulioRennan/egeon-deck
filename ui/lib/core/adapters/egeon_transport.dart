import 'dart:io';

/// Uma conexão aberta com o core Rust: bytes entram, bytes saem.
abstract interface class EgeonConnection {
  Stream<List<int>> get input;
  void write(List<int> bytes);
  Future<void> close();
}

/// Quem sabe abrir a conexão. Existe para o cliente do socket poder ser
/// testado sem socket de verdade.
abstract interface class EgeonTransport {
  Future<EgeonConnection> open();
}

class UnixSocketTransport implements EgeonTransport {
  UnixSocketTransport(this.path);

  final String path;

  @override
  Future<EgeonConnection> open() async {
    final socket = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return _SocketConnection(socket);
  }
}

class _SocketConnection implements EgeonConnection {
  _SocketConnection(this._socket);

  final Socket _socket;

  @override
  Stream<List<int>> get input => _socket;

  @override
  void write(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> close() async {
    await _socket.close();
    _socket.destroy();
  }
}
