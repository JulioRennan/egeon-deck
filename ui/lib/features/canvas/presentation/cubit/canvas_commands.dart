import '../../domain/entities/canvas_tool.dart';
import 'canvas_cubit.dart';

/// Os comandos do canvas que o menu da casca chama: ferramentas e zoom. O
/// canvas se liga aqui ao nascer e solta ao sair; sem canvas na tela (modo
/// chat), os comandos não fazem nada e [attached] é falso.
class CanvasCommands {
  CanvasCubit? _cubit;

  bool get attached => _cubit != null;

  void attach(CanvasCubit cubit) => _cubit = cubit;

  /// Só solta se ainda for o mesmo: a bancada nova liga antes de a antiga sair.
  void detach(CanvasCubit cubit) {
    if (identical(_cubit, cubit)) _cubit = null;
  }

  /// A ferramenta que o próximo clique no canvas usa (cursor, terminal, web,
  /// fila).
  void selectTool(CanvasTool tool) => _cubit?.selectTool(tool);

  /// Aproximar (+1) e afastar (−1) um passo.
  void zoomIn() => _cubit?.stepZoom(1);

  void zoomOut() => _cubit?.stepZoom(-1);

  void resetZoom() => _cubit?.resetZoom();

  /// Enquadrar todos os nós.
  void fitAll() => _cubit?.fitAll();
}
