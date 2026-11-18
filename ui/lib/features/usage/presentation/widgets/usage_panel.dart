import 'package:flutter/widgets.dart';

import '../../../../commons/utils/agent_palette.dart';
import '../../../../commons/widgets/glyphs.dart';
import '../../../../commons/widgets/hand_cursor.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/usage_view.dart';

/// As cores das quatro tarifas, as mesmas na barra e na legenda.
abstract final class TariffColors {
  static Color of(Tariff tariff) => switch (tariff) {
    Tariff.input => const Color(0xFF669EFF),
    Tariff.output => const Color(0xFFC787FA),
    Tariff.cacheWrite => const Color(0xFFF5A84D),
    Tariff.cacheRead => const Color(0xFF54D1BD),
  };

  /// A cor da família do modelo; a que não se conhece fica cinza.
  static Color family(String? family) {
    final key = family?.toLowerCase() ?? '';
    if (key.contains('opus')) return const Color(0xFFC787FA);
    if (key.contains('sonnet')) return const Color(0xFF669EFF);
    if (key.contains('haiku')) return const Color(0xFF54D18C);
    if (key.contains('fable') || key.contains('mythos')) {
      return const Color(0xFFF5A84D);
    }
    return AppColors.white(0.45);
  }
}

/// O detalhe do consumo de uma bancada (ADR-085): o total e para onde ele foi,
/// cada agente e cada modelo com a sua barra, e a tabela de preços recolhida
/// embaixo. Tudo vem pronto do core.
class UsagePanel extends StatefulWidget {
  const UsagePanel({required this.panel, this.pricesOpen = false, super.key});

  final UsagePanelView panel;
  final bool pricesOpen;

  static const width = 400.0;
  static const background = Color(0xFF1D1D1D);

  @override
  State<UsagePanel> createState() => _UsagePanelState();
}

class _UsagePanelState extends State<UsagePanel> {
  late var _pricesOpen = widget.pricesOpen;

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    return ColoredBox(
      color: UsagePanel.background,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              panel.heading.toUpperCase(),
              style: _text(10, 0.42, bold: true, spacing: 0.8),
            ),
            const SizedBox(height: 6),
            Stack(
              children: [
                SizedBox(
                  height: 36,
                  child: Text(
                    panel.totalAmount,
                    key: const ValueKey('usage-total'),
                    style: _text(30, 0.96, mono: true, semi: true),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 16,
                  child: Text(
                    panel.totalTokens,
                    key: const ValueKey('usage-tokens'),
                    style: _text(11, 0.45, mono: true, medium: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _StackedBar(
              parts: [
                for (final share in panel.split)
                  (TariffColors.of(share.tariff), share.dollars),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              runSpacing: 6,
              children: [
                for (final share in panel.split)
                  SizedBox(
                    width: (UsagePanel.width - 40 - 16) / 2,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: _LegendItem(share: share),
                    ),
                  ),
              ],
            ),
            if (panel.agents.isNotEmpty) ...[
              _Section('Agentes', panel.agents.length),
              for (final agent in panel.agents)
                _BarRow(
                  color: AgentPalette.of(agent.name),
                  row: agent,
                  keyPrefix: 'agent',
                ),
            ],
            if (panel.models.isNotEmpty) ...[
              _Section('Modelos', panel.models.length),
              for (final model in panel.models)
                _BarRow(
                  color: TariffColors.family(model.family),
                  row: model,
                  keyPrefix: 'model',
                ),
            ],
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.white(0.08)),
            _Disclosure(
              title: 'Tabela de preços',
              detail: panel.prices.openNote,
              open: _pricesOpen,
              onTap: () => setState(() => _pricesOpen = !_pricesOpen),
            ),
            if (_pricesOpen) _Prices(prices: panel.prices),
          ],
        ),
      ),
    );
  }
}

