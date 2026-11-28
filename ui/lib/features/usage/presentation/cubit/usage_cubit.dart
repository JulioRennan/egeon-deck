import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/usage_view.dart';
import '../../domain/usecase/watch_usage.dart';

part 'usage_state.dart';

/// Um cubit por bancada: dono da assinatura do consumo, abre ao nascer e
/// cancela no `close()`. O core manda a pastilha e o painel prontos.
class UsageCubit extends Cubit<UsageState> {
  UsageCubit({required this.workbenchId, required WatchUsage watch})
    : super(const UsageWaiting()) {
    _subscription = watch(workbenchId).listen((view) => emit(UsageShown(view)));
  }

  final String workbenchId;
  StreamSubscription<UsageView>? _subscription;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
