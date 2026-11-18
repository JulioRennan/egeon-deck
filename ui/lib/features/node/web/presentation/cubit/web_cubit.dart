import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../commons/widgets/web_surface.dart';
import '../../domain/entities/web_node.dart';
import '../../domain/errors/web_error.dart';
import '../../domain/usecase/edit_web.dart';
import '../../domain/usecase/watch_web.dart';
import 'web_capture_registry.dart';

part 'web_state.dart';

/// A fábrica da página nativa: o nome do perfil e o UUID do data store dele.
typedef WebControllerFactory = WebSurfaceController Function(
  String profile,
  String profileId,
);

/// Um cubit por nó web. É dono da assinatura do core e da página nativa: abre
/// ao nascer e solta tudo no `close()`.
///
/// O perfil é fixado na criação da vista (o data store é do WKWebView), então
/// trocar de perfil é jogar a página fora e montar outra na mesma URL.
class WebCubit extends Cubit<WebState> {
  WebCubit({
    required this.nodeId,
    required WatchWeb watch,
    required this._edit,
    required this._createController,
    this.captures,
  }) : super(const WebWaiting()) {
    _subscription = watch(nodeId).listen(_onNode);
  }

  final String nodeId;
  final EditWeb _edit;
  final WebControllerFactory _createController;

  /// Onde a página viva se registra para o `/shot`.
  final WebCaptureRegistry? captures;
  Future<Uint8List?> Function()? _capture;

  StreamSubscription<WebNode>? _subscription;
  StreamSubscription<WebPageState>? _pages;
  WebSurfaceController? _controller;
  String? _profile;
  String? _requested;

  /// A página viva, ou nula antes de o core dizer o perfil.
  WebSurfaceController? get controller => _controller;

  /// Onde a página nativa está, se já disse.
  WebPageState? get _page => switch (state) {
    WebWaiting() => null,
    WebShown(:final page) => page,
  };

  void _showNode(WebNode node) => emit(WebShown(node: node, page: _page));

  void _onNode(WebNode node) {
    // Sem o UUID do perfil (do `web-profiles.json`, no core) não há data store
    // para abrir: a página espera ele chegar em vez de inventar um.
    final profileId = node.profileId;
    if (profileId == null) {
      _showNode(node);
      return;
    }
    if (_controller == null || _profile != node.profile) {
      _mount(node, profileId);
    } else if (node.url != _requested && node.url != _page?.url) {
      _requested = node.url;
      _drive(_controller!.load(node.url));
    }
    _showNode(node);
  }

  void _mount(WebNode node, String profileId) {
    unawaited(_pages?.cancel());
    _unregisterCapture();
    _controller?.dispose();
    final controller = _createController(node.profile, profileId);
    _controller = controller;
    _capture = controller.capture;
    captures?.register(nodeId, _capture!);
    _profile = node.profile;
    _requested = node.url;
    _pages = controller.states.listen(_onPage);
    _drive(controller.load(node.url));
  }

  void _onPage(WebPageState page) {
    // A página só nasce depois do nó: sem ele, não há o que mostrar.
    final shown = state;
    if (shown is! WebShown) return;
    final known = shown.node.url;
    emit(shown.copyWith(page: page));
    // A página navegou sozinha: o core grava para a bancada voltar onde estava.
    if (page.url.isNotEmpty && page.url != known && page.url != _requested) {
      _requested = page.url;
      _fire(_edit.reportNavigated(nodeId, page.url));
    }
  }

  void submit(String typed) => _fire(_edit.navigate(nodeId, typed));

  void back() => _drive(_controller?.goBack());

  void forward() => _drive(_controller?.goForward());

  void reload() => _drive(_controller?.reload());

  void setProfile(String profile) => _fire(_edit.setProfile(nodeId, profile));

  /// Comando é "mande e siga": o estado que o core mandar a seguir corrige a
  /// tela se ele recusar.
  void _fire(Future<void> future) =>
      unawaited(future.catchError((_) {}, test: (error) => error is WebError));

  /// A página nativa avisa o que fez pelo stream de estados; a falha de um
  /// pedido a ela não tem o que mostrar além disso.
  void _drive(Future<void>? future) =>
      unawaited(future?.catchError((_) {}) ?? Future<void>.value());

  void _unregisterCapture() {
    final capture = _capture;
    if (capture != null) captures?.unregister(nodeId, capture);
    _capture = null;
  }

  @override
  Future<void> close() async {
    _unregisterCapture();
    await _subscription?.cancel();
    await _pages?.cancel();
    _controller?.dispose();
    return super.close();
  }
}