TextStyle _text(
  double size,
  double alpha, {
  bool bold = false,
  bool semi = false,
  bool medium = false,
  bool mono = false,
  double? spacing,
}) => TextStyle(
  color: AppColors.white(alpha),
  fontSize: size,
  fontWeight: bold
      ? FontWeight.w700
      : semi
      ? FontWeight.w600
      : medium
      ? FontWeight.w500
      : FontWeight.w400,
  fontFamily: mono ? 'Menlo' : null,
  letterSpacing: spacing,
  decoration: TextDecoration.none,
);

class _StackedBar extends StatelessWidget {
  const _StackedBar({required this.parts});

  final List<(Color, double)> parts;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 8,
    child: CustomPaint(
      key: const ValueKey('usage-bar'),
      painter: _BarPainter(parts),
    ),
  );
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.parts);

  final List<(Color, double)> parts;

  @override
  void paint(Canvas canvas, Size size) {
    final round = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.save();
    canvas.clipRRect(round);
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.white(0.08));
    final total = parts.fold<double>(0, (sum, p) => sum + p.$2);
    if (total > 0) {
      var x = 0.0;
      for (final (color, value) in parts) {
        final width = size.width * value / total;
        if (width <= 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(x, 0, width, size.height),
          Paint()..color = color,
        );
        x += width;
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.parts != parts;
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.share});

  final TariffShare share;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 4, right: 7),
        decoration: BoxDecoration(
          color: TariffColors.of(share.tariff),
          shape: BoxShape.circle,
        ),
      ),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(share.title, style: _text(11, 0.7, medium: true)),
                ),
                Text(
                  share.amount,
                  style: _text(11.5, 0.92, mono: true, semi: true),
                ),
              ],
            ),
            Text(share.detail, style: _text(10, 0.4, mono: true)),
          ],
        ),
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.count);

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text.rich(
      TextSpan(
        text: title.toUpperCase(),
        style: _text(10, 0.42, bold: true, spacing: 0.8),
        children: [TextSpan(text: '  $count', style: _text(10, 0.28))],
      ),
    ),
  );
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.color,
    required this.row,
    required this.keyPrefix,
  });

  final Color color;
  final UsageRow row;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey('$keyPrefix-${row.name}'),
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _text(12.5, 0.92, semi: true),
              ),
            ),
            if (row.tag != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.white(0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(row.tag!, style: _text(9.5, 0.55, semi: true)),
              ),
            ],
            const Spacer(),
            Text(row.amount, style: _text(12.5, 0.95, mono: true, semi: true)),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 4,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.white(0.07),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  key: ValueKey('$keyPrefix-bar-${row.name}'),
                  width: (box.maxWidth * row.fraction).clamp(0.0, box.maxWidth),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(row.detail, style: _text(10, 0.4, mono: true)),
      ],
    ),
  );
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
  Widget build(BuildContext context) => HandCursor(
    child: GestureDetector(
      key: const ValueKey('usage-prices-toggle'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            ChevronGlyph(
              open ? ChevronDirection.down : ChevronDirection.right,
              color: AppColors.white(0.6),
              size: 12,
            ),
            const SizedBox(width: 6),
            Text(title, style: _text(11.5, 0.8, semi: true)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _text(10.5, 0.35),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Prices extends StatelessWidget {
  const _Prices({required this.prices});

  final PriceTableView prices;

  @override
  Widget build(BuildContext context) => Column(
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
                Text(column, style: _text(9.5, 0.38, bold: true)),
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
                    style: _text(11, row.lit ? 0.9 : 0.55, semi: row.lit),
                  ),
                ),
                for (final value in row.values)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      value,
                      style: _text(11, row.lit ? 0.9 : 0.55, mono: true),
                    ),
                  ),
              ],
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(prices.originNote, style: _text(10, 0.32)),
      if (prices.ruleNote.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(prices.ruleNote, style: _text(10, 0.32)),
      ],
      if (prices.fileNote.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(prices.fileNote, style: _text(10, 0.32, mono: true)),
      ],
    ],
  );
}
