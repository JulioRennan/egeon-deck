import 'package:egeon_deck/core/adapters/path_picker.dart';

/// O seletor de pastas falso: o teste diz o que o usuário "escolheu".
class FakePathPicker implements PathPicker {
  List<String> nextFolders = const [];
  String? nextFolder;
  String? nextImage;
  final asked = <String>[];

  @override
  Future<List<String>> folders({
    String? prompt,
    String? initialDirectory,
  }) async {
    asked.add('pastas');
    return nextFolders;
  }

  @override
  Future<String?> folder({String? prompt, String? initialDirectory}) async {
    asked.add('pasta@$initialDirectory');
    return nextFolder;
  }

  @override
  Future<String?> image() async {
    asked.add('imagem');
    return nextImage;
  }
}
