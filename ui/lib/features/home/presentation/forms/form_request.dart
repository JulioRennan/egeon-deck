/// Um pedido de formulário ou confirmação que nasce na casca (clique numa
/// linha, item de menu) e é atendido por quem abre as janelas. Leva só o que a
/// janela precisa mostrar; o resto o core Rust decide.
sealed class FormRequest {
  const FormRequest();
}

class NewWorkspace extends FormRequest {
  const NewWorkspace();
}

class EditWorkspace extends FormRequest {
  const EditWorkspace(this.workspaceId, this.workspaceName);

  final String workspaceId;
  final String workspaceName;
}

class NewProject extends FormRequest {
  const NewProject(this.workspaceId, this.workspaceName);

  final String workspaceId;
  final String workspaceName;
}

class RemoveWorkspace extends FormRequest {
  const RemoveWorkspace(this.workspaceId, this.workspaceName);

  final String workspaceId;
  final String workspaceName;
}

class RemoveProject extends FormRequest {
  const RemoveProject({
    required this.workspaceId,
    required this.workspaceName,
    required this.projectId,
    required this.projectName,
    required this.projectPath,
  });

  final String workspaceId;
  final String workspaceName;
  final String projectId;
  final String projectName;
  final String projectPath;
}

/// Bancada nova; sem [projectId] é "por pasta livre" e a pasta se escolhe na
/// hora. [fromWorktree] abre o formulário de worktree em vez do comum.
class NewBench extends FormRequest {
  const NewBench({this.projectId, this.path, this.fromWorktree = false});

  final String? projectId;

  /// A pasta do projeto, quando se cria dentro de um.
  final String? path;
  final bool fromWorktree;
}

/// Pedidos sobre uma bancada que já existe: o id e o nome que a janela cita.
sealed class BenchRequest extends FormRequest {
  const BenchRequest(this.benchId, this.benchName);

  final String benchId;
  final String benchName;
}

class RenameBench extends BenchRequest {
  const RenameBench(super.benchId, super.benchName);
}

class DuplicateBench extends BenchRequest {
  const DuplicateBench(super.benchId, super.benchName);
}

class EditBenchRules extends BenchRequest {
  const EditBenchRules(super.benchId, super.benchName);
}

class ClearBench extends BenchRequest {
  const ClearBench(super.benchId, super.benchName);
}

class RemoveBench extends BenchRequest {
  const RemoveBench(super.benchId, super.benchName);
}

/// A cor que a bancada tem hoje, para a grade marcá-la.
class RecolorBench extends BenchRequest {
  const RecolorBench(super.benchId, super.benchName, {this.current});

  final String? current;
}

/// "Salvar este canvas como um template novo".
class SaveAsTemplate extends BenchRequest {
  const SaveAsTemplate(super.benchId, super.benchName);
}

/// "Atualizar o template de origem com este canvas".
class UpdateOriginTemplate extends BenchRequest {
  const UpdateOriginTemplate(super.benchId, super.benchName);
}
