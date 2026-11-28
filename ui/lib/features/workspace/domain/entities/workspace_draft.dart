import '../../../../commons/utils/path_names.dart';

/// Um multi-projeto no formulário: um nome e as pastas que ele junta.
class MultiDraft {
  const MultiDraft({this.id, required this.name, this.folders = const []});

  /// Ausente quando é novo; o core dá o id ao salvar.
  final String? id;
  final String name;
  final List<String> folders;

  /// As pastas pelo último componente, juntas por " + ": o que a lista mostra
  /// ao lado do nome. O nome padrão, esse, é do core (`multi_name`).
  String get foldersLabel => folders.map(lastPathComponent).join(' + ');

  MultiDraft copyWith({String? name, List<String>? folders}) => MultiDraft(
    id: id,
    name: name ?? this.name,
    folders: folders ?? this.folders,
  );
}

/// O que o formulário de workspace edita: nome, ícone, pastas e multi-projetos.
class WorkspaceDraft {
  const WorkspaceDraft({
    this.name = '',
    this.icon,
    this.folders = const [],
    this.multis = const [],
    this.iconSource,
    this.clearIcon = false,
  });

  final String name;

  /// O ícone que o workspace já tem (caminho do arquivo).
  final String? icon;
  final List<String> folders;
  final List<MultiDraft> multis;

  /// A imagem nova escolhida, ainda não instalada.
  final String? iconSource;

  /// Tirar o ícone que já existia.
  final bool clearIcon;
}
