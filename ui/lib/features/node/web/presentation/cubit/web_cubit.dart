import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../commons/widgets/web_surface.dart';
import '../../domain/entities/web_node_state.dart';
import '../../domain/usecase/edit_web.dart';
import '../../domain/usecase/watch_web.dart';
import 'web_capture_registry.dart';
import 'web_state.dart';

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
  }) : super(const WebState()) {
    _subscription = watch(nodeId).listen(_onNode);
  }

  final String nodeId;
  final EditWeb _edit;
  final WebControllerFactory _createController;

  /// Onde a página viva se registra para o `/shot`.
  final WebCaptureRegistry? captures;
  Future<Uint8List?> Function()? _capture;

  StreamSubscription<WebNodeState>? _subscription;
  StreamSubscription<WebPageState>? _pages;
  WebSurfaceController? _controller;
  String? _profile;
  String? _requested;

  /// A página viva, ou nula antes de o core dizer o perfil.
  WebSurfaceController? get controller => _controller;

  void _onNode(WebNodeState node) {
    // Sem o UUID do perfil (do `web-profiles.json`, no core) não há data store
    // para abrir: a página espera ele chegar em vez de inventar um.
    final profileId = node.profileId;
    if (profileId == null) {
      emit(state.copyWith(node: node));
      return;
    }
    if (_controller == null || _profile != node.profile) {
      _mount(node, profileId);
    } else if (node.url != _requested && node.url != state.page?.url) {
      _requested = node.url;
      _fire(_controller!.load(node.url));
    }
    emit(state.copyWith(node: node));
  }

  void _mount(WebNodeState node, String profileId) {
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
    _fire(controller.load(node.url));
  }

  void _onPage(WebPageState page) {
    final known = state.node?.url;
    emit(state.copyWith(page: page));
    // A página navegou sozinha: o core grava para a bancada voltar onde estava.
    if (page.url.isNotEmpty && page.url != known && page.url != _requested) {
      _requested = page.url;
      _fire(_edit.reportNavigated(nodeId, page.url));
    }
  }

  void submit(String typed) => _fire(_edit.navigate(nodeId, typed));

  void back() => _fire(_controller?.goBack());

  void forward() => _fire(_controller?.goForward());

  void reload() => _fire(_controller?.reload());

  void setProfile(String profile) => _fire(_edit.setProfile(nodeId, profile));

  /// Comando é "mande e siga": o estado que o core mandar a seguir corrige a
  /// tela se ele recusar.
  void _fire(Future<void>? future) =>
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
