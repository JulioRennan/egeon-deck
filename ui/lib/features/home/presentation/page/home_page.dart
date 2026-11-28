import 'package:flutter/widgets.dart';

import '../../../../core/domain/entities/workbench.dart';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../theme/egeon_colors.dart';
import '../cubit/shell_cubit.dart';
import '../widgets/root_layout.dart';
import '../widgets/home_content.dart';
import '../widgets/workbench_canvas.dart';
import '../../../chat/presentation/page/chat_page.dart';
import '../../../node/agent/presentation/widgets/agent_traits.dart';
import 'home_shell_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({this.title = 'Egeon Deck', super.key});

  /// O nome do flavor ("Egeon Deck (dev)"), para o que diz de qual app é.
  final String title;

  @override
  Widget build(BuildContext context) {
    // Sem bancada na tela, o vazio com o aviso de conexão; com ela, o canvas
    // ou o chat.
    return ColoredBox(
      color: context.eg.obsidian,
      child: HomeShellPage(
        title: title,
        canvas: (context, bench) =>
            bench == null ? const HomeContent() : _BenchCanvas(bench: bench),
        chat: (context, bench) => ChatPage(
          workbenchId: bench.id,
          offerQueues: true,
          traitsFor: (nodeId) =>
              AgentTraits(workbenchId: bench.id, nodeId: nodeId),
        ),
      ),
    );
  }
}

/// O recuo da barra é lido aqui, no `build` deste widget: no construtor do
/// canvas o `context` é de quem chama, e o `select` fora do build dele estoura.
class _BenchCanvas extends StatelessWidget {
  const _BenchCanvas({required this.bench});

  final Workbench bench;

  @override
  Widget build(BuildContext context) {
    final collapsed = context.select((ShellCubit shell) => shell.collapsed);
    return WorkbenchCanvas(
      bench: bench,
      // A barra flutuante cobre a esquerda do canvas; enquadrar desconta, e
      // recolher a barra reenquadra.
      sidebarInset: RootLayout.floatingInset(
        collapsed: collapsed,
        beside: false,
      ),
    );
  }
}
