import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_type.dart';
import '../../../usage/presentation/cubit/usage_cubit.dart';

/// O custo da bancada, embaixo do tile (ADR-085): só a soma, em mono; o
/// detalhe está no canvas e no chat. Cada linha assina o consumo da sua
/// bancada; sem nada consumido, não ocupa lugar.
class BenchCostLabel extends StatelessWidget {
  const BenchCostLabel({required this.workbenchId, this.gap = 0, super.key});

  final String workbenchId;

  /// O respiro em cima, só quando há custo para mostrar.
  final double gap;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(workbenchId),
    create: (_) => inject<UsageCubit>(workbenchId),
    child: BlocBuilder<UsageCubit, UsageState>(
      builder: (context, state) => switch (state) {
        UsageWaiting() => const SizedBox.shrink(),
        UsageShown(:final view) when view.pill.empty => const SizedBox.shrink(),
        UsageShown(:final view) => Padding(
          padding: EdgeInsets.only(top: gap),
          child: Tooltip(
            message: view.pill.tooltip ?? '',
            child: Text(
              view.pill.text,
              key: ValueKey('bench-cost-$workbenchId'),
              maxLines: 1,
              style: EgeonType.monoMeta.copyWith(
                color: context.eg.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      },
    ),
  );
}
