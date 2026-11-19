import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/app_tooltip.dart';
import '../../../../core/adapters/injector.dart';
import '../../../../theme/app_colors.dart';
import '../cubit/usage_cubit.dart';

/// O custo da bancada na ponta da linha do cronômetro, na barra lateral
/// (ADR-085): só a soma — o detalhe está no canvas e no chat. Cada linha assina
/// o consumo da sua bancada; sem nada consumido, não ocupa lugar.
class BenchCost extends StatelessWidget {
  const BenchCost({required this.workbenchId, super.key});

  final String workbenchId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(workbenchId),
    create: (_) => inject<UsageCubit>(workbenchId),
    child: BlocBuilder<UsageCubit, UsageState>(
      builder: (context, state) => switch (state) {
        UsageWaiting() => const SizedBox.shrink(),
        UsageShown(:final view) when view.pill.empty => const SizedBox.shrink(),
        UsageShown(:final view) => AppTooltip(
          message: view.pill.tooltip ?? '',
          child: Text(
            view.pill.text,
            key: ValueKey('bench-cost-$workbenchId'),
            maxLines: 1,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10,
              color: AppColors.white(0.55),
              fontFeatures: const [FontFeature.tabularFigures()],
              decoration: TextDecoration.none,
            ),
          ),
        ),
      },
    ),
  );
}
