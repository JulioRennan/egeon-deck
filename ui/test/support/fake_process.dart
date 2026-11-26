import 'dart:async';
import 'dart:io';

/// O filho que o lançador criaria: registra se foi encerrado e se o stdin
/// foi fechado. O core "sai" quando [exit] é chamado.
class FakeProcess implements Process {
  bool killed = false;
  final _sink = _FakeSink();
  final _exit = Completer<int>();

  bool get stdinClosed => _sink.closed;

  /// O core terminou por conta própria.
  void exit([int code = 0]) => _exit.complete(code);

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => _sink;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => killed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements IOSink {
  bool closed = false;

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
