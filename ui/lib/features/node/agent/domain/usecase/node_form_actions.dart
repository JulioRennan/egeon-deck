import 'dart:ui';

import '../entities/node_form_submit.dart';
import '../entities/node_form_view.dart';
import '../entities/node_screen.dart';
import '../entities/node_template.dart';
import '../repository/node_form_repository.dart';

/// O formulário de terminal de uma bancada: abrir, trocar de CLI, escolher
/// pasta e confirmar. Sem regra aqui: o core decide.
class NodeFormActions {
  const NodeFormActions(this._repository);

  final NodeFormRepository _repository;

  Future<NodeFormView> open(String workbenchId, {String? nodeId}) =>
      _repository.open(workbenchId, nodeId: nodeId);

  Future<NodeScreen> screen(
    String workbenchId, {
    required NodeTemplate template,
    String? nodeId,
    ShownFields? shown,
    String? cli,
    String? config,
  }) => _repository.screen(
    workbenchId,
    template: template,
    nodeId: nodeId,
    shown: shown,
    cli: cli,
    config: config,
  );

  Future<FolderOption> folder(String workbenchId, String path) =>
      _repository.folder(workbenchId, path);

  /// Cria o terminal ou aplica ao nó, conforme [nodeId]. Devolve o id final.
  Future<String> confirm(
    String workbenchId,
    NodeFormSubmit form, {
    String? nodeId,
    Rect? frame,
    Rect? visible,
  }) => nodeId == null
      ? _repository.create(workbenchId, form, frame: frame, visible: visible)
      : _repository.apply(workbenchId, nodeId, form);
}
