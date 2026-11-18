import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import 'glass_panel.dart';

/// Abre uma janela modal sobre a tela e devolve o que ela fechar com. Precisa
/// de um `Overlay` acima de [context]. Esc e o clique fora cancelam (`null`).
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required Widget Function(
    BuildContext context,
    void Function([T? result]) close,
  )
  builder,
  double width = 360,
}) {
  final completer = Completer<T?>();
  late OverlayEntry entry;
  void close([T? result]) {
    if (completer.isCompleted) return;
    entry.remove();
    completer.complete(result);
  }

  entry = OverlayEntry(
    builder: (context) => _DialogLayer(
      width: width,
      onCancel: close,
      child: builder(context, close),
    ),
  );
  Overlay.of(context).insert(entry);
  return completer.future;
}

class _DialogLayer extends StatelessWidget {
  const _DialogLayer({
    required this.width,
    required this.onCancel,
    required this.child,
  });

  final double width;
  final VoidCallback onCancel;
  final Widget child;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onCancel},
    child: Focus(
      autofocus: true,
      child: Stack(
        children: [
          // Listener, e não GestureDetector: o fundo não é um botão e não leva
          // a mão do ponteiro.
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => onCancel(),
              child: ColoredBox(color: AppColors.black(0.5)),
            ),
          ),
          Center(
            child: SizedBox(
              width: width,
              child: GlassPanel(child: child),
            ),
          ),
        ],
      ),
    ),
  );
}

/// O miolo comum: título, texto de apoio, o conteúdo e a fileira de botões.
class DialogBody extends StatelessWidget {
  const DialogBody({
    required this.title,
    required this.actions,
    this.message,
    this.child,
    super.key,
  });

  final String title;
  final String? message;
  final Widget? child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFFFFFFFF),
            decoration: TextDecoration.none,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message!,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.white(0.7),
              decoration: TextDecoration.none,
            ),
          ),
        ],
        if (child != null) ...[const SizedBox(height: 14), child!],
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              actions[i],
            ],
          ],
        ),
      ],
    ),
  );
}

/// Botão de janela. [primary] é o que o Enter confirma.
class DialogButton extends StatefulWidget {
  const DialogButton(
    this.label, {
    required this.onTap,
    this.primary = false,
    this.destructive = false,
    this.enabled = true,
    this.small = false,
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool destructive;
  final bool enabled;

  /// Botão miúdo, para os que moram dentro de um formulário.
  final bool small;

  @override
  State<DialogButton> createState() => _DialogButtonState();
}

class _DialogButtonState extends State<DialogButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final base = widget.primary
        ? (widget.destructive ? const Color(0xFFFF453A) : AppColors.accent)
        : const Color(0xFFFFFFFF);
    final alpha = widget.primary
        ? (_hovering ? 1.0 : 0.9)
        : (_hovering ? 0.18 : 0.12);
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: Container(
            height: widget.small ? 22 : 28,
            constraints: BoxConstraints(minWidth: widget.small ? 0 : 84),
            padding: EdgeInsets.symmetric(horizontal: widget.small ? 10 : 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: base.withValues(alpha: alpha),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: widget.small ? 11 : 13,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFFFFFFF),
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
