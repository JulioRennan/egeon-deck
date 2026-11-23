import 'package:flutter/widgets.dart';

import '../../../../../commons/widgets/eg/button.dart';
import '../../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../../commons/widgets/eg/layer.dart';
import '../../../../../commons/widgets/eg/menu.dart';
import '../../../../../commons/widgets/eg/popover.dart';
import '../../../../../commons/widgets/eg/pressable.dart';
import '../../../../../commons/widgets/eg/segmented_control.dart';
import '../../../../../commons/widgets/eg/tooltip.dart';
import '../../../../../theme/egeon_colors.dart';
import '../../../../../theme/egeon_tokens.dart';
import '../../../../../theme/egeon_type.dart';
import '../../domain/entities/agent_status.dart';
import '../../domain/entities/context_reading.dart';
import '../../../../../commons/utils/effort_names.dart';

/// A linha de controles do card de agente (36): pastilhas **modelo** ·
/// **esforço** · **ultracode** à esquerda e **contexto** (+ limpar)
/// à direita. Tudo o que ela mostra vem do [status] que o core manda — o nome do
/// modelo, os níveis, se o ultracode existe, o contexto.
class AgentStrip extends StatelessWidget {
  const AgentStrip({
    required this.status,
    required this.agentName,
    required this.onModel,
    required this.onEffortMove,
    required this.onEffortAuto,
    required this.onEffortSettle,
    required this.onUltracode,
    required this.onClear,
    super.key,
  });

