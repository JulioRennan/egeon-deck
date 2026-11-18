import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/usecase/relaunch_core.dart';
import '../domain/usecase/start_core.dart';
import '../domain/usecase/stop_core.dart';
import '../domain/usecase/watch_core_link.dart';
import 'core_status.dart';

/// Global: sobe o core Rust e diz se o app está falando com ele. É o dono da
/// assinatura da conexão e quem encerra o core ao fechar.
class ConnectionCubit extends Cubit<CoreStatus> {
  ConnectionCubit({
    required this._startCore,
    required WatchCoreLink watchLink,
    required this._relaunchCore,
    required this._stopCore,
  }) : super(const CoreStatus(ConnectionPhase.starting)) {
    _link = watchLink().listen(_onLink);
    unawaited(_start());
  }

  final StartCore _startCore;
  final RelaunchCore _relaunchCore;
  final StopCore _stopCore;
  StreamSubscription<bool>? _link;

  Future<void> _start() async {
    try {
      await _startCore();
    } catch (e) {
      emit(CoreStatus(ConnectionPhase.failed, error: '$e'));
    }
  }

  void _onLink(bool connected) {
    if (connected) {
      emit(const CoreStatus(ConnectionPhase.connected));
      return;
    }
    emit(const CoreStatus(ConnectionPhase.starting));
    unawaited(_relaunch());
  }

  /// O core caiu com a UI aberta: sobe outro (o lançador não lança se algo
  /// já atende no socket) e o cliente reconecta sozinho.
  Future<void> _relaunch() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (isClosed) return;
    try {
      await _relaunchCore();
    } catch (e) {
      if (!isClosed) emit(CoreStatus(ConnectionPhase.failed, error: '$e'));
    }
  }

  @override
  Future<void> close() async {
    await _link?.cancel();
    await _stopCore();
    return super.close();
  }
}
