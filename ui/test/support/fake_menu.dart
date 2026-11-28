import 'package:egeon_deck/core/adapters/app_windows.dart';
import 'package:egeon_deck/core/adapters/clipboard_writer.dart';
import 'package:egeon_deck/features/home/domain/repository/menu_repository.dart';

/// Os alvos que o "core" diz ter.
class FakeMenuRepository implements MenuRepository {
  FakeMenuRepository([this.targets = '']);

  String targets;

  @override
  Future<String> dispatchTargets() async => targets;
}

/// A área de transferência guardada numa lista, em vez da do sistema.
class FakeClipboard implements ClipboardWriter {
  final written = <String>[];

  @override
  Future<void> write(String text) async => written.add(text);
}

/// As janelas que a casca pediu para abrir, sem abrir nenhuma.
class FakeAppWindows implements AppWindows {
  final opened = <WindowArguments>[];

  @override
  Future<void> open(WindowArguments arguments) async => opened.add(arguments);
}
