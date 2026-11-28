import '../entities/ui_request.dart';
import '../repository/screen_control.dart';

/// Atende um pedido do core pela tela e devolve só o valor: o status e o corpo
/// HTTP são do core.
class AnswerUiRequest {
  const AnswerUiRequest(this._screen);

  final ScreenControl _screen;

  Future<UiReply> call(UiRequest request) async {
    final params = request.params;
    switch (request.route) {
      case 'layout':
        return UiReply(_screen.setLayout(params['mode'] ?? ''));
      case 'sidebar':
        final tab = params['tab'];
        if (tab != null) return UiReply(_screen.setSidebarTab(tab));
        final raw = params['collapsed'] ?? '';
        return UiReply(
          _screen.setSidebarCollapsed(raw == 'toggle' ? null : raw == '1'),
        );
      case 'geometry':
        return UiReply(await _screen.geometry());
      case 'shot':
        final file = params['file'];
        if (file == null || file.isEmpty) {
          return const UiReply('erro: sem arquivo');
        }
        return UiReply(await _screen.snapshot(params['target'] ?? '', file));
    }
    return const UiReply(null);
  }
}
