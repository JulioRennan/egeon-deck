import 'dart:async';
import 'dart:typed_data';

import 'package:egeon_deck/commons/widgets/web_surface.dart';
import 'package:flutter/widgets.dart';

/// Uma página falsa: o teste empurra o estado da navegação e lê o que a UI
/// mandou.
class FakeWebSurface implements WebSurfaceController {
  FakeWebSurface(this.profile);

  final String profile;
  final loaded = <String>[];
  var backs = 0;
  var forwards = 0;
  var reloads = 0;
  var disposed = false;
  final _states = StreamController<WebPageState>.broadcast();

  void navigate(WebPageState state) => _states.add(state);

  @override
  Stream<WebPageState> get states => _states.stream;

  @override
  Future<void> load(String url) async => loaded.add(url);

  @override
  Future<void> goBack() async => backs++;

  @override
  Future<void> goForward() async => forwards++;

  @override
  Future<void> reload() async => reloads++;

  @override
  Future<Uint8List?> capture() async => _png;

  @override
  Widget buildView(BuildContext context) =>
      const SizedBox.expand(key: ValueKey('native-view'));

  @override
  void dispose() {
    disposed = true;
    unawaited(_states.close());
  }
}

// 1x1 PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00,
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
