import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/prompt_queue.dart';
import 'queue_cubit.dart';

part 'queue_notice_state.dart';

/// A linha de aviso da fila: o erro do último envio, que fica uns segundos, e
/// senão o que a fila diz de si (por que não anda). Varia sozinha da lista,
/// por isso é outro cubit; segue o [QueueCubit] pela [QueueNoticeSource].
class QueueNoticeCubit extends Cubit<QueueNoticeState> {
  QueueNoticeCubit(
    QueueNoticeSource source, {
    this.failureTime = const Duration(seconds: 6),
  }) : super(const QueueQuiet()) {
    _queues = source.queues.listen((queue) {
      _blocker = queue.blocker;
      if (state is! QueueSendFailed) emit(_settled());
    });
    _deliveries = source.deliveries.listen(_onDelivery);
  }

  /// Quanto o erro de envio fica antes de dar lugar ao que a fila diz de si.
  final Duration failureTime;

  StreamSubscription<PromptQueue>? _queues;
  StreamSubscription<QueueSendFailure?>? _deliveries;
  Timer? _timer;
  String? _blocker;

  QueueNoticeState _settled() => switch (_blocker) {
    final text? => QueueBlocked(text),
    null => const QueueQuiet(),
  };

  void _onDelivery(QueueSendFailure? failure) {
    _timer?.cancel();
    if (failure == null) {
      emit(_settled());
      return;
    }
    emit(QueueSendFailed(failure));
    _timer = Timer(failureTime, () {
      if (!isClosed) emit(_settled());
    });
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    await _queues?.cancel();
    await _deliveries?.cancel();
    return super.close();
  }
}
