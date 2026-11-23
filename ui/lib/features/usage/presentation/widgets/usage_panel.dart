import 'package:flutter/widgets.dart';

import '../../../../commons/utils/agent_identity.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/icon_button.dart' as eg;
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/segmented_control.dart';
import '../../../../commons/widgets/eg/usage_bar.dart' as bar;
import '../../../../core/domain/entities/workbench_clock.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../domain/entities/usage_view.dart';

/// Qual lista o painel mostra.
enum UsageGroup { agents, models }

/// O painel de consumo da bancada, aberto sobre o chip: o título, os tempos
/// (trabalhando, esperando você) e o total, a barra por tarifa, a lista **Por
/// agente | Por modelo** e, no pé, a tabela de preços e "Zerar cronômetro".
/// Tudo vem pronto do core ([panel] e [clock]); a UI só mostra.
class UsagePanel extends StatefulWidget {
  const UsagePanel({
    required this.panel,
    this.clock,
    this.onReset,
    this.onClose,
    this.headingColor,
    this.pricesOpen = false,
    super.key,
  });

  /// A cor da bancada, no nome do cabeçalho.
  final Color? headingColor;

  final UsagePanelView panel;

  /// Os tempos da bancada; sem eles (ainda não rodou), a faixa de tempos some.
  final WorkbenchClock? clock;

  /// "Zerar cronômetro": sem ouvinte (ou sem relógio), o botão não aparece.
  final VoidCallback? onReset;
  final VoidCallback? onClose;
  final bool pricesOpen;

  static const width = 400.0;

  @override
  State<UsagePanel> createState() => _UsagePanelState();
}

class _UsagePanelState extends State<UsagePanel> {
  var _group = UsageGroup.agents;
  late var _pricesOpen = widget.pricesOpen;

