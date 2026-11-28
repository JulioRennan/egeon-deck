import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'eg_icon.dart';
import 'layer.dart';

/// Abre um diálogo modal, centrado, sobre o `scrim`. O [Future] completa com o
/// valor passado a `close` (ou `null` ao fechar por Esc ou clique fora, se
/// [barrierDismissible]). Diálogo é sólido: sem vidro.
Future<T?> showEgDialog<T>(
  BuildContext context, {
  required Widget Function(
    BuildContext context,
    void Function([T? result]) close,
  )
  builder,
  bool barrierDismissible = true,
}) {
  final completer = Completer<T?>();
  showLayer(
    context,
    barrierColor: context.eg.scrim,
    dismissOnOutside: barrierDismissible,
    dismissOnEscape: barrierDismissible,
    onClosed: () {
      if (!completer.isCompleted) completer.complete(null);
    },
    builder: (context, layer) => Center(
      child: LayerEntrance(
        duration: EgeonMotion.base,
        scaleFrom: 0.98,
        child: builder(context, ([result]) {
          if (!completer.isCompleted) completer.complete(result);
          layer.close();
        }),
      ),
    ),
  );
  return completer.future;
}

/// O corpo de um diálogo: raio 14, fundo `carbon`, `shadow-modal` (o anel de
/// 1px já vem nela), respiro de 24.
class Dialog extends StatelessWidget {
  const Dialog({
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 440,
    this.icon,
    super.key,
  });

  /// O ícone do diálogo destrutivo (a lixeira): 32, raio 6, `dangerSoft`.
  final EgIconData? icon;

  final String title;
  final Widget child;

  /// Botões, alinhados à direita (o primário por último).
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.carbon,
            borderRadius: BorderRadius.circular(EgeonRadius.xl),
            boxShadow: EgeonShadow.modal,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EgeonSpace.s6,
              EgeonSpace.s6,
              EgeonSpace.s6,
              EgeonSpace.s6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (icon != null) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.dangerSoft,
                          borderRadius: BorderRadius.circular(EgeonRadius.sm),
                        ),
                        child: Center(
                          child: EgIcon(icon!, size: 16, color: c.danger),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: EgeonSpace.s2),
                ],
                Text(
                  title,
                  style: EgeonType.title.copyWith(
                    color: c.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: EgeonSpace.s2),
                DefaultTextStyle(
                  style: EgeonType.body.copyWith(
                    color: c.textSecondary,
                    decoration: TextDecoration.none,
                  ),
                  child: child,
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: EgeonSpace.s8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: EgeonSpace.s2),
                        actions[i],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
