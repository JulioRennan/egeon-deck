import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'web_surface.dart';

/// A página nativa pelo plugin próprio do runner (`macos/Runner/Web`): uma
/// `WKWebView` com o data store do perfil (cookies e bancada isolados, como no
/// legado) e captura em PNG — as duas coisas que o pacote
/// `webview_flutter_wkwebview` não dá.
///
/// Só quem monta a fábrica (`main.dart`/casca) importa este arquivo.
WebSurfaceController createChannelWebSurfaceController({
  required String profile,
  required String profileId,
}) => ChannelWebSurface(profile: profile, profileId: profileId);

class ChannelWebSurface implements WebSurfaceController {
  ChannelWebSurface({required this.profile, required this.profileId}) {
    _ready = _create();
  }

  static const _channel = MethodChannel('egeon/web');
  static const viewType = 'egeon/web-view';
  static final _live = <int, ChannelWebSurface>{};
  static var _handlerInstalled = false;

  /// O nome do perfil e o UUID do data store (do core, `web-profiles.json`).
  final String profile;
  final String profileId;

  late final Future<int> _ready;
  final _states = StreamController<WebPageState>.broadcast();
  var _disposed = false;

  /// Só existe depois de a página nascer no runner.
  int? _id;

  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'state') return;
      final map = (call.arguments as Map).cast<Object?, Object?>();
      _live[map['id']! as int]?._onState(map);
    });
  }

  Future<int> _create() async {
    _installHandler();
    final id = (await _channel.invokeMethod<int>('create', {
      'profile': profile,
      'profileId': profileId,
    }))!;
    if (_disposed) {
      // Soltou antes de a página nascer: não fica vista retida no runner.
      await _channel.invokeMethod<void>('dispose', {'id': id});
    } else {
      _id = id;
      _live[id] = this;
    }
    return id;
  }

  void _onState(Map<Object?, Object?> map) {
    if (_disposed) return;
    _states.add(
      WebPageState(
        url: map['url'] as String? ?? '',
        canGoBack: map['canGoBack'] as bool? ?? false,
        canGoForward: map['canGoForward'] as bool? ?? false,
        loading: map['loading'] as bool? ?? false,
      ),
    );
  }

  Future<T?> _call<T>(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    final id = await _ready;
    if (_disposed) return null;
    return _channel.invokeMethod<T>(method, {'id': id, ...args});
  }

  @override
  Stream<WebPageState> get states => _states.stream;

  @override
  Future<void> load(String url) => _call<void>('load', {'url': url});

  @override
  Future<void> goBack() => _call<void>('goBack');

  @override
  Future<void> goForward() => _call<void>('goForward');

  @override
  Future<void> reload() => _call<void>('reload');

  /// PNG da página, no tamanho que a vista tem na tela agora.
  @override
  Future<Uint8List?> capture() => _call<Uint8List>('snapshot');

  @override
  Widget buildView(BuildContext context) => FutureBuilder<int>(
    future: _ready,
    builder: (context, snapshot) {
      final id = snapshot.data;
      if (id == null) return const SizedBox.expand();
      return AppKitView(
        viewType: viewType,
        creationParams: {'id': id},
        creationParamsCodec: const StandardMessageCodec(),
      );
    },
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_states.close());
    final id = _id;
    // Ainda nascendo: quem solta é o `_create`, assim que o id chegar.
    if (id == null) return;
    _live.remove(id);
    unawaited(_channel.invokeMethod<void>('dispose', {'id': id}));
  }
}
