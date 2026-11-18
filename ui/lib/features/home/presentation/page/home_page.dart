import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/cubits/connection_cubit.dart';
import '../../../../core/cubits/core_status.dart';
import '../../../../theme/app_colors.dart';
import '../../../node/terminal/domain/repository/terminal_repository.dart';
import '../../../node/terminal/domain/usecase/open_terminal.dart';
import '../cubit/home_cubit.dart';
import '../cubit/shell_cubit.dart';
import '../widgets/root_layout.dart';
import '../../../chat/presentation/cubit/queue_panel_width.dart';
import '../../domain/repository/node_repositories.dart';
import '../widgets/home_content.dart';
import '../widgets/workbench_canvas.dart';
import '../../../chat/presentation/page/chat_page.dart';
import 'home_shell_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.read<TerminalRepository>();
    return BlocProvider(
      create: (context) {
        final home = HomeCubit(OpenTerminal(repository));
        final phase = context.read<ConnectionCubit>().state.phase;
        if (phase == ConnectionPhase.connected) home.openTerminal();
        return home;
      },
      child: BlocListener<ConnectionCubit, CoreStatus>(
        listenWhen: (_, now) => now.phase == ConnectionPhase.connected,
        listener: (context, _) => context.read<HomeCubit>().openTerminal(),
        // Sem bancada na tela, o terminal único; com ela, o canvas ou o chat.
        child: ColoredBox(
          color: AppColors.background,
          child: HomeShellPage(
            canvas: (context, bench) => bench == null
                ? const HomeContent()
                : WorkbenchCanvas(
                    bench: bench,
                    // A barra flutuante cobre a esquerda do canvas; enquadrar
                    // desconta, e recolher a barra reenquadra.
                    sidebarInset: RootLayout.floatingInset(
                      collapsed: context.select(
                        (ShellCubit shell) => shell.state.collapsed,
                      ),
                      beside: false,
                    ),
                  ),
            chat: (context, bench) => ChatPage(
              workbenchId: bench.id,
              queues: ChatQueues(
                repository: context.read<NodeRepositories>().queue(bench.id),
                width: context.read<QueuePanelWidth>(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
