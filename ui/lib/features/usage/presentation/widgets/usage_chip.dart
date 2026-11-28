import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/glass_surface.dart';
import '../../../../commons/widgets/eg/identity.dart';
import '../../../../commons/widgets/eg/layer.dart';
import '../../../../commons/widgets/eg/popover.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/tooltip.dart';
import '../../../../commons/widgets/eg/workbench_clock.dart' as eg;
import '../../../../core/domain/entities/workbench_clock.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/usage_view.dart';
import '../cubit/usage_cubit.dart';
import 'usage_panel.dart';

/// O consumo no canto (U1): numa peça de vidro, o cronômetro da bancada
/// (martelo e mão) e o custo; o clique abre o painel embaixo, e o chip fica
/// marcado enquanto ele está aberto. Sem painel do core, não abre.
class UsageChip extends StatefulWidget {
  const UsageChip({this.clock, this.onReset, this.identity, super.key});

  /// A identidade (cor) da bancada, no nome do painel.
  final Identity? identity;

  /// Os tempos da bancada; ausente até ela ter rodado.
  final WorkbenchClock? clock;
  final VoidCallback? onReset;

  /// 46 de altura: 36 do botão e 5 de respiro de cada lado.
  static const height = 46.0;

  @override
  State<UsageChip> createState() => _UsageChipState();
}

class _UsageChipState extends State<UsageChip> {
  final _box = GlobalKey();
  final _glass = GlobalKey();
  Layer? _layer;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _layer?.close();
    super.dispose();
  }

  void _toggle(UsageView view) {
    if (_layer?.isOpen ?? false) {
      _layer!.close();
      return;
    }
    final panel = view.panel;
    if (panel == null) return;
    // O painel nasce 8 abaixo do chip inteiro, não só do botão de dentro.
    final box = _glass.currentContext!.findRenderObject()! as RenderBox;
    setState(() {});
    _layer = showPopover(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      placement: PopoverPlacement.bottomEnd,
      width: UsagePanel.width,
      padding: EdgeInsets.zero,
      radius: 16,
      gap: 8,
      onClosed: () {
        if (mounted && !_disposed) setState(() {});
      },
      builder: (context, close) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: (MediaQuery.sizeOf(context).height - 120).clamp(
            240.0,
            640.0,
          ),
        ),
        child: UsagePanel(
          panel: panel,
          clock: widget.clock,
          onReset: widget.onReset == null
              ? null
              : () {
                  close();
                  widget.onReset!();
                },
          onClose: close,
          headingColor: widget.identity?.color(context.eg),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<UsageCubit, UsageState>(
    builder: (context, state) {
      final view = switch (state) {
        UsageWaiting() => const UsageView(),
        UsageShown(:final view) => view,
      };
      final c = context.eg;
      final open = _layer?.isOpen ?? false;
      final clock = widget.clock;
      return GlassSurface(
        key: _glass,
        radius: EgeonRadius.xl,
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        child: Tooltip(
          message: view.pill.tooltip ?? 'Consumo da bancada',
          child: Pressable(
            key: _box,
            onPressed: view.panel == null ? null : () => _toggle(view),
            semanticLabel: 'Consumo da bancada',
            builder: (context, s) => DecoratedBox(
              decoration: BoxDecoration(
                color: open
                    ? c.accentSoft
                    : s.hovered
                    ? EgeonColors.overlay4
                    : null,
                borderRadius: BorderRadius.circular(EgeonRadius.md),
              ),
              child: SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (clock != null) ...[
                        _Phase(
                          icon: EgIcons.hammer,
                          tint: c.running,
                          seconds: clock.running,
                        ),
                        const SizedBox(width: 10),
                        _Phase(
                          icon: EgIcons.hand,
                          tint: c.attention,
                          seconds: clock.waiting,
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 1,
                          height: 14,
                          child: ColoredBox(color: EgeonColors.overlay10),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        view.pill.text,
                        key: const ValueKey('usage-pill-text'),
                        maxLines: 1,
                        style: EgeonType.monoMeta.copyWith(
                          color: c.textPrimary,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(width: 10),
                      EgIcon(
                        EgIcons.chevronDown,
                        size: 12,
                        color: c.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Um tempo do chip: ícone na cor da fase e o `mm:ss` em mono. Só há dois
/// (trabalhando e parado); o erro aparece no painel, não aqui.
class _Phase extends StatelessWidget {
  const _Phase({required this.icon, required this.tint, required this.seconds});

  final EgIconData icon;
  final Color tint;
  final double seconds;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      EgIcon(icon, size: 13, color: tint),
      const SizedBox(width: 4),
      Text(
        eg.WorkbenchClock.format(Duration(seconds: seconds.floor())),
        style: EgeonType.monoMeta.copyWith(
          color: context.eg.textPrimary,
          decoration: TextDecoration.none,
        ),
      ),
    ],
  );
}
