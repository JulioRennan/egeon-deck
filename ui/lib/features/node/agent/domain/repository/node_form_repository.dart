import 'dart:ui';

import '../entities/node_form_submit.dart';
import '../entities/node_form_view.dart';
import '../entities/node_screen.dart';
import '../entities/node_template.dart';
import '../errors/agent_error.dart';

/// O formulário de terminal falando com o core Rust: quem decide o que a tela
/// mostra e o que se grava é ele. Falha como [AgentError].
abstract interface class NodeFormRepository {
  /// Abre o formulário: sem [nodeId], de terminal novo; com, do nó.
  Future<NodeFormView> open(String workbenchId, {String? nodeId});

  /// A tela para [cli], depois de guardar o que estava nela ([shown]).
  /// [config] é a escolhida agora no + do campo.
  Future<NodeScreen> screen(
    String workbenchId, {
    required NodeTemplate template,
    String? nodeId,
    ShownFields? shown,
    String? cli,
    String? config,
  });

  /// O + da pasta: como o nó grava [path].
  Future<FolderOption> folder(String workbenchId, String path);

  /// Cria o terminal; sem [frame], no primeiro lugar livre do que está à
  /// vista ([visible], no espaço do canvas). Devolve o id.
  Future<String> create(
    String workbenchId,
    NodeFormSubmit form, {
    Rect? frame,
    Rect? visible,
  });

  /// Aplica ao nó; devolve o id final (o nome pode ter mudado).
  Future<String> apply(String workbenchId, String nodeId, NodeFormSubmit form);

  /// Os componentes salvos, para o menu do botão Terminal.
  Future<List<ComponentInfo>> components();
}
