import 'dart:typed_data';

import '../entities/terminal_key.dart';
import '../entities/terminal_pointer.dart';
import '../repository/terminal_repository.dart';

class SendTerminalInput {
  const SendTerminalInput(this._repository);

  final TerminalRepository _repository;

  Future<void> key(String nodeId, TerminalKey key) =>
      _repository.sendKey(nodeId, key);

  Future<void> text(String nodeId, String text) =>
      _repository.sendText(nodeId, text);

  Future<void> paste(String nodeId, String text) =>
      _repository.paste(nodeId, text);

  Future<void> pointer(String nodeId, TerminalPointer pointer) =>
      _repository.sendPointer(nodeId, pointer);

  Future<void> scroll(String nodeId, TerminalScroll scroll) =>
      _repository.scroll(nodeId, scroll);

  Future<void> selectAll(String nodeId) => _repository.selectAll(nodeId);

  Future<String?> copy(String nodeId) => _repository.copy(nodeId);

  Future<void> clipboard(String nodeId, String text) =>
      _repository.sendClipboard(nodeId, text);

  Future<bool> linkHover(String nodeId, double x, double y) =>
      _repository.linkHover(nodeId, x, y);

  Future<void> dropFiles(String nodeId, List<String> paths) =>
      _repository.dropFiles(nodeId, paths);

  Future<void> dropImage(String nodeId, Uint8List png) =>
      _repository.dropImage(nodeId, png);
}
