import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/context_menu.dart';
import '../../../../../commons/widgets/glyphs.dart';
import '../../../../../commons/widgets/hand_cursor.dart';
import '../../../../../theme/app_colors.dart';
import '../../domain/entities/agent_status.dart';
import 'context_indicator.dart';
import 'effort_dial.dart';

/// A faixa do cabeçalho do card de agente: modelo, esforço, ultracode, o
/// contexto em uso e o botão de limpar a conversa. Rótulo em cima, controle
/// embaixo; grupos lado a lado.
///
/// Tudo o que ela mostra vem do [status] que o core manda — o nome do modelo,
/// os níveis do slider, o nível do auto, se o ultracode existe.
class AgentStrip extends StatelessWidget {
  const AgentStrip({
    required this.status,
    required this.onModel,
    required this.onEffortMove,
    required this.onEffortAuto,
    required this.onEffortSettle,
    required this.onUltracode,
    required this.onClear,
    this.tint = const Color(0xFFBF5AF2),
    this.settleDelay = const Duration(seconds: 1),
    super.key,
  });

  final AgentStatus status;
  final Color tint;
  final Duration settleDelay;
  final ValueChanged<String?> onModel;
  final ValueChanged<int> onEffortMove;
  final VoidCallback onEffortAuto;
  final VoidCallback onEffortSettle;
  final ValueChanged<bool> onUltracode;
  final VoidCallback onClear;

  static const groupGap = 20.0;

  @override
  Widget build(BuildContext context) {
    final groups = <Widget>[
      if (status.offersModel)
        _Group('modelo', _ModelPicker(status: status, onPick: onModel)),
      if (status.offersEffort)
        _Group(
          'esforço',
          EffortDial(
            view: status.dial,
            tint: tint,
            settleDelay: settleDelay,
            onMove: onEffortMove,
            onToggleAuto: onEffortAuto,
            onSettle: onEffortSettle,
          ),
        ),
      if (status.ultracode != null && status.offersEffort)
        _UltracodePill(
          state: status.ultracode!,
          tint: tint,
          onTap: () => onUltracode(!status.ultracode!.on),
        ),
      // Só o catálogo sabe o tamanho da janela: sem ele o grupo nem aparece.
      if (status.context != null || status.offersModel)
        _Group('contexto', ContextIndicator(reading: status.context)),
      if (status.clearable) _ClearButton(onTap: onClear),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(width: groupGap),
          groups[i],
        ],
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.caption, this.control);

  final String caption;
  final Widget control;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        caption,
        style: TextStyle(
          color: AppColors.white(0.32),
          fontSize: 9,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
      const SizedBox(height: 2),
      control,
    ],
  );
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({required this.status, required this.onPick});

  final AgentStatus status;
  final ValueChanged<String?> onPick;

  /// O menu: o mais novo de cada família com o nome de gente, as versões
  /// anteriores, os apelidos ("sempre o mais recente") e o padrão.
  void _open(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset(0, box.size.height + 4));
    final entries = <MenuEntry>[];
    ModelGroup? previous;
    for (final entry in status.models) {
      if (previous != null && previous != entry.group) {
        entries.add(const MenuEntry.separator());
      }
      previous = entry.group;
      entries.add(
        MenuEntry(
          entry.label,
          () => onPick(entry.value),
          leading: SizedBox(
            width: 10,
            child: entry.selected
                ? const Text(
                    '✓',
                    style: TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 11,
                      decoration: TextDecoration.none,
                    ),
                  )
                : null,
          ),
        ),
      );
    }
    showContextMenu(context, position: origin, entries: entries);
  }

  @override
  Widget build(BuildContext context) => HandCursor(
    child: GestureDetector(
      key: const ValueKey('model-picker'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _open(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            status.modelTitle,
            style: TextStyle(
              color: AppColors.white(0.82),
              fontSize: 10,
              fontWeight: FontWeight.w500,
              fontFamily: 'Menlo',
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(width: 4),
          ChevronGlyph(
            ChevronDirection.down,
            color: AppColors.white(0.5),
            size: 10,
          ),
        ],
      ),
    ),
  );
}

class _UltracodePill extends StatelessWidget {
  const _UltracodePill({
    required this.state,
    required this.tint,
    required this.onTap,
  });

  final Ultracode state;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !state.available
        ? AppColors.white(0.25)
        : state.on
        ? tint
        : AppColors.white(0.62);
    return HandCursor(
      enabled: state.available,
      child: GestureDetector(
        key: const ValueKey('ultracode'),
        behavior: HitTestBehavior.opaque,
        onTap: state.available ? onTap : null,
        child: Container(
          height: 14,
          margin: const EdgeInsets.only(top: 11),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: state.on && state.available
                ? tint.withValues(alpha: 0.18)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text(
            'ultracode',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => HandCursor(
    child: GestureDetector(
      key: const ValueKey('agent-clear'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 11),
        child: CustomPaint(
          size: const Size.square(14),
          painter: _SparklePainter(AppColors.white(0.62)),
        ),
      ),
    ),
  );
}

/// As faíscas de "limpar a conversa": uma estrela de quatro pontas e um ponto.
class _SparklePainter extends CustomPainter {
  _SparklePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final star = Path()
      ..moveTo(s * 0.4, s * 0.1)
      ..quadraticBezierTo(s * 0.44, s * 0.46, s * 0.8, s * 0.5)
      ..quadraticBezierTo(s * 0.44, s * 0.54, s * 0.4, s * 0.9)
      ..quadraticBezierTo(s * 0.36, s * 0.54, s * 0.0, s * 0.5)
      ..quadraticBezierTo(s * 0.36, s * 0.46, s * 0.4, s * 0.1);
    canvas
      ..drawPath(star, Paint()..color = color)
      ..drawCircle(
        Offset(s * 0.86, s * 0.16),
        s * 0.09,
        Paint()..color = color,
      );
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}
