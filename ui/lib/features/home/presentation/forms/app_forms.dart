import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/form_dialog.dart';
import '../../../../core/adapters/injector.dart';
import '../../../workbench/domain/entities/bench_template.dart';
import '../../../workbench/domain/errors/workbench_error.dart';
import '../../../workspace/domain/errors/workspace_error.dart';
import '../../../workbench/domain/entities/removal_plan.dart';
import '../../../workbench/domain/entities/template_plan.dart';
import '../../../workbench/domain/entities/worktree_info.dart';
import '../../../workbench/domain/entities/worktree_source.dart';
import '../../../workbench/domain/usecase/save_bench_template.dart';
import '../../../workbench/presentation/widgets/multi_worktree_form.dart';
import '../../../workbench/domain/usecase/bench_creation.dart';
import '../../../workbench/presentation/widgets/new_bench_form.dart';
import '../../../workbench/presentation/widgets/worktree_form.dart';
import '../../../workbench/domain/usecase/change_bench_color.dart';
import '../../../workbench/domain/usecase/clear_workbench.dart';
import '../../../workbench/domain/usecase/edit_workbench_rules.dart';
import '../../../workbench/domain/usecase/remove_workbench.dart';
import '../../../workbench/domain/usecase/rename_workbench.dart';
import '../../../workbench/presentation/widgets/color_palette_dialog.dart';
import '../../../workspace/domain/usecase/remove_workspace.dart' as usecase;
import '../../../workspace/domain/entities/workspace_draft.dart';
import '../../../workspace/domain/entities/workspace_saved.dart';
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
      return _benchFromWorktree(context, request);
    case DuplicateBench():
      return _openWorktree(
        context,
        WorktreeSource.bench(request.benchId),
        benchName: request.benchName,
      );
    case SaveAsTemplate():
      return _saveTemplate(context, request);
    case UpdateOriginTemplate():
      return _updateTemplate(context, request);
  }
}

/// Roda o gesto e mostra o que deu errado: a recusa do core com o texto dele,
/// e a queda do socket.
Future<void> _guard(
  BuildContext context,
  Future<void> Function() action, {
  String title = 'Não foi possível',
}) async {
  final String message;
  try {
    await action();
    return;
  } on WorkbenchError catch (failure) {
    message = switch (failure) {
      WorkbenchRefused(:final message) => message,
      WorkbenchOffline() => _offline,
    };
  } on WorkspaceError catch (failure) {
    message = switch (failure) {
      WorkspaceRefused(:final message) => message,
      WorkspaceOffline() => _offline,
    };
  }
  if (!context.mounted) return;
  await messageDialog(context, title: title, message: message);
}

const _offline = 'Sem conexão com o core. Tente de novo.';

