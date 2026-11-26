import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../commons/widgets/pasted_image.dart';
import '../../../../../commons/utils/path_names.dart';
import '../../domain/entities/prompt_queue.dart';
import '../../domain/entities/queue_effect.dart';
import '../../domain/errors/queue_error.dart';
import '../../domain/repository/queue_repository.dart';
import '../../domain/usecase/edit_queue.dart';
import '../../domain/usecase/watch_queue.dart';
import '../../domain/usecase/watch_queue_effects.dart';

part 'queue_state.dart';

/// Um cubit por fila (um por nó). É dono da assinatura: abre ao nascer e
/// cancela no `close()`. A fila inteira vem do core a cada mudança; daqui só
/// sai intenção — a UI guarda a tarefa aberta, nada mais. O aviso de envio é
/// do [QueueNoticeCubit], que segue [notices].
class QueueCubit extends Cubit<QueueState> {
  QueueCubit({
    required this.nodeId,
    required WatchQueue watch,
    required this._edit,
    WatchQueueEffects? effects,
  }) : super(const QueueWaiting()) {
    _subscription = watch(nodeId).listen(_onQueue);
    _effects = effects?.call(nodeId).listen(_onEffect);
  }

  final String nodeId;
  final EditQueue _edit;
  StreamSubscription<PromptQueue>? _subscription;
  StreamSubscription<QueueEffect>? _effects;
  final _drafts = StreamController<String>.broadcast();
  final _queues = StreamController<PromptQueue>.broadcast();
  final _deliveries = StreamController<QueueSendFailure?>.broadcast();

  /// Rascunhos vindos de fora (o `egeon` do terminal) para a linha de baixo.
  /// Evento: o mesmo texto duas vezes vale duas vezes.
  Stream<String> get drafts => _drafts.stream;

  /// O que a linha de aviso segue: a fila (pelo que ela diz de si), começando
  /// pela de agora, e o resultado de cada envio — `null` é envio que foi.
  QueueNoticeSource get notices =>
      (queues: _following(), deliveries: _deliveries.stream);

  Stream<PromptQueue> _following() {
    late final StreamController<PromptQueue> out;
    StreamSubscription<PromptQueue>? changes;
    out = StreamController<PromptQueue>(
      onListen: () {
        out.add(state.queue);
        changes = _queues.stream.listen(out.add);
      },
      onCancel: () => changes?.cancel(),
    );
    return out.stream;
  }

  String? get _open => switch (state) {
    QueueEditing(:final open) => open,
    QueueWaiting() || QueueBrowsing() => null,
  };

  QueueState _showing(PromptQueue queue, String? open) =>
      open == null ? QueueBrowsing(queue) : QueueEditing(queue, open: open);

  void _onQueue(PromptQueue queue) {
    final open = _open;
    // A tarefa aberta que saiu da fila fecha junto.
    emit(
      _showing(
        queue,
        open != null && queue.indexOf(open) == null ? null : open,
      ),
    );
    _queues.add(queue);
  }

  /// Vindo de fora: o rascunho cai na linha de baixo e a tarefa pedida abre.
  void _onEffect(QueueEffect effect) => switch (effect) {
    QueueDraft(:final text) => _drafts.add(text),
    QueueOpenItem(:final item) => expand(item),
  };

  // ---- tarefa aberta -------------------------------------------------------

  /// Abre uma tarefa e fecha a anterior, largando-a se ficou em branco.
  void expand(String id) {
    final previous = _open;
    if (previous == id || isClosed) return;
    emit(QueueEditing(state.queue, open: id));
    if (previous != null) _dropIfEmpty(previous);
  }

  void collapse() {
    final id = _open;
    if (id == null) return;
    emit(QueueBrowsing(state.queue));
    _dropIfEmpty(id);
  }

  /// Tarefa em branco que você abriu e deixou: não vira lixo na lista.
  void _dropIfEmpty(String id) {
    final index = state.queue.indexOf(id);
    if (index == null) return;
    final item = state.queue.items[index];
    if (item.empty && !item.locked) _fire(_edit.remove(nodeId, id));
  }

  // ---- anotar e editar -----------------------------------------------------

  /// Enter na linha de baixo põe a tarefa na lista e deixa a linha pronta para
  /// a próxima. Enter numa tarefa aberta abre uma nova logo abaixo dela.
  Future<void> create({String text = '', String? after}) async {
    final String id;
    try {
      id = await _edit.add(nodeId, text: text, after: after);
    } on QueueError {
      // Core fora: a tarefa não nasceu, e o próximo estado dele corrige a tela.
      return;
    }
    // Sem o id (o core ainda não o devolveu), a tarefa aparece no estado
    // seguinte e a tela espera você abri-la.
    if (id.isNotEmpty && (after != null || text.isEmpty)) expand(id);
  }

  /// A cada tecla: a fila grava e avisa, e a linha aberta não se recria.
  void update(String id, String text) => _fire(_edit.update(nodeId, id, text));

  void remove(String id) => _fire(_edit.remove(nodeId, id));

