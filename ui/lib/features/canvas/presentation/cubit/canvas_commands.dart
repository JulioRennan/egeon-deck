import '../../domain/entities/canvas_tool.dart';
import 'canvas_cubit.dart';
import 'canvas_tool_cubit.dart';

/// Os comandos do canvas que o menu da casca chama: ferramentas e zoom. O
/// canvas se liga aqui ao nascer e solta ao sair; sem canvas na tela (modo
/// chat), os comandos não fazem nada e [attached] é falso.
class CanvasCommands {
  CanvasCubit? _cubit;
  CanvasToolCubit? _tools;

  bool get attached => _cubit != null;

  void attach(CanvasCubit cubit, CanvasToolCubit tools) {
    _cubit = cubit;
    _tools = tools;
  }

  /// Só solta se ainda for o mesmo: a bancada nova liga antes de a antiga sair.
  void detach(CanvasCubit cubit) {
    if (!identical(_cubit, cubit)) return;
    _cubit = null;
    _tools = null;
  }

  /// A ferramenta que o próximo clique no canvas usa (cursor, terminal, web,
  /// fila).
  void selectTool(CanvasTool tool) => _tools?.selectTool(tool);

  /// Aproximar (+1) e afastar (−1) um passo.
  void zoomIn() => _cubit?.stepZoom(1);

  void zoomOut() => _cubit?.stepZoom(-1);

  void resetZoom() => _cubit?.resetZoom();

  /// Enquadrar todos os nós.
  void fitAll() => _cubit?.fitAll();
}
