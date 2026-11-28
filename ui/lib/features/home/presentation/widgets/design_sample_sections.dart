import 'package:flutter/widgets.dart';

import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_glass.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';

class SampleSection extends StatelessWidget {
  const SampleSection(this.title, this.child, {super.key});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: EgeonSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: EgeonType.heading.copyWith(color: context.eg.textPrimary),
          ),
          const SizedBox(height: EgeonSpace.s3),
          child,
        ],
      ),
    );
  }
}

class SampleSwatch extends StatelessWidget {
  const SampleSwatch(this.name, this.color, {this.textColor, super.key});

  final String name;
  final Color color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Container(
      width: 132,
      height: 64,
      padding: const EdgeInsets.all(EgeonSpace.s2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(EgeonRadius.md),
        border: Border.all(color: c.line, width: EgeonBorder.hairline),
      ),
      alignment: Alignment.bottomLeft,
      child: Text(
        name,
        style: EgeonType.monoMeta.copyWith(color: textColor ?? c.textSecondary),
      ),
    );
  }
}

class SampleWrap extends StatelessWidget {
  const SampleWrap(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: EgeonSpace.s2,
    runSpacing: EgeonSpace.s2,
    children: children,
  );
}

class SampleSurfaces extends StatelessWidget {
  const SampleSurfaces({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return SampleWrap([
      SampleSwatch('obsidian', c.obsidian),
      SampleSwatch('graphite', c.graphite),
      SampleSwatch('carbon', c.carbon),
      SampleSwatch('steel', c.steel),
      SampleSwatch('steel-active', c.steelActive),
      SampleSwatch('line', c.line),
      SampleSwatch('line-strong', c.lineStrong),
      SampleSwatch('accent', c.accent, textColor: c.onAccent),
      SampleSwatch('primary', c.primary, textColor: c.onPrimary),
    ]);
  }
}

class SampleTextColors extends StatelessWidget {
  const SampleTextColors({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    Widget line(String name, Color color) => Text(
      '$name — Atualizado há 2 min',
      style: EgeonType.body.copyWith(color: color),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('text-primary', c.textPrimary),
        line('text-secondary', c.textSecondary),
        line('text-muted', c.textMuted),
        line('text-disabled', c.textDisabled),
        line('accent', c.accent),
      ],
    );
  }
}

class SampleStates extends StatelessWidget {
  const SampleStates({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    Widget state(String name, Color color, Color soft) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: EgeonSpace.s3,
        vertical: EgeonSpace.s2,
      ),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(EgeonRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: EgeonSize.dot,
            height: EgeonSize.dot,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: EgeonSpace.s2),
          Text(name, style: EgeonType.label.copyWith(color: color)),
        ],
      ),
    );
    return SampleWrap([
      state('attention', c.attention, c.attentionSoft),
      state('running', c.running, c.runningSoft),
      state('success', c.success, c.successSoft),
      state('danger', c.danger, c.dangerSoft),
      state('waiting', c.waiting, c.waitingSoft),
    ]);
  }
}

class SampleIdentities extends StatelessWidget {
  const SampleIdentities({super.key});

  static const _names = [
    'sky',
    'iris',
    'orchid',
    'teal',
    'slate',
    'sand',
    'mauve',
    'jade',
    'olive',
    'rose',
    'clay',
    'moss',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final colors = c.identities;
    return SampleWrap([
      for (var i = 0; i < colors.length; i++)
        Container(
          width: 132,
          padding: const EdgeInsets.all(EgeonSpace.s3),
          decoration: BoxDecoration(
            color: c.carbon,
            borderRadius: BorderRadius.circular(EgeonRadius.md),
            border: Border.all(color: c.line),
          ),
          child: Text(
            _names[i],
            style: EgeonType.label.copyWith(color: colors[i]),
          ),
        ),
    ]);
  }
}

class SampleTypeScale extends StatelessWidget {
  const SampleTypeScale({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    Widget row(String name, TextStyle style, String sample) => Padding(
      padding: const EdgeInsets.only(bottom: EgeonSpace.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              name,
              style: EgeonType.monoMeta.copyWith(color: c.textMuted),
            ),
          ),
          Flexible(
            child: Text(sample, style: style.copyWith(color: c.textPrimary)),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('display', EgeonType.display, 'Nenhum agente precisa de você'),
        row('title', EgeonType.title, 'Novo workspace'),
        row('heading', EgeonType.heading, 'Bancadas ativas'),
        row(
          'body',
          EgeonType.body,
          'Texto corrido das mensagens do chat e descrições.',
        ),
        row('label', EgeonType.label, 'Abrir bancada'),
        row('small', EgeonType.small, 'Atualizado há 2 min'),
        row('caption', EgeonType.caption, 'PERMISSÃO'),
        row('terminal', EgeonType.terminal, r'$ claude --resume egeon-ui'),
        row('code', EgeonType.code, "const bench = workspace.open('api');"),
        row('mono-meta', EgeonType.monoMeta, '12:04 · \$0,42 · 61% ctx'),
        row(
          'itálico',
          EgeonType.code.copyWith(fontStyle: FontStyle.italic),
          '// comentário de sintaxe em itálico',
        ),
      ],
    );
  }
}

class SampleGridPainter extends CustomPainter {
  const SampleGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 16) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(SampleGridPainter old) => old.color != color;
}

class SampleGlassOverGrid extends StatelessWidget {
  const SampleGlassOverGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return SizedBox(
      width: 480,
      height: 160,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: SampleGridPainter(c.accent.withValues(alpha: 0.5)),
            ),
          ),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(EgeonRadius.xl),
                boxShadow: EgeonShadow.glass,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(EgeonRadius.xl),
                child: BackdropFilter(
                  filter: EgeonGlass.filter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: EgeonGlass.background,
                      borderRadius: BorderRadius.circular(EgeonRadius.xl),
                      border: Border.all(color: EgeonGlass.border),
                    ),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: EgeonSpace.s6,
                            vertical: EgeonSpace.s4,
                          ),
                          child: Text(
                            'Painel de vidro',
                            style: EgeonType.label.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        // O inset de 1px do CSS: um fio claro no topo.
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 1,
                          child: ColoredBox(color: EgeonGlass.highlight),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SampleGlyphs extends StatelessWidget {
  const SampleGlyphs({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏',
          style: EgeonType.terminal.copyWith(color: c.textPrimary),
        ),
        Text(
          '─ │ ┌ ┐ └ ┘ █ ░ ▒ ▓',
          style: EgeonType.terminal.copyWith(color: c.textPrimary),
        ),
        Text('← → ↑ ↓', style: EgeonType.small.copyWith(color: c.textPrimary)),
        Text(
          '⌘ ⌥ ⇧ ⌃ ⌘⌥1',
          style: EgeonType.small.copyWith(color: c.textPrimary),
        ),
      ],
    );
  }
}