  void toggleDone(String id) => _fire(_edit.toggleDone(nodeId, id));

  void reopen(String id) => _fire(_edit.reopen(nodeId, id));

  void clearDone() => _fire(_edit.clearDone(nodeId));

  void move(String id, {required int to}) =>
      _fire(_edit.move(nodeId, id, to: to));

  /// Sobe ou desce um passo, sem sair da lista. A conta é da fila; o core
  /// recebe a posição final.
  void moveBy(String id, int offset) {
    final queue = state.queue;
    final to = queue.movedBy(id, offset).indexOf(id);
    if (to != null && to != queue.indexOf(id)) move(id, to: to);
  }

  void attach(String id, List<PastedImage> images) {
    if (images.isNotEmpty) _fire(_edit.attach(nodeId, id, images));
  }

  void detach(String id, String image) =>
      _fire(_edit.detach(nodeId, id, image));

  /// O clique na miniatura: o print abre no app do sistema.
  void openImage(String id, String image) =>
      _fire(_edit.openImage(nodeId, id, image));

  /// Print solto: o core escolhe a tarefa (a aberta, se não foi enviada, ou uma
  /// nova) e a UI a abre para você escrever.
  Future<void> attachToOpenOrNew(List<PastedImage> images) async {
    if (images.isEmpty) return;
    try {
      final id = await _edit.attachLoose(nodeId, images, open: _open);
      if (id.isNotEmpty) expand(id);
    } on QueueError {
      return;
    }
  }

  /// Arquivos soltos na fila. Só imagem entra (como no legado: arrasto que não
  /// é imagem nem é aceito); vira print da tarefa aberta, ou tarefa nova.
  Future<void> attachFiles(List<String> paths) =>
      attachToOpenOrNew(_imageFiles(paths));

  List<PastedImage> _imageFiles(List<String> paths) {
    final extensions = state.queue.imageExtensions;
    return [
      for (final path in paths)
        if (extensions.contains(path.split('.').last.toLowerCase()))
          PastedImage(
            name: lastPathComponent(path),
            bytes: Uint8List(0),
            path: path,
          ),
    ];
  }

  /// O que a área de transferência traz que serve de print. Arquivo copiado
  /// que não é imagem não serve, e aí o ⌘V cola o texto.
  List<PastedImage> _pasted(PastedClipboard pasted) => switch (pasted) {
    PastedFiles(:final paths) => _imageFiles(paths),
    PastedPng(:final bytes) => [PastedImage(name: 'colado.png', bytes: bytes)],
  };

  /// ⌘V com imagem no editor ou na resposta de uma tarefa: o print vai para
  /// ela. Devolve se havia imagem.
  bool pasteInto(String id, PastedClipboard pasted) {
    final images = _pasted(pasted);
    attach(id, images);
    return images.isNotEmpty;
  }

  /// ⌘V com imagem na linha de baixo: o que já estava escrito vira tarefa,
  /// com o print, e ela abre para você continuar. Devolve se havia imagem.
  bool pasteNew(String text, PastedClipboard pasted) {
    final images = _pasted(pasted);
    if (images.isEmpty) return false;
    unawaited(_createWith(text, images));
    return true;
  }

  Future<void> _createWith(String text, List<PastedImage> images) async {
    final String id;
    try {
      id = await _edit.add(nodeId, text: text);
    } on QueueError {
      return;
    }
    if (id.isEmpty) return;
    // Print recusado não desfaz a tarefa: ela abre com o texto, como no legado.
    await _edit
        .attach(nodeId, id, images)
        .catchError((_) {}, test: (error) => error is QueueError);
    if (!isClosed) expand(id);
  }

  /// Print solto sem arquivo (bytes em PNG): o core grava a imagem.
  Future<void> attachPng(Uint8List png) =>
      attachToOpenOrNew([PastedImage(name: 'colado.png', bytes: png)]);

  // ---- mandar --------------------------------------------------------------

  Future<void> send({String? id}) =>
      _deliver(_edit.send(nodeId, id: id), reply: false);

  Future<void> reply(String id, String text) =>
      _deliver(_edit.reply(nodeId, id, text), reply: true);

  Future<void> _deliver(Future<void> sent, {required bool reply}) async {
    try {
      await sent;
      _report(null);
    } on QueueError catch (error) {
      _report(QueueSendFailure(error, reply: reply));
    }
  }

  void _report(QueueSendFailure? failure) {
    if (!_deliveries.isClosed) _deliveries.add(failure);
  }

  void setAuto({required bool on}) => _fire(_edit.setAuto(nodeId, on: on));

  void setTarget(String target) => _fire(_edit.setTarget(nodeId, target));

  /// Comando é "mande e siga": o estado que o core mandar a seguir corrige a
  /// tela se ele recusar.
  void _fire(Future<void> future) => unawaited(
    future.catchError((_) {}, test: (error) => error is QueueError),
  );

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _effects?.cancel();
    await _drafts.close();
    await _queues.close();
    await _deliveries.close();
    return super.close();
  }
}