  final AgentStatus status;
  final String agentName;
  final ValueChanged<String?> onModel;
  final ValueChanged<int> onEffortMove;
  final VoidCallback onEffortAuto;
  final VoidCallback onEffortSettle;
  final ValueChanged<bool> onUltracode;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final dial = status.dial;
    final ultra = status.ultracode;
    final groups = <Widget>[
      if (status.offersModel)
        _MenuChip(
          key: const ValueKey('model-picker'),
          caption: 'modelo',
          value: status.modelTitle,
          tooltip:
              'Modelo em uso: ${status.modelTitle} — escolher outro reinicia '
              'o terminal, a conversa continua',
          open: (anchor, onClosed) => _modelMenu(context, anchor, onClosed),
        ),
      if (status.offersEffort) ...[
        if (status.offersModel) const _Divider(),
        _MenuChip(
          key: const ValueKey('effort-picker'),
          caption: 'esforço',
          value: dial.label.isEmpty ? '—' : effortName(dial.label),
          valueKey: const ValueKey('effort-label'),
          tooltip: dial.usable
              ? 'Esforço de raciocínio — escolher outro reinicia o terminal, '
                    'a conversa continua'
              : 'Este modelo não tem esforço',
          open: dial.usable
              ? (anchor, onClosed) => _effortPopover(context, anchor, onClosed)
              : null,
        ),
      ],
      if (ultra != null && status.offersEffort)
        _SwitchChip(
          key: const ValueKey('ultracode'),
          label: 'ultracode',
          on: ultra.on && ultra.available,
          tooltip: ultra.available
              ? 'Ultracode ${ultra.on ? 'ligado' : 'desligado'} — workflow '
                    'dinâmico em toda tarefa, em qualquer esforço (precisa dos '
                    'dynamic workflows ligados no /config). Trocar reinicia o '
                    'terminal; a conversa continua'
              : 'Este modelo não tem ultracode',
          onTap: ultra.available ? () => onUltracode(!ultra.on) : null,
        ),
    ];
    final right = <Widget>[
      // Só o catálogo sabe o tamanho da janela: sem ele o grupo nem aparece.
      if (status.context != null || status.offersModel)
        _ContextChip(
          key: const ValueKey('context-chip'),
          reading: status.context,
          agentName: agentName,
          clearable: status.clearable,
          onClear: onClear,
        ),
      if (status.clearable)
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Tooltip(
            message: 'Limpar contexto',
            child: Pressable(
              key: const ValueKey('agent-clear'),
              onPressed: onClear,
              semanticLabel: 'Limpar contexto',
              builder: (context, s) => DecoratedBox(
                decoration: BoxDecoration(
                  color: s.hovered ? c.steel : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Center(
                    child: EgIcon(
                      EgIcons.rotateCcw,
                      size: 14,
                      color: s.hovered ? c.textPrimary : c.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
    // Num card estreito a linha encolhe em vez de estourar.
    return Row(
      children: [
        Flexible(
          flex: 3,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(mainAxisSize: MainAxisSize.min, children: groups),
            ),
          ),
        ),
        Flexible(
          flex: 2,
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: right),
            ),
          ),
        ),
      ],
    );
  }

  /// O menu: o mais novo de cada família com o nome de gente, as versões
  /// anteriores, os apelidos ("sempre o mais recente") e o padrão — em blocos,
  /// como o core os agrupa.
  Layer _modelMenu(BuildContext context, Rect anchor, VoidCallback onClosed) {
    final items = <MenuElement>[const MenuHeader('Modelo')];
    ModelGroup? previous;
    for (final entry in status.models) {
      if (previous != null && previous != entry.group) {
        items.add(const MenuSeparator());
      }
      previous = entry.group;
      items.add(
        MenuItem(
          entry.label,
          checked: entry.selected,
          onSelected: () => onModel(entry.value),
        ),
      );
    }
    items
      ..add(const MenuSeparator())
      ..add(const MenuHeader('Trocar retoma a conversa no novo modelo.'));
    return showMenu(
      context,
      anchor: anchor,
      width: 248,
      onClosed: onClosed,
      items: items,
    );
  }

  Layer _effortPopover(
    BuildContext context,
    Rect anchor,
    VoidCallback onClosed,
  ) => showPopover(
    context,
    anchor: anchor,
    padding: const EdgeInsets.all(6),
    onClosed: onClosed,
    builder: (context, close) {
      final c = context.eg;
      final dial = status.dial;
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 248, maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Label('Esforço'),
            _AutoRow(
              key: const ValueKey('effort-auto'),
              on: dial.auto,
              onTap: () {
                onEffortAuto();
                close();
              },
            ),
            const SizedBox(height: 4),
            Opacity(
              // Em automático a barra mostra, apagada, o nível que o modelo usa.
              opacity: dial.auto ? 0.5 : 1,
              child: SegmentedControl<int>(
                label: 'Esforço',
                value: dial.markIndex,
                onChanged: (i) {
                  onEffortMove(i);
                  onEffortSettle();
                  close();
                },
                options: [
                  for (var i = 0; i < dial.levels.length; i++)
                    SegmentOption(i, effortName(dial.levels[i])),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              child: Text(
                'Mais esforço pensa mais antes de agir e gasta mais.',
                style: EgeonType.caption.copyWith(
                  color: c.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// "Automático" no menu de esforço: o modelo escolhe o nível.
class _AutoRow extends StatelessWidget {
  const _AutoRow({required this.on, required this.onTap, super.key});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Pressable(
      onPressed: onTap,
      semanticLabel: 'Automático',
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.hovered ? c.steel : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  child: on
                      ? EgIcon(EgIcons.check, size: 14, color: c.accent)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  'Automático',
                  style: EgeonType.label.copyWith(
                    color: c.textPrimary,
                    fontSize: 13,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'o modelo escolhe',
                    textAlign: TextAlign.end,
                    style: EgeonType.caption.copyWith(
                      color: c.textMuted,
                      fontSize: 12,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
    child: Text(
      text,
      style: EgeonType.caption.copyWith(
        color: context.eg.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.22,
        decoration: TextDecoration.none,
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: SizedBox(
      width: 1,
      height: 14,
      child: ColoredBox(color: EgeonColors.overlay6),
    ),
  );
}

/// A pastilha `.ch` do DS: 24, raio 6, 12/16 w500. Aberta fica `accentSoft`.
class _ChipBody extends StatelessWidget {
  const _ChipBody({
    required this.state,
    required this.on,
    required this.children,
    this.enabled = true,
  });

  final PressState state;
  final bool on;
  final bool enabled;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final hovered = state.hovered && enabled;
    return Opacity(
      opacity: enabled ? 1 : EgeonOpacity.disabled,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: on
              ? c.accentSoft
              : hovered
              ? c.steel
              : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: SizedBox(
          height: 24,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DefaultTextStyle(
              style: EgeonType.caption.copyWith(
                color: on
                    ? c.accent
                    : hovered
                    ? c.textPrimary
                    : c.textSecondary,
                fontSize: 12,
                height: 16 / 12,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastilha que abre um menu ou popover (modelo, esforço): "legenda  valor ▾".
/// Fica ligada enquanto o menu está aberto. Sem [open], só mostra.
class _MenuChip extends StatefulWidget {
  const _MenuChip({
    required this.caption,
    required this.value,
    required this.tooltip,
    required this.open,
    this.valueKey,
    super.key,
  });

  final String caption;
  final String value;
  final Key? valueKey;
  final String tooltip;
  final Layer Function(Rect anchor, VoidCallback onClosed)? open;

  @override
  State<_MenuChip> createState() => _MenuChipState();
}

class _MenuChipState extends State<_MenuChip> {
  final _box = GlobalKey();
  bool _open = false;

  void _show() {
    final box = _box.currentContext!.findRenderObject()! as RenderBox;
    setState(() => _open = true);
    widget.open!(box.localToGlobal(Offset.zero) & box.size, () {
      if (mounted) setState(() => _open = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Tooltip(
      message: widget.tooltip,
      child: Pressable(
        key: _box,
        onPressed: widget.open == null ? null : _show,
        semanticLabel: '${widget.caption} ${widget.value}',
        builder: (context, s) => _ChipBody(
          state: s,
          on: _open,
          enabled: widget.open != null,
          children: [
            Text(
              widget.caption,
              style: TextStyle(
                color: c.textMuted,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 6),
            Text(widget.value, key: widget.valueKey),
            const SizedBox(width: 6),
            EgIcon(
              EgIcons.chevronDown,
              size: 12,
              color: _open ? c.accent : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastilha de interruptor (ultracode): o trilho de 26×16 e o nome.
class _SwitchChip extends StatelessWidget {
  const _SwitchChip({
    required this.label,
    required this.on,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool on;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        toggled: on,
        child: Pressable(
          onPressed: onTap,
          semanticLabel: label,
          builder: (context, s) => _ChipBody(
            state: s,
            on: false,
            enabled: onTap != null,
            children: [
              AnimatedContainer(
                duration: EgeonMotion.fast,
                width: 26,
                height: 16,
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: on ? c.accentPressed : c.steelActive,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: on ? c.textPrimary : c.textSecondary,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(width: 12, height: 12),
                ),
              ),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pastilha do contexto: "contexto ▬▬▬ 18%". Abre o painel com os tokens, o
/// aviso de compactação e "Limpar contexto…".
class _ContextChip extends StatefulWidget {
  const _ContextChip({
    required this.reading,
    required this.agentName,
    required this.clearable,
    required this.onClear,
    super.key,
  });

  final ContextReading? reading;
  final String agentName;
  final bool clearable;
  final VoidCallback onClear;

  @override
  State<_ContextChip> createState() => _ContextChipState();
}

class _ContextChipState extends State<_ContextChip> {
  final _box = GlobalKey();
  bool _open = false;

  static Color fill(EgeonColors c, double v) =>
      v >= 0.8 ? c.attention : c.accent;

  void _show() {
    final box = _box.currentContext!.findRenderObject()! as RenderBox;
    setState(() => _open = true);
    showPopover(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      placement: PopoverPlacement.bottomEnd,
      width: 280,
      padding: const EdgeInsets.all(12),
      onClosed: () {
        if (mounted) setState(() => _open = false);
      },
      builder: (context, close) => _ContextPanel(
        reading: widget.reading,
        clearable: widget.clearable,
        onClear: () {
          close();
          widget.onClear();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final reading = widget.reading;
    final fraction = reading?.fraction;
    return Tooltip(
      message: switch (reading) {
        final r? =>
          '${r.detail}. O CLI pode compactar a conversa antes de encher',
        null => 'Sem resposta do modelo ainda nesta conversa',
      },
      child: Pressable(
        key: _box,
        onPressed: _show,
        semanticLabel: 'Contexto em uso',
        builder: (context, s) => _ChipBody(
          state: s,
          on: _open,
          children: [
            Text(
              'contexto',
              style: TextStyle(
                color: c.textMuted,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 56,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.steelActive,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: fraction == null
                    ? null
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: fraction < 0.02 ? 0.02 : fraction,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: fill(c, fraction),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              reading?.text ?? '—',
              key: const ValueKey('context-pct'),
              style: EgeonType.monoMeta.copyWith(
                fontSize: 11,
                color: _open ? c.accent : null,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContextPanel extends StatelessWidget {
  const _ContextPanel({
    required this.reading,
    required this.clearable,
    required this.onClear,
  });

  final ContextReading? reading;
  final bool clearable;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final r = reading;
    final fraction = r?.fraction;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                'Contexto',
                style: EgeonType.label.copyWith(
                  color: c.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            Text(
              r?.text ?? '—',
              style: EgeonType.monoMeta.copyWith(
                color: c.textSecondary,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 8),
          child: SizedBox(
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.steelActive,
                borderRadius: BorderRadius.circular(3),
              ),
              child: fraction == null
                  ? null
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: fraction < 0.02 ? 0.02 : fraction,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _ContextChipState.fill(c, fraction),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        Text(
          r == null
              ? 'Sem resposta do modelo ainda'
              : '${ContextReading.short(r.used)} de '
                    '${ContextReading.short(r.window)} tokens',
          key: const ValueKey('context-tokens'),
          style: EgeonType.monoMeta.copyWith(
            color: c.textSecondary,
            fontSize: 12,
            height: 18 / 12,
            decoration: TextDecoration.none,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Compacta sozinho perto de 90%.',
            style: EgeonType.caption.copyWith(
              color: c.textMuted,
              fontSize: 12,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        if (clearable)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
              alignment: Alignment.centerRight,
              child: Button(
                key: const ValueKey('context-clear'),
                label: 'Limpar contexto…',
                size: ButtonSize.sm,
                kind: ButtonKind.secondary,
                onPressed: onClear,
              ),
            ),
          ),
      ],
    );
  }
}
