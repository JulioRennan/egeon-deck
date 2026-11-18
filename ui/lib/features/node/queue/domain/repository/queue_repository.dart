import 'dart:typed_data';

import '../entities/prompt_queue.dart';
import '../entities/queue_effect.dart';

/// Um print colado ou solto na fila: o nome que ele tinha e os bytes.
class PastedImage {
  const PastedImage({required this.name, required this.bytes, this.path});

  final String name;
  final Uint8List bytes;

  /// O arquivo de onde veio, quando veio de um: o core anexa por caminho.
  final String? path;
}

abstract interface class QueueRepository {
  /// A fila do nó [nodeId]. O core manda a fila inteira a cada mudança — a UI
  /// não aplica diferença.
  Stream<PromptQueue> watch(String nodeId);

  /// Rascunho e "abrir tarefa" vindos de fora.
  Stream<QueueEffect> effects(String nodeId);

  /// Devolve o id da tarefa criada. [after] põe a nova logo abaixo dela.
  Future<String> add(String nodeId, {String text = '', String? after});

  Future<void> update(String nodeId, String id, String text);
  Future<void> remove(String nodeId, String id);

  /// [to] conta só as linhas que ficaram no lugar.
  Future<void> move(String nodeId, String id, {required int to});

  /// Marca ou desmarca à mão: o checkbox da bolinha.
  Future<void> toggleDone(String nodeId, String id);

  /// Reabre uma tarefa fechada.
  Future<void> reopen(String nodeId, String id);

  /// Manda ao agente ligado. Devolve por que não foi (sem ligação, falha), ou
  /// nulo quando foi. Sem [id], a próxima pendente.
  Future<String?> send(String nodeId, {String? id});

  /// Responde a uma pergunta do agente, ou comenta. Mesmo retorno de [send].
  Future<String?> reply(String nodeId, String id, String text);

  Future<void> setAuto(String nodeId, {required bool on});
  Future<void> setTarget(String nodeId, String target);

  /// Tira da lista o que já foi.
  Future<void> clearDone(String nodeId);

  Future<void> attach(String nodeId, String id, List<PastedImage> images);

  /// Print solto: o core escolhe a tarefa — a [open], se ainda não foi
  /// enviada, senão uma em branco que ele cria — e devolve o id dela.
  Future<String> attachLoose(
    String nodeId,
    List<PastedImage> images, {
    String? open,
  });
  Future<void> detach(String nodeId, String id, String image);
}
