part of 'node_form_cubit.dart';

/// O formulário de terminal, fase por fase.
sealed class NodeFormState {
  const NodeFormState();
}

/// Perguntando ao core o que mostrar.
final class NodeFormOpening extends NodeFormState {
  const NodeFormOpening();
}

/// O core não abriu o formulário.
final class NodeFormUnavailable extends NodeFormState {
  const NodeFormUnavailable(this.error);

  final AgentError error;
}

/// O formulário na tela: o que o core mandou ao abrir, a tela do CLI marcado
/// e a lista de pastas (com as que o + acrescentou).
sealed class NodeFormOpen extends NodeFormState {
  const NodeFormOpen({
    required this.view,
    required this.screen,
    required this.cli,
    required this.folders,
  });

  final NodeFormView view;
  final NodeScreen screen;
  final String? cli;
  final List<FolderOption> folders;

  /// O componente como está agora, com o que cada CLI tem.
  NodeTemplate get template => screen.template;
}

/// Um componente entrou inteiro: ao abrir e ao escolher um em "Começar de
/// outro". Todos os campos voltam aos dele.
final class NodeFormLoaded extends NodeFormOpen {
  const NodeFormLoaded({
    required super.view,
    required super.screen,
    required super.cli,
    required super.folders,
  });
}

/// A tela do CLI mudou — outro CLI, ou a configuração do +. Só os campos do
/// CLI voltam; nome, pasta e tipo ficam como você deixou.
final class NodeFormSwitched extends NodeFormOpen {
  const NodeFormSwitched({
    required super.view,
    required super.screen,
    required super.cli,
    required super.folders,
  });
}

/// Uma pasta entrou na lista pelo + e fica marcada.
final class NodeFormFolderAdded extends NodeFormOpen {
  const NodeFormFolderAdded({
    required super.view,
    required super.screen,
    required super.cli,
    required super.folders,
    required this.folder,
  });

  final String folder;
}

/// Confirmado, esperando o core criar ou aplicar.
final class NodeFormSaving extends NodeFormOpen {
  const NodeFormSaving({
    required super.view,
    required super.screen,
    required super.cli,
    required super.folders,
  });
}

/// O core recusou um pedido; o formulário continua aberto.
final class NodeFormRefused extends NodeFormOpen {
  const NodeFormRefused({
    required super.view,
    required super.screen,
    required super.cli,
    required super.folders,
    required this.error,
  });

  final AgentError error;
}

/// Criado ou aplicado: [nodeId] é o id final do nó.
final class NodeFormDone extends NodeFormState {
  const NodeFormDone(this.nodeId);

  final String nodeId;
}
