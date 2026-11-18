import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import 'dragged_image.dart';

/// Recebe arquivos arrastados do Finder sobre [child]; entrega os caminhos e
/// realça a borda enquanto o arquivo está por cima. É o único lugar que conhece
/// o pacote de drop.
class FileDropTarget extends StatefulWidget {
  const FileDropTarget({
    required this.onFiles,
    required this.child,
    this.onImage,
    super.key,
  });

  final void Function(List<String> paths) onFiles;

  /// Imagem solta SEM arquivo (PNG ou TIFF da área de arrasto, já em PNG). Sem
  /// isto, um arrasto assim é ignorado.
  final void Function(Uint8List png)? onImage;
  final Widget child;

  @override
  State<FileDropTarget> createState() => _FileDropTargetState();
}

class _FileDropTargetState extends State<FileDropTarget> {
  var _over = false;

  Future<void> _dropImage() async {
    final png = await readDraggedImage();
    if (png != null && mounted) widget.onImage!(png);
  }

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => setState(() => _over = true),
    onDragExited: (_) => setState(() => _over = false),
    onDragDone: (detail) {
      setState(() => _over = false);
      final paths = [
        for (final file in detail.files)
          if (file.path.isNotEmpty) file.path,
      ];
      if (paths.isNotEmpty) {
        widget.onFiles(paths);
      } else if (widget.onImage != null) {
        unawaited(_dropImage());
      }
    },
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: _over ? Border.all(color: AppColors.accent, width: 2) : null,
      ),
      child: widget.child,
    ),
  );
}
