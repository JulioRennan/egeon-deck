import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/standard_dialogs.dart';
import '../../../../core/adapters/egeon_socket_client.dart'
    show EgeonDisconnected;
import '../../../../core/domain/entities/command_failed.dart';
import '../../../workbench/domain/entities/bench_template.dart';
import '../../../workbench/domain/entities/removal_plan.dart';
import '../../../workbench/domain/usecase/bench_creation.dart';
import '../../../workbench/presentation/widgets/new_bench_form.dart';
import '../../../workbench/presentation/widgets/worktree_form.dart';
import '../../../workbench/domain/repository/workbench_repository.dart';
import '../../../workbench/domain/usecase/change_bench_color.dart';
import '../../../workbench/domain/usecase/clear_workbench.dart';
import '../../../workbench/domain/usecase/edit_workbench_rules.dart';
import '../../../workbench/domain/usecase/remove_workbench.dart';
import '../../../workbench/domain/usecase/rename_workbench.dart';
import '../../../workbench/presentation/widgets/color_palette_dialog.dart';
import '../../../workspace/domain/repository/workspace_repository.dart';
import '../../../workspace/domain/usecase/remove_workspace.dart' as usecase;
import '../../../workspace/domain/entities/workspace_draft.dart';
import '../../../workspace/domain/usecase/create_project.dart';
import '../../../workspace/domain/usecase/save_workspace.dart';
import '../../../workspace/presentation/widgets/new_project_form.dart';
import '../../../workspace/presentation/widgets/workspace_form.dart';
import '../../../../core/adapters/path_picker.dart';
import 'form_request.dart';

/// Atende os pedidos da casca abrindo a janela certa e mandando o resultado ao
/// core Rust. O que o core recusar volta como um aviso com o motivo dele.
///
/// [context] precisa estar abaixo do `Overlay` da casca.
Future<void> handleForm(BuildContext context, FormRequest request) async {
  switch (request) {
    case RecolorBench():
      return _recolor(context, request);
    case RenameBench():
      return _rename(context, request);
    case ClearBench():
      return _clear(context, request);
    case RemoveBench():
      return _removeBench(context, request);
    case EditBenchRules():
      return _rules(context, request);
    case RemoveWorkspace():
      return _removeWorkspace(context, request);
    case RemoveProject():
      return _removeProject(context, request);
    case NewWorkspace():
      return _workspaceForm(context, null);
    case EditWorkspace():
      return _workspaceForm(context, request);
    case NewProject():
      return _newProject(context, request);
    case NewBench(fromWorktree: false):
      return _newBench(context, request);
    case NewBench():
      // Worktree a partir de uma pasta, sem bancada de origem: o `worktree` do
      // core pede a bancada. Fica sem ação até o contrato dizer como.
      return;
    case DuplicateBench():
      return _duplicate(context, request);
  }
}

/// Roda o gesto e mostra o que deu errado: a recusa do core com o texto dele, e
/// qualquer outra falha (socket caído, resposta ilegível) com a mensagem dela.
Future<void> _guard(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } on Exception catch (failure) {
    if (!context.mounted) return;
    await messageDialog(
      context,
      title: 'Não foi possível',
      message: switch (failure) {
        CommandFailed(:final message) => message,
        EgeonDisconnected() => 'Sem conexão com o core. Tente de novo.',
        _ => '$failure',
      },
    );
  }
}

Future<void> _newBench(BuildContext context, NewBench request) async {
  final repository = context.read<WorkbenchRepository>();
  final picker = context.read<PathPicker>();
  var path = request.path;
  path ??= await picker.folder(prompt: 'Escolher');
  if (path == null || !context.mounted) return;
  var templates = const <BenchTemplate>[];
  await _guard(
    context,
    () async => templates = await ListTemplates(repository)(),
  );
  if (!context.mounted) return;
  final input = await showNewBenchForm(
    context,
    suggested: _folderName(path),
    templates: templates,
  );
  if (input == null || !context.mounted) return;
  await _guard(
    context,
    () => CreateWorkbench(repository)(
      path: path!,
      name: input.name,
      project: request.projectId,
      template: input.template,
    ),
  );
}

