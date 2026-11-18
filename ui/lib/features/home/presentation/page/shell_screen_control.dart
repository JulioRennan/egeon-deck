import 'dart:typed_data';

import '../../../../core/adapters/window_frame.dart';
import '../../../canvas/domain/entities/canvas_probe.dart' as canvas_probe;
import '../../../../core/domain/entities/view_mode.dart';
import '../../../../commons/widgets/screen_captures.dart';
import '../../../sidebar/presentation/cubit/sidebar_cubit.dart';
import '../../../sidebar/presentation/widgets/sidebar_segments.dart';
import '../../domain/repository/screen_control.dart';
import '../cubit/shell_cubit.dart';

/// A tela da casca atendendo o que o core pede de fora (decisão 35).
class ShellScreenControl implements ScreenControl {
  ShellScreenControl({
    required this.shell,
    required this.sidebar,
    required this.captures,
    required this.window,
    required this.writePng,
    required this.canvas,
  });

  final ShellCubit shell;
  final SidebarCubit sidebar;
  final ScreenCaptures captures;
  final WindowFrameSource window;

  /// O canvas da bancada na tela agora, se houver um.
  final canvas_probe.CanvasProbe? Function() canvas;

  /// Grava o PNG das regiões da casca; o do card é o canvas que grava.
  final Future<void> Function(String path, Uint8List png) writePng;

  @override
  String? setLayout(String mode) {
    final wanted = ViewMode.values.where((m) => m.wire == mode);
    if (wanted.isEmpty || shell.state.shell.bench == null) return null;
    shell.setView(wanted.first);
    return wanted.first.wire;
  }

  @override
  bool setSidebarCollapsed(bool? collapsed) {
    if (collapsed == null) {
      shell.toggleCollapsed();
    } else {
      shell.setCollapsed(collapsed);
    }
    return shell.state.collapsed;
  }

  @override
  String? setSidebarTab(String tab) {
    final wanted = SidebarTab.values.where((t) => t.name == tab);
    if (wanted.isEmpty) return null;
    sidebar.showTab(wanted.first);
    return wanted.first.name;
  }

  @override
  Future<Map<String, Object?>> geometry() async {
    final bench = shell.state.shell.bench;
    if (bench == null) return {};
    // Em chat não há canvas montado: só o modo diz o que há na tela.
    final probe = canvas();
    if (bench.view == ViewMode.chat || probe == null) {
      return {
        'workbench': bench.name,
        'mode': bench.view.wire,
        'magnification': 1,
        'nodes': <Object?>[],
      };
    }
    final frame = await window.read();
    return {
      ...probe.geometry(
        canvas_probe.WindowFrame(
          x: frame.x,
          y: frame.y,
          screenHeight: frame.screenHeight,
        ),
      ),
      'workbench': bench.name,
    };
  }

  @override
  Future<String> snapshot(String target, String file) async {
    if (target != 'window' && target != 'sidebar') {
      final card = target.split('/');
      final probe = canvas();
      // O canvas ao vivo é o da bancada na tela; outra bancada não está
      // desenhada, e a captura de um card exige o card desenhado.
      if (card.length != 2 ||
          probe == null ||
          card.first != shell.state.shell.bench?.name) {
        return "erro: nó desconhecido '$target'";
      }
      return probe.snapshot(card[1], file);
    }
    final png = await captures.png(target);
    if (png == null) return "erro: nó desconhecido '$target'";
    try {
      await writePng(file, png);
    } on Object catch (error) {
      return 'erro: $error';
    }
    return file;
  }
}
