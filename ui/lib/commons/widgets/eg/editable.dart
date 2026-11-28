import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// O texto editável de [TextField] e [TextArea]: um `EditableText` com o
/// detector de gestos de seleção (clique põe o cursor, arrasto seleciona,
/// duplo clique pega a palavra). O visual é de quem o usa.
class Editable extends StatefulWidget {
  const Editable({
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.cursorColor,
    required this.selectionColor,
    this.maxLines = 1,
    this.minLines,
    this.obscureText = false,
    this.readOnly = false,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final Color cursorColor;
  final Color selectionColor;
  final int? maxLines;
  final int? minLines;
  final bool obscureText;
  final bool readOnly;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<Editable> createState() => _EditableState();
}

class _EditableState extends State<Editable>
    implements TextSelectionGestureDetectorBuilderDelegate {
  @override
  final editableTextKey = GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  late final _gestures = TextSelectionGestureDetectorBuilder(delegate: this);

  @override
  Widget build(BuildContext context) {
    return _gestures.buildGestureDetector(
      behavior: HitTestBehavior.translucent,
      child: EditableText(
        key: editableTextKey,
        controller: widget.controller,
        focusNode: widget.focusNode,
        style: widget.style,
        cursorColor: widget.cursorColor,
        backgroundCursorColor: widget.selectionColor,
        selectionColor: widget.selectionColor,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        obscureText: widget.obscureText,
        readOnly: widget.readOnly,
        rendererIgnoresPointer: true,
        inputFormatters: widget.inputFormatters,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}
