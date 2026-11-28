import 'dart:async';
import 'dart:typed_data';

import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_effect.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_frame.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_info.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_key.dart';
import 'package:egeon_deck/features/node/terminal/domain/entities/terminal_pointer.dart';
import 'package:egeon_deck/features/node/terminal/domain/repository/terminal_repository.dart';

/// Um terminal falso: o teste empurra quadros e lê o que a UI mandou.
class FakeTerminalRepository implements TerminalRepository {
  final _frames = StreamController<TerminalFrame>.broadcast();
  final keys = <TerminalKey>[];
  final texts = <String>[];
  final pastes = <String>[];
  final resizes = <(int, int)>[];
  final pointers = <TerminalPointer>[];
  final scrolls = <TerminalScroll>[];
  final clipboards = <String>[];
  var selectAlls = 0;
  final drops = <Object>[];
  final hovers = <(double, double)>[];

  /// O que o "core" responde ao ⌘-hover.
  bool linkUnderCursor = false;

  /// O que o "core" responde ao ⌘C.
  String? copied;
  final effectsController = StreamController<TerminalEffect>.broadcast();
  var watchers = 0;
  var created = 0;

  /// Terminais que o "core" falso diz ter; `create` acrescenta.
  final terminals = <TerminalInfo>[];

  @override
  Future<List<TerminalInfo>> list() async => List.of(terminals);

  @override
  Future<TerminalInfo> create({String? cwd}) async {
    created++;
    final info = TerminalInfo(
      id: 't$created',
      alive: true,
      columns: 80,
      rows: 24,
    );
    terminals.add(info);
    return info;
  }

  void push(TerminalFrame frame) => _frames.add(frame);

  @override
  Stream<TerminalFrame> watch(String nodeId) {
    late StreamController<TerminalFrame> controller;
    StreamSubscription<TerminalFrame>? inner;
    controller = StreamController<TerminalFrame>(
      onListen: () {
        watchers++;
        inner = _frames.stream.listen(controller.add);
      },
      onCancel: () {
        watchers--;
        return inner?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> sendKey(String nodeId, TerminalKey key) async => keys.add(key);

  @override
  Future<void> sendText(String nodeId, String text) async => texts.add(text);

  @override
  Future<void> paste(String nodeId, String text) async => pastes.add(text);

  @override
  Future<void> resize(String nodeId, int columns, int rows) async =>
      resizes.add((columns, rows));

  @override
  Future<void> sendPointer(String nodeId, TerminalPointer pointer) async =>
      pointers.add(pointer);

  @override
  Future<void> scroll(String nodeId, TerminalScroll scroll) async =>
      scrolls.add(scroll);

  @override
  Future<void> selectAll(String nodeId) async => selectAlls++;

  @override
  Future<String?> copy(String nodeId) async => copied;

  @override
  Stream<TerminalEffect> effects(String nodeId) => effectsController.stream;

  @override
  Future<void> sendClipboard(String nodeId, String text) async =>
      clipboards.add(text);

  @override
  Future<bool> linkHover(String nodeId, double x, double y) async {
    hovers.add((x, y));
    return linkUnderCursor;
  }

  @override
  Future<void> dropFiles(String nodeId, List<String> paths) async =>
      drops.add(paths);

  @override
  Future<void> dropImage(String nodeId, Uint8List png) async => drops.add(png);
}
