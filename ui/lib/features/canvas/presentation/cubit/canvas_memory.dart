import '../../domain/entities/canvas_viewport.dart';
import 'canvas_tool_cubit.dart';

/// A vista e a ferramenta de cada bancada enquanto o app vive. O canvas de
/// uma bancada sai da tela ao trocar de aba ou ir para o chat; ao voltar, ele
/// continua onde estava — no Swift o canvas vive com a bancada, e só a
/// primeira vez abre enquadrado.
class CanvasMemory {
  final _views = <String, CanvasViewport>{};
  final _tools = <String, CanvasToolState>{};

  CanvasViewport? view(String workbenchId) => _views[workbenchId];

  void keepView(String workbenchId, CanvasViewport viewport) =>
      _views[workbenchId] = viewport;

  CanvasToolState? tool(String workbenchId) => _tools[workbenchId];

  void keepTool(String workbenchId, CanvasToolState tool) =>
      _tools[workbenchId] = tool;
}
