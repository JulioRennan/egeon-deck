import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/cubits/connection_cubit.dart';
import '../../../../core/cubits/core_status.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_theme.dart';
import '../../../node/terminal/domain/repository/terminal_repository.dart';
import '../../../node/terminal/domain/usecase/resize_terminal.dart';
import '../../../node/terminal/domain/usecase/send_terminal_input.dart';
import '../../../node/terminal/domain/usecase/watch_terminal.dart';
import '../../../node/terminal/presentation/cubit/terminal_cubit.dart';
import '../../../node/terminal/presentation/page/terminal_page.dart';
import '../cubit/home_cubit.dart';

class HomeContent extends StatelessWidget {
  const HomeContent({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionCubit>().state;
    final home = context.watch<HomeCubit>().state;
    final id = home.terminalId;

    return Stack(
      children: [
        if (id != null) TerminalHost(key: ValueKey(id), nodeId: id),
        if (connection.phase == ConnectionPhase.failed)
          HomeNotice(connection.error ?? 'Falha ao iniciar o core')
        else if (id == null && home.error != null)
          HomeNotice(home.error!)
        else if (connection.phase == ConnectionPhase.starting)
          const HomeNotice('Conectando ao core…'),
      ],
    );
  }
}

class TerminalHost extends StatelessWidget {
  const TerminalHost({super.key, required this.nodeId});

  final String nodeId;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<TerminalRepository>();
    return BlocProvider(
      create: (_) => TerminalCubit(
        nodeId: nodeId,
        watch: WatchTerminal(repository),
        input: SendTerminalInput(repository),
        resize: ResizeTerminal(repository),
      ),
      child: const TerminalPage(),
    );
  }
}

class HomeNotice extends StatelessWidget {
  const HomeNotice(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: AppTheme.textStyle.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }
}
