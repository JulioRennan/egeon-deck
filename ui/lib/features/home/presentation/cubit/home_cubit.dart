import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../node/terminal/domain/usecase/open_terminal.dart';
import 'home_state.dart';

/// A casca. Por enquanto só mostra um terminal quando o core Rust atende; o
/// canvas e as abas entram depois.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit(this._openTerminal) : super(const HomeState());

  final OpenTerminal _openTerminal;
  var _opening = false;

  /// Chamado a cada (re)conexão: mantém o terminal se ele ainda vive, troca
  /// por outro se o core reiniciou.
  Future<void> openTerminal() async {
    if (_opening) return;
    _opening = true;
    try {
      final info = await _openTerminal(current: state.terminalId);
      if (info.id != state.terminalId || state.error != null) {
        emit(HomeState(terminalId: info.id));
      }
    } catch (e) {
      emit(HomeState(terminalId: state.terminalId, error: '$e'));
    } finally {
      _opening = false;
    }
  }
}
