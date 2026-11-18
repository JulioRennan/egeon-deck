import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../usage/domain/repository/usage_repository.dart';
import '../../../usage/domain/usecase/watch_usage.dart';
import '../../../usage/presentation/cubit/usage_cubit.dart';
import '../../../usage/presentation/widgets/usage_pill.dart';

/// A pastilha de consumo da bancada na tela, no canto da barra de cima. O cubit
/// é da bancada: trocar de bancada fecha a assinatura da antiga e abre a nova.
class UsageCorner extends StatelessWidget {
  const UsageCorner({required this.workbenchId, super.key});

  final String workbenchId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(workbenchId),
    create: (context) => UsageCubit(
      workbenchId: workbenchId,
      watch: WatchUsage(context.read<UsageRepository>()),
    ),
    child: const UsagePill(),
  );
}
