import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/prompt_queue.dart';
import '../../domain/entities/queue_effect.dart';
import '../../domain/repository/queue_repository.dart';
import '../../domain/usecase/edit_queue.dart';
import '../../domain/usecase/watch_queue.dart';
import '../../domain/usecase/watch_queue_effects.dart';
import 'queue_state.dart';

/// Um cubit por fila (um por nó). É dono da assinatura: abre ao nascer e
/// cancela no `close()`. A fila inteira vem do core a cada mudança; daqui só
/// sai intenção — a UI guarda a tarefa aberta e o aviso, nada mais.
class QueueCubit extends Cubit<QueueState> {
  QueueCubit({
    required this.nodeId,
    required WatchQueue watch,
    required this._edit,
    WatchQueueEffects? effects,
  }) : super(const QueueState()) {
    _subscription = watch(nodeId).listen(_onQueue);
    _effects = effects?.call(nodeId).listen(_onEffect);
  }

  final String nodeId;
  final EditQueue _edit;
  StreamSubscription<PromptQueue>? _subscription;
  StreamSubscription<QueueEffect>? _effects;
  Timer? _noticeTimer;

  void _onQueue(PromptQueue queue) {
    final open = state.expanded;
    emit(
      state.copyWith(
        queue: queue,
        // A tarefa aberta que saiu da fila fecha junto.
        expanded: open != null && queue.indexOf(open) == null
            ? () => null
            : null,
      ),
    );
  }

  /// Vindo de fora: o rascunho cai na linha de baixo e a tarefa pedida abre.
  void _onEffect(QueueEffect effect) => switch (effect) {
    QueueDraft(:final text) => emit(state.copyWith(draft: text)),
    QueueOpenItem(:final item) => expand(item),
  };

  // ---- tarefa aberta -------------------------------------------------------

  /// Abre uma tarefa e fecha a anterior, largando-a se ficou em branco.
  void expand(String id) {
    if (state.expanded == id) return;
    final previous = state.expanded;
    emit(state.copyWith(expanded: () => id));
    if (previous != null) _dropIfEmpty(previous);
  }

  void collapse() {
    final id = state.expanded;
    if (id == null) return;
    emit(state.copyWith(expanded: () => null));
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
    } on Object {
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

  /// Print solto: o core escolhe a tarefa (a aberta, se não foi enviada, ou uma
  /// nova) e a UI a abre para você escrever.
  Future<void> attachToOpenOrNew(List<PastedImage> images) async {
    if (images.isEmpty) return;
    try {
      final id = await _edit.attachLoose(nodeId, images, open: state.expanded);
      if (id.isNotEmpty) expand(id);
    } on Object {
      return;
    }
  }

  /// Arquivos soltos na fila. Só imagem entra (como no legado: arrasto que não
  /// é imagem nem é aceito); vira print da tarefa aberta, ou tarefa nova.
  Future<void> attachFiles(List<String> paths) {
    final extensions = state.queue.imageExtensions;
    final images = [
      for (final path in paths)
        if (extensions.contains(path.split('.').last.toLowerCase()))
          PastedImage(
            name: path.split('/').last,
            bytes: Uint8List(0),
            path: path,
          ),
    ];
    return attachToOpenOrNew(images);
  }

  /// Print solto sem arquivo (bytes em PNG): o core grava a imagem.
  Future<void> attachPng(Uint8List png) =>
      attachToOpenOrNew([PastedImage(name: 'colado.png', bytes: png)]);

  // ---- mandar --------------------------------------------------------------

  Future<void> send({String? id}) async => _report(
    await _edit.send(nodeId, id: id).catchError((_) => 'Falha ao enviar'),
  );

  Future<void> reply(String id, String text) async => _report(
    await _edit.reply(nodeId, id, text).catchError((_) => 'Falha ao responder'),
  );

  void setAuto({required bool on}) => _fire(_edit.setAuto(nodeId, on: on));

  void setTarget(String target) => _fire(_edit.setTarget(nodeId, target));

  /// O erro fica seis segundos e dá lugar ao que a fila diz de si.
  void _report(String? error) {
    _noticeTimer?.cancel();
    if (isClosed) return;
    emit(state.copyWith(notice: () => error));
    if (error == null) return;
    _noticeTimer = Timer(const Duration(seconds: 6), () {
      if (!isClosed && state.notice == error) {
        emit(state.copyWith(notice: () => null));
      }
    });
  }

  /// Comando é "mande e siga": o estado que o core mandar a seguir corrige a
  /// tela se ele recusar.
  void _fire(Future<void> future) => unawaited(future.catchError((_) {}));

  @override
  Future<void> close() async {
    _noticeTimer?.cancel();
    await _subscription?.cancel();
    await _effects?.cancel();
    return super.close();
  }
}