/// O último trecho do caminho: o nome que a bancada leva se nada for digitado.
String _folderName(String path) {
  final parts = path.split('/').where((part) => part.isNotEmpty);
  return parts.isEmpty ? 'bancada' : parts.last;
}

Future<void> _duplicate(BuildContext context, DuplicateBench request) async {
  final actions = WorktreeActions(context.read<WorkbenchRepository>());
  final input = await showWorktreeForm(
    context,
    benchId: request.benchId,
    benchName: request.benchName,
    actions: actions,
  );
  if (input == null || !context.mounted) return;
  await _guard(
    context,
    () => actions.create(
      request.benchId,
      input.branch,
      destination: input.destination,
      nodes: input.nodes,
    ),
  );
}

Future<void> _recolor(BuildContext context, RecolorBench request) async {
  final change = ChangeBenchColor(context.read<WorkbenchRepository>());
  final picked = await showColorPalette(context, current: request.current);
  if (picked == null || !context.mounted) return;
  await _guard(context, () => change(request.benchId, picked));
}

Future<void> _rename(BuildContext context, RenameBench request) async {
  final rename = RenameWorkbench(context.read<WorkbenchRepository>());
  final name = request.benchName;
  final typed = await promptDialog(
    context,
    title: 'Renomear bancada',
    message:
        '"$name" é a primeira parte do endereço de dispatch ($name/…). Os '
        'alvos abertos passam a atender pelo nome novo.',
    confirmLabel: 'Renomear',
    initial: name,
  );
  if (typed == null || typed == name || !context.mounted) return;
  await _guard(context, () => rename(request.benchId, typed));
}

Future<void> _clear(BuildContext context, ClearBench request) async {
  final clear = ClearWorkbench(context.read<WorkbenchRepository>());
  int? asked;
  await _guard(
    context,
    () async => asked = await clear.agents(request.benchId),
  );
  final agents = asked;
  if (agents == null || !context.mounted) return;
  final plural = agents == 1 ? '' : 's';
  final confirmed = await confirmDialog(
    context,
    title: 'Limpar a bancada "${request.benchName}"?',
    message:
        'Roda o comando de limpar em $agents agente$plural — eles esquecem a '
        'conversa atual — e arquiva o chat e a trilha da bancada em '
        'chat-archive/ e trace-archive/. Nada é apagado do disco.',
    confirmLabel: 'Limpar',
  );
  if (!confirmed || !context.mounted) return;
  await _guard(context, () => clear(request.benchId));
}

Future<void> _removeBench(BuildContext context, RemoveBench request) async {
  final remove = RemoveWorkbench(context.read<WorkbenchRepository>());
  RemovalPlan? asked;
  await _guard(context, () async => asked = await remove.plan(request.benchId));
  final plan = asked;
  if (plan == null || !context.mounted) return;
  final title = 'Remover a bancada "${request.benchName}"?';
  final message = plan.live
      ? 'Os terminais abertos são encerrados.'
      : 'A bancada sai da lista.';
  var deleteWorktrees = false;
  if (plan.worktrees > 0) {
    final answer = await confirmWithOptionDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'Remover',
      destructive: true,
      optionLabel: plan.worktrees == 1
          ? 'Também apagar a worktree do disco'
          : 'Também apagar as ${plan.worktrees} worktrees do disco',
    );
    if (!answer.confirmed) return;
    deleteWorktrees = answer.option;
  } else {
    final confirmed = await confirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (!confirmed) return;
  }
  if (!context.mounted) return;
  await _guard(
    context,
    () => remove(request.benchId, deleteWorktrees: deleteWorktrees),
  );
}