  static bar.Tariff _tariff(Tariff t) => switch (t) {
    Tariff.output => bar.Tariff.output,
    Tariff.input => bar.Tariff.input,
    Tariff.cacheWrite => bar.Tariff.cacheWrite,
    Tariff.cacheRead => bar.Tariff.cacheRead,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final panel = widget.panel;
    final clock = widget.clock;
    final rows = switch (_group) {
      UsageGroup.agents => panel.agents,
      UsageGroup.models => panel.models,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  panel.heading,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: EgeonType.label.copyWith(
                    fontSize: 13,
                    height: 18 / 13,
                    fontWeight: FontWeight.w600,
                    color: widget.headingColor ?? c.textPrimary,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (widget.onClose != null)
                eg.IconButton(
                  key: const ValueKey('usage-close'),
                  icon: EgIcons.x,
                  tooltip: 'Recolher consumo',
                  compact: true,
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
        // O resto rola junto: com a tabela de preços aberta, o painel passa da
        // tela.
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (clock != null) ...[
                        Expanded(
                          child: _Stat(
                            label: 'Trabalhando',
                            icon: EgIcons.hammer,
                            tint: c.running,
                            value: WorkbenchClock.format(clock.running),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Stat(
                            label: 'Parado',
                            icon: EgIcons.hand,
                            tint: c.attention,
                            value: WorkbenchClock.format(clock.waiting),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: _Stat(
                          label: 'Total',
                          value: panel.totalAmount,
                          valueKey: const ValueKey('usage-total'),
                          note: panel.totalTokens,
                          noteKey: const ValueKey('usage-tokens'),
                        ),
                      ),
                    ],
                  ),
                ),
                // A faixa de 4 do topo: um trecho por agente, na cor dele.
                if (panel.agents.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: _AgentBar(agents: panel.agents),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedControl<UsageGroup>(
                      label: 'Agrupar o consumo',
                      value: _group,
                      onChanged: (g) => setState(() => _group = g),
                      options: [
                        const SegmentOption(UsageGroup.agents, 'Por agente'),
                        const SegmentOption(UsageGroup.models, 'Por modelo'),
                      ],
                    ),
                  ),
                ),
                const _Rule(),
                // Por modelo: a divisão por tarifa, com a legenda.
                if (_group == UsageGroup.models && panel.split.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: bar.UsageBar(
                      segments: [
                        for (final share in panel.split)
                          bar.UsageSegment(
                            value: share.dollars,
                            display: share.amount,
                            tariff: _tariff(share.tariff),
                            tokens: share.detail,
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final row in rows)
                        _Row(
                          row: row,
                          keyPrefix: _group == UsageGroup.agents
                              ? 'agent'
                              : 'model',
                          color: _group == UsageGroup.agents
                              ? agentIdentity(row.name).color(c)
                              : c.accent,
                        ),
                    ],
                  ),
                ),
                const _Rule(),
                _Disclosure(
                  title: 'Tabela de preços',
                  detail: widget.panel.prices.openNote,
                  open: _pricesOpen,
                  onTap: () => setState(() => _pricesOpen = !_pricesOpen),
                ),
                if (_pricesOpen)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: _Prices(prices: panel.prices),
                  ),
                if (widget.onReset != null && clock != null) ...[
                  const _Rule(),
                  SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Pressable(
                          key: const ValueKey('usage-reset'),
                          onPressed: widget.onReset,
                          semanticLabel: 'Zerar cronômetro',
                          builder: (context, st) => DecoratedBox(
                            decoration: BoxDecoration(
                              color: st.hovered ? EgeonColors.overlay4 : null,
                              borderRadius: BorderRadius.circular(
                                EgeonRadius.md,
                              ),
                            ),
                            child: SizedBox(
                              height: 28,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Center(
                                  widthFactor: 1,
                                  child: Text(
                                    'Zerar cronômetro',
                                    style: EgeonType.label.copyWith(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                      color: c.danger,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A divisória de 1px (`overlay6`) entre as zonas do painel.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: ColoredBox(color: EgeonColors.overlay6));
}

/// A faixa de 4 do topo: cada agente é um trecho na cor dele, do tamanho do que
/// gastou (a fração de cada um é relativa ao maior), com vão de 2.
class _AgentBar extends StatelessWidget {
  const _AgentBar({required this.agents});

  final List<UsageRow> agents;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final total = agents.fold<double>(0, (a, r) => a + r.fraction);
    return Semantics(
      label: agents.map((r) => '${r.name} ${r.amount}').join(', '),
      child: ClipRRect(
        key: const ValueKey('usage-agent-bar'),
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 4,
          child: Row(
            // Sem esticar, o trecho (um ColoredBox sem filho) ficaria com altura
            // zero e a faixa não se veria.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, r) in agents.indexed) ...[
                if (i > 0) const SizedBox(width: 2),
                Expanded(
                  flex: total == 0
                      ? 1
                      : (r.fraction / total * 10000).round().clamp(1, 10000),
                  child: ColoredBox(
                    key: ValueKey('usage-agent-seg-${r.name}'),
                    color: agentIdentity(r.name).color(c),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Um número do topo do painel: rótulo em 12 muted e o valor em mono.
class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.icon,
    this.tint,
    this.note,
    this.valueKey,
    this.noteKey,
  });

  final String label;
  final String value;
  final EgIconData? icon;
  final Color? tint;
  final String? note;
  final Key? valueKey;
  final Key? noteKey;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              EgIcon(icon!, size: 13, color: tint ?? c.textSecondary),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EgeonType.caption.copyWith(
                  fontSize: 12,
                  height: 16 / 12,
                  color: c.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Flexible(
              child: Text(
                value,
                key: valueKey,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EgeonType.monoMeta.copyWith(
                  fontSize: 20,
                  height: 26 / 20,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
        if (note != null)
          Text(
            note!,
            key: noteKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EgeonType.monoMeta.copyWith(
              color: c.textMuted,
              decoration: TextDecoration.none,
            ),
          ),
      ],
    );
  }
}

/// Uma linha de agente ou modelo: nome na cor, custo, "N turnos · tokens" e a
/// barra proporcional ao maior.
class _Row extends StatelessWidget {
  const _Row({required this.row, required this.keyPrefix, required this.color});

  final UsageRow row;
  final String keyPrefix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Padding(
      key: ValueKey('$keyPrefix-${row.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // O nome (e a etiqueta) toma o vão; o custo fica na ponta direita.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: EgeonType.label.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: color,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    if (row.tag != null) ...[
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.steel,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          child: Text(
                            row.tag!,
                            style: EgeonType.monoMeta.copyWith(
                              fontSize: 11,
                              color: c.textSecondary,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                row.amount,
                style: EgeonType.monoMeta.copyWith(
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 3,
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: EgeonColors.overlay6,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: const SizedBox.expand(),
                  ),
                  Container(
                    key: ValueKey('$keyPrefix-bar-${row.name}'),
                    width: (box.maxWidth * row.fraction).clamp(
                      0.0,
                      box.maxWidth,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            row.detail,
            textAlign: TextAlign.right,
            style: EgeonType.monoMeta.copyWith(
              color: c.textSecondary,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// "▸ Tabela de preços": o clique abre e fecha.
class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.title,
    required this.detail,
    required this.open,
    required this.onTap,
  });

  final String title;
  final String detail;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Pressable(
      key: const ValueKey('usage-prices-toggle'),
      onPressed: onTap,
      semanticLabel: title,
      builder: (context, s) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          children: [
            AnimatedRotation(
              turns: open ? 0.25 : 0,
              duration: EgeonMotion.fast,
              child: EgIcon(
                EgIcons.chevronRight,
                size: 12,
                color: s.hovered ? c.textPrimary : c.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: EgeonType.label.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: s.hovered ? c.textPrimary : c.textSecondary,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EgeonType.caption.copyWith(
                  color: c.textMuted,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Prices extends StatelessWidget {
  const _Prices({required this.prices});

  final PriceTableView prices;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    TextStyle mono(Color color, {FontWeight? weight}) =>
        EgeonType.monoMeta.copyWith(
          fontSize: 11,
          fontWeight: weight,
          color: color,
          decoration: TextDecoration.none,
        );
    return Column(
      key: const ValueKey('usage-prices'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(2.2)},
          defaultColumnWidth: const FlexColumnWidth(),
          children: [
            TableRow(
              children: [
                for (final column in prices.columns)
                  Text(
                    column,
                    style: mono(c.textMuted, weight: FontWeight.w600),
                  ),
              ],
            ),
            for (final row in prices.rows)
              TableRow(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${row.lit ? '● ' : ''}${row.edited ? '✎ ' : ''}${row.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: EgeonType.caption.copyWith(
                        color: row.lit ? c.textPrimary : c.textSecondary,
                        fontWeight: row.lit ? FontWeight.w600 : null,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                  for (final value in row.values)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        value,
                        style: mono(row.lit ? c.textPrimary : c.textSecondary),
                      ),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          prices.originNote,
          style: EgeonType.caption.copyWith(
            color: c.textMuted,
            decoration: TextDecoration.none,
          ),
        ),
        if (prices.ruleNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              prices.ruleNote,
              style: EgeonType.caption.copyWith(
                color: c.textMuted,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        if (prices.fileNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(prices.fileNote, style: mono(c.textMuted)),
          ),
      ],
    );
  }
}
