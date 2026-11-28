import 'package:egeon_deck/features/canvas/presentation/cubit/canvas_cubit.dart';
import 'package:egeon_deck/features/canvas/presentation/widgets/canvas_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_canvas_repository.dart';
import '../../../support/pump_canvas.dart';

import 'package:egeon_deck/commons/utils/app_shortcut.dart';

/// Dois dedos no trackpad: sem ⌘ o canvas anda; com ⌘, zoom no cursor —
/// como a ⌘+roda (auditoria, Canvas).
void main() {
  CanvasState state(WidgetTester tester) =>
      tester.element(find.byType(CanvasSurface)).read<CanvasCubit>().state;

  Future<void> twoFingers(WidgetTester tester, Offset at, Offset pan) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.trackpad,
    );
    await gesture.panZoomStart(at);
    await gesture.panZoomUpdate(at, pan: pan);
    await gesture.panZoomEnd();
    await tester.pump();
  }

  testWidgets('com ⌘, dois dedos aproximam no cursor', (tester) async {
    await pumpCanvas(tester, InMemoryCanvasRepository());
    final before = state(tester).viewport.zoom;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    // Dedos para cima aproximam, como no Figma.
    await twoFingers(tester, const Offset(600, 600), const Offset(0, 60));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

    expect(state(tester).viewport.zoom, isNot(before));
  });

  testWidgets('sem ⌘, dois dedos andam a vista e não mexem no zoom', (
    tester,
  ) async {
    await pumpCanvas(tester, InMemoryCanvasRepository());
    final before = state(tester).viewport;

    await twoFingers(tester, const Offset(600, 600), const Offset(0, -60));

    expect(state(tester).viewport.zoom, before.zoom);
    expect(state(tester).viewport.origin, isNot(before.origin));
  });

  testWidgets('fora do macOS, Ctrl + dois dedos aproximam no cursor', (
    tester,
  ) async {
    debugUsesCommandKey = false;
    addTearDown(() => debugUsesCommandKey = true);
    await pumpCanvas(tester, InMemoryCanvasRepository());
    final before = state(tester).viewport.zoom;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await twoFingers(tester, const Offset(600, 600), const Offset(0, 60));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(state(tester).viewport.zoom, isNot(before));
  });
}
