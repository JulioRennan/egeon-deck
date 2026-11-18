import 'package:egeon_deck/core/adapters/native_edit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('egeon/edit');
  final calls = <Object?>[];

  setUp(() {
    calls.clear();
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.arguments);
          return true;
        });
  });
  tearDown(
    () => TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test('cada ação vai ao runner pelo nome', () async {
    for (final action in EditAction.values) {
      await const ChannelNativeEdit().send(action);
    }
    expect(calls, ['undo', 'redo', 'cut', 'copy', 'paste', 'selectAll']);
  });

  test('sem plugin (fora do macOS) não quebra', () async {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await const ChannelNativeEdit().send(EditAction.copy);
  });
}
