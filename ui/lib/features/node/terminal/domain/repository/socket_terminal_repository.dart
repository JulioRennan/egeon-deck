import 'dart:convert';
import 'dart:typed_data';

import '../../../../../core/adapters/egeon_socket_client.dart';
import '../entities/terminal_effect.dart';
import '../entities/terminal_frame.dart';
import '../entities/terminal_info.dart';
import '../entities/terminal_key.dart';
import '../entities/terminal_pointer.dart';
import 'terminal_repository.dart';

/// O terminal falando com o core Rust pelo cliente único do socket.
class SocketTerminalRepository implements TerminalRepository {
  const SocketTerminalRepository(this._client);

  final EgeonSocketClient _client;

  @override
  Future<List<TerminalInfo>> list() async {
    final reply = await _client.request('list_terminals');
    return [
      for (final t in reply['terminals']! as List<Object?>)
        TerminalInfo.fromMap(t! as Map<String, Object?>),
    ];
  }

  @override
  Future<TerminalInfo> create({String? cwd}) async {
    final reply = await _client.request('create_terminal', {'cwd': ?cwd});
    return TerminalInfo.fromMap(reply);
  }

  @override
  Stream<TerminalFrame> watch(String nodeId) => _client
      .subscribe('screen/$nodeId')
      // O tópico traz quadros e efeitos (bell, área de transferência) juntos.
      .where((event) => event['effect'] == null)
      .map(TerminalFrame.fromMap);

  @override
  Future<void> sendKey(String nodeId, TerminalKey key) =>
      _client.request('key', {'node': nodeId, ...key.toMap()});

  @override
  Future<void> sendText(String nodeId, String text) =>
      _client.request('input', {'node': nodeId, 'text': text});

  @override
  Future<void> paste(String nodeId, String text) =>
      _client.request('paste', {'node': nodeId, 'text': text});

  @override
  Future<void> resize(String nodeId, int columns, int rows) => _client.request(
    'resize',
    {'node': nodeId, 'cols': columns, 'rows': rows},
  );

  @override
  Future<void> sendPointer(String nodeId, TerminalPointer pointer) =>
      _client.request('pointer', {'node': nodeId, ...pointer.toMap()});

  @override
  Future<void> scroll(String nodeId, TerminalScroll scroll) =>
      _client.request('scroll', {'node': nodeId, 'to': scroll.toWire()});

  @override
  Future<void> selectAll(String nodeId) =>
      _client.request('select_all', {'node': nodeId});

  @override
  Future<String?> copy(String nodeId) async {
    final reply = await _client.request('copy', {'node': nodeId});
    return reply['text'] as String?;
  }

  @override
  Stream<TerminalEffect> effects(String nodeId) => _client
      .subscribe('screen/$nodeId')
      .where((event) => event['effect'] != null)
      .map(TerminalEffect.tryParse)
      .where((effect) => effect != null)
      .cast<TerminalEffect>();

  @override
  Future<void> sendClipboard(String nodeId, String text) =>
      _client.request('clipboard_reply', {'node': nodeId, 'text': text});

  @override
  Future<bool> linkHover(String nodeId, double x, double y) async {
    final reply = await _client.request('link_hover', {
      'node': nodeId,
      'x': x,
      'y': y,
    });
    return reply['link'] as bool? ?? false;
  }

  @override
  Future<void> dropFiles(String nodeId, List<String> paths) =>
      _client.request('drop', {'node': nodeId, 'paths': paths});

  @override
  Future<void> dropImage(String nodeId, Uint8List png) =>
      _client.request('drop', {'node': nodeId, 'png': base64Encode(png)});
}
