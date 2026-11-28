import 'dart:async';
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/node_form_submit.dart';
import '../../domain/entities/node_form_view.dart';
import '../../domain/entities/node_screen.dart';
import '../../domain/entities/node_template.dart';
import '../../domain/errors/agent_error.dart';
import '../../domain/usecase/node_form_actions.dart';

part 'node_form_state.dart';

/// Para onde o formulário vai: a bancada, o nó em edição (nulo é terminal
/// novo) e onde o terminal novo nasce (nulo é o primeiro lugar livre).
/// Onde o terminal novo nasce: no [frame] desenhado ou, sem ele, no primeiro
/// lugar livre do que está à vista ([visible]).
typedef NodeFormTarget = ({
  String workbenchId,
  String? nodeId,
  Rect? frame,
  Rect? visible,
});

/// Um cubit por formulário aberto. Pergunta ao core o que mostrar e devolve o
/// que está na tela; os campos digitados são do widget.
class NodeFormCubit extends Cubit<NodeFormState> {
  NodeFormCubit({required this.target, required this._actions})
    : super(const NodeFormOpening()) {
    unawaited(_open());
  }

  final NodeFormTarget target;
  final NodeFormActions _actions;

  String get _bench => target.workbenchId;

  /// Editar um nó (e não criar um).
  bool get editing => target.nodeId != null;

  Future<void> _open() async {
    try {
      final view = await _actions.open(_bench, nodeId: target.nodeId);
      if (isClosed) return;
      emit(
        NodeFormLoaded(
          view: view,
          screen: view.screen,
          cli: view.cli,
          folders: view.folders,
        ),
      );
    } on AgentError catch (error) {
      if (!isClosed) emit(NodeFormUnavailable(error));
    }
  }

  /// Marcou outro CLI: o core guarda o que estava na tela no que saiu e diz o
  /// que mostrar no que entra (ADR-057).
  Future<void> switchCli(String cli, ShownFields? shown) => _screen(
    (open) => _actions.screen(
      _bench,
      nodeId: target.nodeId,
      template: open.template,
      shown: shown,
      cli: cli,
    ),
    cli: cli,
  );

  /// O + da configuração: a pasta escolhida entra na lista, marcada.
  Future<void> pickConfig(String path, ShownFields? shown) => _screen(
    (open) => _actions.screen(
      _bench,
      nodeId: target.nodeId,
      template: open.template,
      shown: shown,
      cli: open.cli,
      config: path,
    ),
  );

  /// "Começar de outro": o componente salvo preenche o formulário inteiro.
  Future<void> startFrom(ComponentInfo component) async {
    final open = state;
    if (open is! NodeFormOpen) return;
    final keys = [for (final c in open.view.clis) c.key];
    final agent = component.template.agent;
    final cli = keys.contains(agent) ? agent : keys.firstOrNull;
    try {
      final screen = await _actions.screen(
        _bench,
        nodeId: target.nodeId,
        template: component.template,
        cli: cli,
      );
      if (isClosed) return;
      // A raiz está sempre na lista; a pasta do componente entra se não
      // estiver, com o próprio texto (só a raiz tem outro nome).
      final cwd = component.template.cwd ?? '';
      emit(
        NodeFormLoaded(
          view: open.view,
          screen: screen,
          cli: cli,
          folders: _withFolder(
            open.folders,
            FolderOption(value: cwd, shown: cwd),
          ),
        ),
      );
    } on AgentError catch (error) {
      _refuse(error);
    }
  }

  /// O + da pasta: o core diz como o nó grava a escolhida.
  Future<void> addFolder(String path) async {
    final open = state;
    if (open is! NodeFormOpen) return;
    try {
      final folder = await _actions.folder(_bench, path);
      if (isClosed) return;
      emit(
        NodeFormFolderAdded(
          view: open.view,
          screen: open.screen,
          cli: open.cli,
          folders: _withFolder(open.folders, folder),
          folder: folder.value,
        ),
      );
    } on AgentError catch (error) {
      _refuse(error);
    }
  }

  /// Criar ou aplicar. O que estava na tela do CLI vai junto.
  Future<void> confirm(
    FormFields fields, {
    ShownFields? shown,
    bool saveComponent = false,
  }) async {
    final open = state;
    if (open is! NodeFormOpen || open is NodeFormSaving) return;
    emit(
      NodeFormSaving(
        view: open.view,
        screen: open.screen,
        cli: open.cli,
        folders: open.folders,
      ),
    );
    try {
      final id = await _actions.confirm(
        _bench,
        NodeFormSubmit(
          template: open.template,
          fields: fields,
          shown: shown,
          saveComponent: saveComponent,
        ),
        nodeId: target.nodeId,
        frame: target.frame,
        visible: target.visible,
      );
      if (!isClosed) emit(NodeFormDone(id));
    } on AgentError catch (error) {
      _refuse(error);
    }
  }

  Future<void> _screen(
    Future<NodeScreen> Function(NodeFormOpen open) ask, {
    String? cli,
  }) async {
    final open = state;
    if (open is! NodeFormOpen) return;
    try {
      final screen = await ask(open);
      if (isClosed) return;
      emit(
        NodeFormSwitched(
          view: open.view,
          screen: screen,
          cli: cli ?? open.cli,
          folders: open.folders,
        ),
      );
    } on AgentError catch (error) {
      _refuse(error);
    }
  }

  void _refuse(AgentError error) {
    final open = state;
    if (isClosed || open is! NodeFormOpen) return;
    emit(
      NodeFormRefused(
        view: open.view,
        screen: open.screen,
        cli: open.cli,
        folders: open.folders,
        error: error,
      ),
    );
  }

  /// A lista com [folder], sem repetir: o que o + já tinha acrescentado fica.
  static List<FolderOption> _withFolder(
    List<FolderOption> folders,
    FolderOption folder,
  ) => folders.any((f) => f.value == folder.value)
      ? folders
      : [...folders, folder];
}
