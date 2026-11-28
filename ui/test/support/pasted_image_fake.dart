import 'dart:typed_data';

import 'package:egeon_deck/features/node/queue/domain/repository/queue_repository.dart';

abstract final class PastedImageFake {
  static PastedImage make(String name) =>
      PastedImage(name: name, bytes: Uint8List.fromList([1, 2, 3]));
}

/// Bytes de mentira para o print.
abstract final class Uint8ListFake {
  static final bytes = Uint8List.fromList([1, 2, 3]);
}