Future<void> _newBench(BuildContext context, NewBench request) async {
  var path = request.path;
  path ??= await inject<PathPicker>().folder(prompt: 'Escolher');
  if (path == null || !context.mounted) return;
  var templates = const <BenchTemplate>[];
  await _guard(
    context,
    () async => templates = await inject<ListTemplates>()(),
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
    () => inject<CreateWorkbench>()(
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

/// "Nova bancada a partir de worktree…": do projeto, ou de um repositório
/// escolhido na hora (`createWorkbenchFromWorktree`).
Future<void> _benchFromWorktree(BuildContext context, NewBench request) async {
  final project = request.projectId;
  if (project != null) {
    return _openWorktree(context, WorktreeSource.folder(project: project));
  }
  final path = await inject<PathPicker>().folder(
    prompt: 'Usar este repositório',
  );
  if (path == null || !context.mounted) return;
  return _openWorktree(context, WorktreeSource.folder(path: path));
}

/// O formulário de worktree certo para a origem: o de um campo por
/// repositório em multi-projeto, o comum no resto. O core lê o repositório
/// antes de abrir: pasta fora do git avisa já, não no "Abrir".
Future<void> _openWorktree(
  BuildContext context,
  WorktreeSource source, {
  String? benchName,
}) async {
  final actions = inject<WorktreeActions>();
  WorktreeInfo? read;
  await _guard(
    context,
    () async => read = await actions.info(source),
    title: benchName == null
        ? 'Não consegui ler o repositório'
        : '"$benchName" não é um repositório git',
  );
  final info = read;
  if (info == null || !context.mounted) return;
  var templates = const <BenchTemplate>[];
  if (!source.hasOrigin) {
    await _guard(
      context,
      () async => templates = await inject<ListTemplates>()(),
    );
    if (!context.mounted) return;
  }
  final multi = info.multi;
  if (multi != null) {
    return _multiWorktree(context, source, multi, templates);
  }
  final input = await showWorktreeForm(
    context,
    source: source,
    title: 'Worktree de ${info.repo.isEmpty ? benchName ?? '' : info.repo}',
    info: info,
    templates: templates,
  );
  if (input == null || !context.mounted) return;
  await _guard(
    context,
    () => actions.create(
      source,
      input.branch,
      destination: input.destination,
      nodes: input.nodes,
      template: input.template,
    ),
    title: 'Não consegui criar a worktree',
  );
}

/// Multi-projeto: a mesma branch em cada repositório, salvo a que se trocou.
/// Repositório que recusa não derruba os outros; o aviso diz o que faltou.
Future<void> _multiWorktree(
  BuildContext context,
  WorktreeSource source,
  MultiWorktree multi,
  List<BenchTemplate> templates,
) async {
  final input = await showMultiWorktreeForm(
    context,
    multi: multi,
    templates: source.hasOrigin ? null : templates,
  );
  if (input == null || !context.mounted) return;
  WorktreeCreated? made;
  await _guard(
    context,
    () async => made = await inject<WorktreeActions>().create(
      source,
      input.branch,
      repos: input.repos,
      template: input.template,
    ),
    title: 'Nenhuma worktree foi criada',
  );
  final failed = made?.failed ?? const [];
  if (failed.isEmpty || !context.mounted) return;
  await messageDialog(
    context,
    title: 'Algumas worktrees ficaram de fora',
    message: failed.join('\n'),
  );
}

Future<void> _recolor(BuildContext context, RecolorBench request) async {
  final change = inject<ChangeBenchColor>();
  final picked = await showColorPalette(
    context,
    benchName: request.benchName,
    current: request.current,
  );
  if (picked == null || !context.mounted) return;
  await _guard(context, () => change(request.benchId, picked));
}

Future<void> _rename(BuildContext context, RenameBench request) async {
  final rename = inject<RenameWorkbench>();
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
  final clear = inject<ClearWorkbench>();
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

/// Remoções em qualquer passo — levantando, no diálogo, conferindo, apagando:
/// o segundo clique em "Remover" não abre um segundo diálogo
/// (`removalInFlight`). Estado de tela, por janela: preso ao `Overlay` onde
/// os diálogos se abrem, morre com ele.
final _removalInFlight = Expando<Set<String>>();

Future<void> _removeBench(BuildContext context, RemoveBench request) async {
  final inFlight = _removalInFlight[Overlay.of(context)] ??= <String>{};
  if (!inFlight.add(request.benchId)) return;
  try {
    await _askRemoveBench(context, request);
  } finally {
    inFlight.remove(request.benchId);
  }
}

Future<void> _askRemoveBench(BuildContext context, RemoveBench request) async {
  final remove = inject<RemoveWorkbench>();
  RemovalPlan? asked;
  await _guard(context, () async => asked = await remove.plan(request.benchId));
  final plan = asked;
  if (plan == null || !context.mounted) return;
  final title = 'Remover a bancada "${request.benchName}"?';
  var message = plan.live
      ? 'Os terminais abertos são encerrados.'
      : 'A bancada sai da lista.';
  // TODAS as worktrees da bancada, e não só a pasta dela: com worktree por
  // terminal, uma bancada pode ter aberto worktree em vários repositórios.
  final deletable = plan.deletable;
  var deleteWorktrees = false;
  if (deletable.isNotEmpty) {
    final lines = [
      for (final wt in plan.worktrees)
        wt.usedBy == null
            ? '${wt.repo} · ${wt.branch ?? '?'} · ${wt.owners.join(', ')}'
            : '${wt.repo} · ${wt.branch ?? '?'} · MANTIDA, é a bancada '
                  '"${wt.usedBy}"',
      'Desmarcado, as pastas ficam onde estão e você pode reabri-las.',
    ];
    final answer = await confirmWithOptionDialog(
      context,
      title: title,
      message: message,
      confirmLabel: 'Remover',
      destructive: true,
      optionLabel: deletable.length == 1
          ? 'Também apagar a worktree do disco'
          : 'Também apagar as ${deletable.length} worktrees do disco',
      optionHint: lines.join('\n'),
    );
    if (!answer.confirmed) return;
    deleteWorktrees = answer.option;
  } else {
    // Tudo o que ela usa é pasta de outra bancada: apagar levaria trabalho de
    // quem não foi consultado.
    message += plan.worktrees.isEmpty
        ? ' Nenhuma pasta é tocada.'
        : ' As worktrees dela são de outras bancadas e ficam.';
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
  // Segundo passo, só quando há trabalho a perder: o core apaga com
  // `--force`, e forçar sem mostrar o que morre seria apagar às escuras. O
  // `git status` só corre agora, com a caixa marcada: com `node_modules`
  // demora, e o core cobre a bancada com "Conferindo o que se perde…".
  var losses = const <String>[];
  if (deleteWorktrees) {
    var checked = false;
    await _guard(context, () async {
      losses = await remove.losses(request.benchId);
      checked = true;
    }, title: 'A bancada não foi removida');
    if (!checked || !context.mounted) return;
  }
  if (losses.isNotEmpty) {
    final confirmed = await confirmDialog(
      context,
      title: 'Isto apaga trabalho não commitado',
      message: losses.join('\n'),
      confirmLabel: 'Apagar mesmo assim',
      destructive: true,
      // As linhas de arquivo são longas: estreita, cada uma quebraria em duas.
      width: 460,
    );
    if (!confirmed || !context.mounted) return;
  }
  await _guard(
    context,
    () => remove(request.benchId, deleteWorktrees: deleteWorktrees),
    title: deleteWorktrees ? 'A bancada não foi removida' : 'Não foi possível',
  );
}

/// "Salvar este canvas como um template novo": o nome sugerido é o da
/// bancada, e não o do template de origem — atualizar esse é o outro botão.
Future<void> _saveTemplate(BuildContext context, SaveAsTemplate request) async {
  final save = inject<SaveBenchTemplate>();
  TemplatePlan? asked;
  await _guard(
    context,
    () async =>
        asked = await save.plan(request.benchId, name: request.benchName),
  );
  final plan = asked;
  if (plan == null || !context.mounted) return;
  if (plan.empty) {
    return messageDialog(
      context,
      title: 'Canvas vazio',
      message: 'Monte os nós que você quer no preset e salve de novo.',
    );
  }
  final typed = await promptDialog(
    context,
    title: 'Salvar como template',
    message: plan.summary,
    confirmLabel: 'Salvar',
    initial: request.benchName,
    placeholder: 'nome do template',
  );
  final name = typed?.trim() ?? '';
  if (name.isEmpty || !context.mounted) return;
  TemplatePlan? named;
  await _guard(
    context,
    () async => named = await save.plan(request.benchId, name: name),
  );
  final existing = named;
  if (existing == null || !context.mounted) return;
  if (existing.exists) {
    final replace = await confirmDialog(
      context,
      title: 'Já existe um template "$name"',
      message: 'Substituir pelo canvas atual?',
      confirmLabel: 'Substituir',
    );
    if (!replace || !context.mounted) return;
  }
  await _guard(context, () => save(request.benchId, name: name));
}

/// Regrava o template de que a bancada nasceu. As que já nasceram dele não
/// mudam: os valores foram copiados na criação.
Future<void> _updateTemplate(
  BuildContext context,
  UpdateOriginTemplate request,
) async {
  final save = inject<SaveBenchTemplate>();
  TemplatePlan? asked;
  await _guard(context, () async => asked = await save.plan(request.benchId));
  final plan = asked;
  final name = plan?.template;
  if (plan == null || name == null || !context.mounted) return;
  if (plan.empty) {
    return messageDialog(
      context,
      title: 'Canvas vazio',
      message:
          'Um template sem nós não abre nada. Monte o canvas e atualize de '
          'novo.',
    );
  }
  if (!plan.exists) {
    return messageDialog(
      context,
      title: 'O template "$name" não existe mais',
      message: 'Use "salvar como template" para criá-lo de novo.',
    );
  }
  final confirmed = await confirmDialog(
    context,
    title: 'Atualizar o template "$name"?',
    message:
        '${plan.summary}\n\nAs bancadas que já nasceram deste template não '
        'mudam.',
    confirmLabel: 'Atualizar',
  );
  if (!confirmed || !context.mounted) return;
  await _guard(context, () => save(request.benchId));
}

Future<void> _rules(BuildContext context, EditBenchRules request) async {
  final rules = inject<EditWorkbenchRules>();
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
  final remove = inject<usecase.RemoveWorkspace>();
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
  final remove = inject<usecase.RemoveWorkspace>();
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
  final save = inject<SaveWorkspace>();
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
    picker: inject<PathPicker>(),
    suggestName: (folders) => save.multiName(edit?.workspaceId, folders),
  );
  if (draft == null || !context.mounted) return;
  WorkspaceSaved? saved;
  await _guard(
    context,
    () async => saved = await save(draft, id: edit?.workspaceId),
  );
  final outcome = saved;
  if (outcome == null) return;
  final warning = outcome.warning;
  if (warning != null && context.mounted) {
    await messageDialog(
      context,
      title: 'Não consegui copiar a imagem',
      message: warning,
    );
  }
  // O projeto que tem bancada não sai: virariam órfãs sem você pedir.
  if (outcome.refused.isNotEmpty && context.mounted) {
    await messageDialog(
      context,
      title: 'Projeto com bancadas fica',
      message: 'Remova antes as bancadas de: ${outcome.refused.join(', ')}.',
    );
  }
}

Future<void> _newProject(BuildContext context, NewProject request) async {
  final create = inject<CreateProject>();
  final picker = inject<PathPicker>();
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
    } on WorkspaceRefused catch (failure) {
      problem = failure.message;
    }
    if (!context.mounted) return;
  }
}
