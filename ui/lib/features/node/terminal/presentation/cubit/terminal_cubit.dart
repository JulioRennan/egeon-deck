import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/terminal_effect.dart';
import '../../domain/entities/terminal_frame.dart';
import '../../domain/entities/terminal_key.dart';
import '../../domain/entities/terminal_pointer.dart';
import '../../domain/usecase/resize_terminal.dart';
import '../../domain/usecase/send_terminal_input.dart';
import '../../domain/usecase/watch_terminal.dart';
import '../../domain/usecase/watch_terminal_effects.dart';
import 'terminal_state.dart';

/// Um cubit por terminal. É dono da assinatura da tela: abre ao nascer e
/// cancela no `close()`. As linhas não passam pelo estado — o widget as lê de
/// [frames], por causa do volume.
class TerminalCubit extends Cubit<TerminalState> {
  TerminalCubit({
    required this.nodeId,
    required WatchTerminal watch,
    required this._input,
    required this._resize,
    WatchTerminalEffects? effects,
  }) : super(const TerminalState()) {
    _subscription = watch(nodeId).listen(_onFrame);
    _effectsSubscription = effects?.call(nodeId).listen(_effects.add);
  }

  final String nodeId;
  final SendTerminalInput _input;
  final ResizeTerminal _resize;

  final _frames = StreamController<TerminalFrame>.broadcast();
  StreamSubscription<TerminalFrame>? _subscription;
  StreamSubscription<TerminalEffect>? _effectsSubscription;
  final _effects = StreamController<TerminalEffect>.broadcast();
  TerminalFrame? _last;

  Stream<TerminalFrame> get frames => _frames.stream;

  /// Beep e área de transferência que o programa pede. Quem toca o som e fala
  /// com a área de transferência é o widget.
  Stream<TerminalEffect> get effects => _effects.stream;

  /// O quadro mais recente, para um widget que nasce depois dele.
  TerminalFrame? get lastFrame => _last;

  void _onFrame(TerminalFrame frame) {
    _last = frame;
    _frames.add(frame);
    if (!state.live ||
        state.columns != frame.columns ||
        state.rows != frame.rows) {
      emit(
        state.copyWith(live: true, columns: frame.columns, rows: frame.rows),
      );
    }
  }

  void sendKey(TerminalKey key) => _fire(_input.key(nodeId, key));

  void sendText(String text) => _fire(_input.text(nodeId, text));

  void paste(String text) => _fire(_input.paste(nodeId, text));

  void resize(int columns, int rows) => _fire(_resize(nodeId, columns, rows));

  /// O gesto do mouse, cru: o core decide o que ele significa.
  void pointer(TerminalPointer pointer) =>
      _fire(_input.pointer(nodeId, pointer));

  void scroll(TerminalScroll scroll) => _fire(_input.scroll(nodeId, scroll));

  void selectAll() => _fire(_input.selectAll(nodeId));

  /// ⌘C: o core devolve o texto da seleção; vazio ou nulo é "nada a copiar".
  Future<String?> copy() => _input.copy(nodeId).catchError((_) => null);

  /// Há link na célula? Com ⌘ sobre ela, a UI mostra a mão. Falha é "não há".
  Future<bool> linkHover(double x, double y) =>
      _input.linkHover(nodeId, x, y).catchError((_) => false);

  /// Arquivos soltos aqui; o core monta o texto que vai ao agente.
  void dropFiles(List<String> paths) => _fire(_input.dropFiles(nodeId, paths));

  /// Imagem solta sem arquivo, já em PNG.
  void dropImage(Uint8List png) => _fire(_input.dropImage(nodeId, png));

  /// Resposta ao pedido de leitura da área de transferência (OSC 52).
  void sendClipboard(String text) => _fire(_input.clipboard(nodeId, text));

  /// Tecla e resize são "mande e siga": se a conexão cair, o core reenvia a
  /// tela inteira ao reassinar e o próximo gesto já vale.
  void _fire(Future<void> future) => unawaited(future.catchError((_) {}));

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _effectsSubscription?.cancel();
    await _effects.close();
    await _frames.close();
    return super.close();
  }
}
