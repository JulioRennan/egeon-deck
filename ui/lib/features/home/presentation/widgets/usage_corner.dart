import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/utils/bench_identity.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../core/domain/entities/workbench_clock.dart';
import '../../../usage/presentation/cubit/usage_cubit.dart';
import '../../../usage/presentation/widgets/usage_chip.dart';
import '../../../workbench/domain/errors/workbench_error.dart';
import '../../../workbench/domain/usecase/reset_clock.dart';
import '../cubit/shell_cubit.dart';

/// O consumo da bancada na tela, no canto: o cronômetro e o custo num chip de
/// vidro. O cubit é da bancada: trocar de bancada fecha a assinatura da antiga
/// e abre a nova. "Zerar cronômetro" vai ao core; recusa dele não tem o que
/// mostrar, o relógio continua como está.
class UsageCorner extends StatelessWidget {
  const UsageCorner({required this.workbenchId, this.clock, super.key});

  final String workbenchId;
  final WorkbenchClock? clock;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(workbenchId),
    create: (_) => inject<UsageCubit>(workbenchId),
    child: UsageChip(
      identity: BenchIdentity.of(
        context.select<ShellCubit, String?>(
          (shell) => shell.state.snapshot.bench?.color,
        ),
      ),
      clock: clock,
      onReset: () => unawaited(
        inject<ResetClock>()(workbenchId)
            .catchError((_) {}, test: (e) => e is WorkbenchError),
      ),
    ),
  );
}