Future<void> _rules(BuildContext context, EditBenchRules request) async {
  final rules = EditWorkbenchRules(context.read<WorkbenchRepository>());
  String? asked;
  await _guard(
    context,
    () async => asked = await rules.current(request.benchId),
  );
  final current = asked;
  if (current == null || !context.mounted) return;
  final typed = await textAreaDialog(
    context,
    title: 'Regras — ${request.benchName}',
    message:
        'Como se trabalha nesta bancada. Vale para todo agente que abre aqui, '
        'somado às regras de cada terminal, e entra no system prompt depois '
        'do papel — quando um pedido conflita com uma regra, vale a regra.\n\n'
        'Uma por linha, curtas, dizendo o que FAZER ("peça antes de commitar" '
        'adere muito melhor que "não commite") e o porquê quando não for '
        'óbvio. Poucas: regra demais dilui todas.',
    confirmLabel: 'Salvar',
    initial: current,
  );
  if (typed == null || typed == current.trim() || !context.mounted) return;
  await _guard(context, () => rules.save(request.benchId, typed));
}

/// Pergunta ao core se aceitaria; só então confirma com o usuário. Recusa (com
/// bancadas dentro, por exemplo) é o que se mostra, sem confirmação nenhuma.
Future<bool> _accepted(
  BuildContext context,
  Future<void> Function() check,
) async {
  var ok = false;
  await _guard(context, () async {
    await check();
    ok = true;
  });
  return ok && context.mounted;
}

Future<void> _removeWorkspace(
  BuildContext context,
  RemoveWorkspace request,
) async {
  final remove = usecase.RemoveWorkspace(context.read<WorkspaceRepository>());
  if (!await _accepted(
    context,
    () => remove.checkWorkspace(request.workspaceId),
  )) {
    return;
  }
  if (!context.mounted) return;
  final confirmed = await confirmDialog(
    context,
    title: 'Remover o workspace "${request.workspaceName}"?',
    message: 'Só a organização some; nenhuma pasta é tocada.',
    confirmLabel: 'Remover',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  await _guard(context, () => remove.workspace(request.workspaceId));
}

Future<void> _removeProject(BuildContext context, RemoveProject request) async {
  final remove = usecase.RemoveWorkspace(context.read<WorkspaceRepository>());
  if (!await _accepted(
    context,
    () => remove.checkProject(request.workspaceId, request.projectId),
  )) {
    return;
  }
  if (!context.mounted) return;
  final confirmed = await confirmDialog(
    context,
    title: 'Tirar "${request.projectName}" de "${request.workspaceName}"?',
    message: 'A pasta ${request.projectPath} não é tocada.',
    confirmLabel: 'Tirar',
    destructive: true,
  );
  if (!confirmed || !context.mounted) return;
  await _guard(
    context,
    () => remove.project(request.workspaceId, request.projectId),
  );
}

Future<void> _workspaceForm(BuildContext context, EditWorkspace? edit) async {
  final workspaces = context.read<WorkspaceRepository>();
  final picker = context.read<PathPicker>();
  final save = SaveWorkspace(workspaces);
  var initial = const WorkspaceDraft();
  if (edit != null) {
    WorkspaceDraft? loaded;
    await _guard(
      context,
      () async => loaded = await save.draft(edit.workspaceId),
    );
    if (loaded == null || !context.mounted) return;
    initial = loaded!;
  }
  final draft = await showWorkspaceForm(
    context,
    initial: initial,
    editing: edit != null,
    picker: picker,
    suggestName: (folders) => save.multiName(edit?.workspaceId, folders),
  );
  if (draft == null || !context.mounted) return;
  await _guard(context, () => save(draft, id: edit?.workspaceId));
}

Future<void> _newProject(BuildContext context, NewProject request) async {
  final create = CreateProject(context.read<WorkspaceRepository>());
  final picker = context.read<PathPicker>();
  String? suggested;
  await _guard(
    context,
    () async => suggested = await create.suggestedParent(request.workspaceId),
  );
  var parent = suggested;
  if (parent == null || !context.mounted) return;
  var name = '';
  var git = true;
  String? problem;
  while (true) {
    final input = await showNewProjectForm(
      context,
      workspaceName: request.workspaceName,
      parent: parent!,
      picker: picker,
      name: name,
      git: git,
      problem: problem,
    );
    if (input == null || !context.mounted) return;
    name = input.name;
    parent = input.parent;
    git = input.git;
    try {
      await create(
        request.workspaceId,
        name: input.name,
        parent: input.parent,
        git: input.git,
      );
      return;
    } on CommandFailed catch (failure) {
      problem = failure.message;
    }
    if (!context.mounted) return;
  }
}
