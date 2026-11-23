import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'agent_name.dart';
import 'eg_icon.dart';
import 'icon_button.dart';
import 'identity.dart';
import 'layer.dart';
import 'spinner.dart';

/// O tom do aviso (DS `Toast`): cada um com a sua forma e a sua cor.
enum ToastTone { attention, success, danger, running, info }

/// Quanto do pé da tela outras camadas fixas (o composer, os pedidos de
/// permissão) já ocupam: o aviso sobe por cima. Quem manda nele é a casca.
final ValueNotifier<double> toastBottomInset = ValueNotifier(0);

Layer? _current;
Timer? _timer;

/// Aviso passageiro no pé da tela, sem tirar o foco de ninguém. Um de cada
/// vez: o novo toma o lugar do que estava. Some sozinho em [duration]; o
/// "Dispensar" fecha antes. [actions] recebe o `close` do aviso.
Layer showToast(
  BuildContext context, {
  required String title,
  ToastTone tone = ToastTone.info,
  String? description,
  Person? agent,
  List<Widget> Function(VoidCallback close)? actions,
  Duration duration = const Duration(seconds: 4),
}) {
  _timer?.cancel();
  _current?.close();
  final layer = showLayer(
    context,
    dismissOnOutside: false,
    dismissOnEscape: false,
    passThrough: true,
    onClosed: () {
      _timer?.cancel();
      _current = null;
    },
    builder: (context, layer) => Align(
      alignment: Alignment.bottomCenter,
      child: ValueListenableBuilder<double>(
        valueListenable: toastBottomInset,
        builder: (context, inset, child) => Padding(
          padding: EdgeInsets.only(bottom: EgeonSpace.s6 + inset),
          child: child,
        ),
        child: LayerEntrance(
          duration: EgeonMotion.base,
          offset: const Offset(0, 8),
          child: Toast(
            title: title,
            tone: tone,
            description: description,
            agent: agent,
            actions: actions?.call(layer.close) ?? const [],
            onDismiss: layer.close,
          ),
        ),
      ),
    ),
  );
  _current = layer;
  _timer = Timer(duration, layer.close);
  return layer;
}

/// O corpo do aviso: `carbon`, raio 12, `shadow-float`; ícone do tom, título
/// (com o nome do agente na cor dele), descrição, ações e "Dispensar".
class Toast extends StatelessWidget {
  const Toast({
    required this.title,
    this.tone = ToastTone.info,
    this.description,
    this.agent,
    this.actions = const [],
    this.onDismiss,
    super.key,
  });

  final String title;
  final ToastTone tone;
  final String? description;
  final Person? agent;
  final List<Widget> actions;

  /// O botão "Dispensar" (ghost, ícone x) no canto.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final Widget icon = switch (tone) {
      ToastTone.attention => EgIcon(EgIcons.hand, color: c.attention),
      ToastTone.success => EgIcon(EgIcons.check, color: c.success),
      ToastTone.danger => EgIcon(EgIcons.octagon, color: c.danger),
      ToastTone.running => const Spinner(size: 16),
      ToastTone.info => EgIcon(EgIcons.info, color: c.textSecondary),
    };
    final titleStyle = EgeonType.label.copyWith(
      color: c.textPrimary,
      decoration: TextDecoration.none,
    );
    return Semantics(
      liveRegion: true,
      child: SizedBox(
        width: 360,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.carbon,
            borderRadius: BorderRadius.circular(EgeonRadius.lg),
            boxShadow: EgeonShadow.float,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              EgeonSpace.s4,
              EgeonSpace.s3,
              EgeonSpace.s3,
              EgeonSpace.s3,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: icon),
                const SizedBox(width: EgeonSpace.s3),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              if (agent != null)
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      right: EgeonSpace.s1,
                                    ),
                                    child: AgentName(
                                      agent!.name,
                                      identity: agent!.identity,
                                      address: agent!.address,
                                    ),
                                  ),
                                ),
                              TextSpan(text: title),
                            ],
                          ),
                          style: titleStyle,
                        ),
                        if (description != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              description!,
                              style: EgeonType.small.copyWith(
                                color: c.textSecondary,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        if (actions.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: EgeonSpace.s2),
                            child: Wrap(
                              spacing: EgeonSpace.s2,
                              runSpacing: EgeonSpace.s2,
                              children: actions,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: EgeonSpace.s2),
                IconButton(
                  icon: EgIcons.x,
                  tooltip: 'Dispensar',
                  compact: true,
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
