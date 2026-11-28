import 'dart:convert';
import 'dart:io';

import 'package:egeon_deck/theme/egeon_colors.dart';
import 'package:egeon_deck/theme/egeon_glass.dart';
import 'package:egeon_deck/theme/egeon_terminal_palette.dart';
import 'package:egeon_deck/theme/egeon_tokens.dart';
import 'package:egeon_deck/theme/egeon_type.dart';
import 'package:flutter/animation.dart' show Cubic;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// O Dart do tema é escrito à mão (sem gerador); este teste o prende ao
// tokens.json do design system. Mudou o DS: troque a fixture e o teste aponta
// o que ficou diferente.

const c = EgeonColors.dark;

final Map<String, Color> _colors = {
  'obsidian': c.obsidian,
  'graphite': c.graphite,
  'carbon': c.carbon,
  'steel': c.steel,
  'steel-active': c.steelActive,
  'line-subtle': c.lineSubtle,
  'line': c.line,
  'line-strong': c.lineStrong,
  'line-hover': c.lineHover,
  'control-border': c.controlBorder,
  'control-border-hover': c.controlBorderHover,
  'text-primary': c.textPrimary,
  'text-secondary': c.textSecondary,
  'text-muted': c.textMuted,
  'text-disabled': c.textDisabled,
  'accent': c.accent,
  'accent-hover': c.accentHover,
  'accent-pressed': c.accentPressed,
  'accent-soft': c.accentSoft,
  'on-accent': c.onAccent,
  'primary': c.primary,
  'primary-hover': c.primaryHover,
  'primary-pressed': c.primaryPressed,
  'on-primary': c.onPrimary,
  'focus-ring': c.focusRing,
  'attention': c.attention,
  'attention-soft': c.attentionSoft,
  'running': c.running,
  'running-soft': c.runningSoft,
  'success': c.success,
  'success-soft': c.successSoft,
  'danger': c.danger,
  'danger-soft': c.dangerSoft,
  'danger-hover': c.dangerHover,
  'danger-pressed': c.dangerPressed,
  'on-attention': c.onAttention,
  'on-danger': c.onDanger,
  'waiting': c.waiting,
  'waiting-soft': c.waitingSoft,
  'id-rose': c.idRose,
  'id-clay': c.idClay,
  'id-sand': c.idSand,
  'id-olive': c.idOlive,
  'id-moss': c.idMoss,
  'id-jade': c.idJade,
  'id-teal': c.idTeal,
  'id-sky': c.idSky,
  'id-slate': c.idSlate,
  'id-iris': c.idIris,
  'id-orchid': c.idOrchid,
  'id-mauve': c.idMauve,
  'on-identity': c.onIdentity,
  'diff-add-bg': c.diffAddBg,
  'diff-add-word': c.diffAddWord,
  'diff-add-fg': c.diffAddFg,
  'diff-del-bg': c.diffDelBg,
  'diff-del-word': c.diffDelWord,
  'diff-del-fg': c.diffDelFg,
  'syn-text': c.synText,
  'syn-comment': c.synComment,
  'syn-keyword': c.synKeyword,
  'syn-string': c.synString,
  'syn-number': c.synNumber,
  'syn-function': c.synFunction,
  'syn-type': c.synType,
  'syn-constant': c.synConstant,
  'syn-tag': c.synTag,
  'syn-punct': c.synPunct,
  'term-bg': c.termBg,
  'term-fg': c.termFg,
  'term-cursor': c.termCursor,
  'term-selection': c.termSelection,
  'term-black': c.termBlack,
  'term-red': c.termRed,
  'term-green': c.termGreen,
  'term-yellow': c.termYellow,
  'term-blue': c.termBlue,
  'term-magenta': c.termMagenta,
  'term-cyan': c.termCyan,
  'term-white': c.termWhite,
  'term-bright-black': c.termBrightBlack,
  'term-bright-red': c.termBrightRed,
  'term-bright-green': c.termBrightGreen,
  'term-bright-yellow': c.termBrightYellow,
  'term-bright-blue': c.termBrightBlue,
  'term-bright-magenta': c.termBrightMagenta,
  'term-bright-cyan': c.termBrightCyan,
  'term-bright-white': c.termBrightWhite,
  'scrim': c.scrim,
  'edge': c.edge,
  'glass': EgeonGlass.background,
  'glass-border': EgeonGlass.border,
  'glass-highlight': EgeonGlass.highlight,
  'overlay-2': EgeonColors.overlay2,
  'overlay-4': EgeonColors.overlay4,
  'overlay-6': EgeonColors.overlay6,
  'overlay-8': EgeonColors.overlay8,
  'overlay-10': EgeonColors.overlay10,
  'overlay-12': EgeonColors.overlay12,
};

Map<String, dynamic> _tokens() =>
    jsonDecode(File('test/fixtures/design_tokens.json').readAsStringSync())
        as Map<String, dynamic>;

List<Map<String, dynamic>> _list(String family) =>
    ((_tokens()[family] as Map<String, dynamic>)['tokens'] as List)
        .cast<Map<String, dynamic>>();

/// `{accent}` é alias de outro token (só o `focus-ring` usa).
Color _color(String value) {
  if (!value.startsWith('{')) return _hex(value);
  final name = value.substring(1, value.length - 1);
  final target = _list('color').firstWhere((t) => t['name'] == name);
  return _hex(target['value'] as String);
}

Color _hex(String value) {
  var hex = value.substring(1);
  if (hex.length == 6) hex = '${hex}ff';
  final rgba = int.parse(hex, radix: 16);
  return Color(((rgba & 0xff) << 24) | (rgba >> 8));
}

double _px(Object? value) => double.parse('$value'.replaceAll('px', ''));

Duration _ms(String value) =>
    Duration(milliseconds: int.parse(value.replaceAll('ms', '')));

Cubic _cubic(String value) {
  final n = RegExp(r'cubic-bezier\(([^)]*)\)')
      .firstMatch(value)!
      .group(1)!
      .split(',')
      .map((e) => double.parse(e.trim()))
      .toList();
  return Cubic(n[0], n[1], n[2], n[3]);
}

Color _rgba(String value) {
  if (value.startsWith('#')) return _hex(value);
  final m = RegExp(r'rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)')
      .firstMatch(value)!;
  return Color.fromARGB(
    (double.parse(m.group(4)!) * 255).round(),
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}

/// "0 8px 24px rgba(…), 0 0 0 1px #2A3036" → camadas; o `inset` fica de fora
/// (vira `EgeonGlass.highlight`).
List<BoxShadow> _shadow(String css) {
  if (css == 'none') return const [];
  final layers = RegExp(r'(?:[^,(]|\([^)]*\))+')
      .allMatches(css)
      .map((m) => m.group(0)!.trim())
      .where((l) => !l.startsWith('inset'));
  return [
    for (final layer in layers)
      () {
        final colorAt = layer.indexOf(RegExp(r'rgba|#'));
        final nums = layer
            .substring(0, colorAt)
            .trim()
            .split(RegExp(r'\s+'))
            .map(_px)
            .toList();
        return BoxShadow(
          offset: Offset(nums[0], nums[1]),
          blurRadius: nums[2],
          spreadRadius: nums.length > 3 ? nums[3] : 0,
          color: _rgba(layer.substring(colorAt)),
        );
      }(),
  ];
}

void _sameShadow(List<BoxShadow> actual, List<BoxShadow> expected, String n) {
  expect(actual.length, expected.length, reason: n);
  for (var i = 0; i < expected.length; i++) {
    expect(actual[i], expected[i], reason: '$n camada $i');
  }
}

void main() {
  test('as 90 cores e as 3 do vidro batem com o design system', () {
    final tokens = _list('color');
    expect(tokens.length, 99);
    expect(_colors.length, 99);
    for (final t in tokens) {
      final name = t['name'] as String;
      expect(_colors[name], isNotNull, reason: 'falta $name no Dart');
      expect(_colors[name], _color(t['value'] as String), reason: name);
    }
  });

  test('as 12 identidades seguem a ordem de atribuição', () {
    expect(c.identities, [
      c.idSky,
      c.idIris,
      c.idOrchid,
      c.idTeal,
      c.idSlate,
      c.idSand,
      c.idMauve,
      c.idJade,
      c.idOlive,
      c.idRose,
      c.idClay,
      c.idMoss,
    ]);
  });

  test('espaço', () {
    const dart = {
      'space-0.5': EgeonSpace.s05,
      'space-1': EgeonSpace.s1,
      'space-2': EgeonSpace.s2,
      'space-3': EgeonSpace.s3,
      'space-4': EgeonSpace.s4,
      'space-5': EgeonSpace.s5,
      'space-6': EgeonSpace.s6,
      'space-8': EgeonSpace.s8,
      'space-10': EgeonSpace.s10,
      'space-12': EgeonSpace.s12,
      'space-16': EgeonSpace.s16,
    };
    final tokens = _list('spacing');
    expect(tokens.length, dart.length);
    for (final t in tokens) {
      expect(dart[t['name']], _px(t['value']), reason: '${t['name']}');
    }
  });

  test('raio', () {
    const dart = {
      'radius-xs': EgeonRadius.xs,
      'radius-sm': EgeonRadius.sm,
      'radius-md': EgeonRadius.md,
      'radius-lg': EgeonRadius.lg,
      'radius-xl': EgeonRadius.xl,
      'radius-full': EgeonRadius.full,
    };
    final tokens = _list('radius');
    expect(tokens.length, dart.length);
    for (final t in tokens) {
      expect(dart[t['name']], _px(t['value']), reason: '${t['name']}');
    }
  });

  test('tamanho', () {
    const dart = {
      'size-control-sm': EgeonSize.controlSm,
      'size-control-md': EgeonSize.controlMd,
      'size-control-lg': EgeonSize.controlLg,
      'size-row': EgeonSize.row,
      'size-tab': EgeonSize.tab,
      'size-titlebar': EgeonSize.titlebar,
      'size-icon': EgeonSize.icon,
      'size-icon-sm': EgeonSize.iconSm,
      'size-dot': EgeonSize.dot,
      'size-sidebar': EgeonSize.sidebar,
    };
    final tokens = _list('size');
    expect(tokens.length, dart.length);
    for (final t in tokens) {
      expect(dart[t['name']], _px(t['value']), reason: '${t['name']}');
    }
  });

  test('borda', () {
    const dart = {
      'border-hairline': EgeonBorder.hairline,
      'border-state': EgeonBorder.state,
      'border-focus': EgeonBorder.focus,
    };
    final tokens = _list('border');
    expect(tokens.length, dart.length);
    for (final t in tokens) {
      expect(dart[t['name']], _px(t['value']), reason: '${t['name']}');
    }
  });

  test('opacidade', () {
    const dart = {
      'opacity-disabled': EgeonOpacity.disabled,
      'opacity-hover-reveal': EgeonOpacity.hoverReveal,
      'opacity-muted': EgeonOpacity.muted,
    };
    final tokens = _list('opacity');
    expect(tokens.length, dart.length);
    for (final t in tokens) {
      expect(
        dart[t['name']],
        double.parse('${t['value']}'),
        reason: '${t['name']}',
      );
    }
  });

  test('duração', () {
    const dart = {
      'duration-instant': EgeonMotion.instant,
      'duration-fast': EgeonMotion.fast,
      'duration-base': EgeonMotion.base,
      'duration-attention': EgeonMotion.attention,
      'duration-spin': EgeonMotion.spin,
    };
    final tokens = _list('duration');
    expect(tokens.length, dart.length);
    for (final t in tokens) {
      expect(
        dart[t['name']],
        _ms(t['value'] as String),
        reason: '${t['name']}',
      );
    }
  });

  test('curva', () {
    const dart = {
      'ease-standard': EgeonMotion.easeStandard,
      'ease-exit': EgeonMotion.easeExit,
      'ease-pulse': EgeonMotion.easePulse,
    };
    final tokens = _list('easing');
    expect(tokens.length, dart.length);
    for (final t in tokens) {
      final expected = _cubic(t['value'] as String);
      final actual = dart[t['name']]! as Cubic;
      expect(
        [actual.a, actual.b, actual.c, actual.d],
        [expected.a, expected.b, expected.c, expected.d],
        reason: '${t['name']}',
      );
    }
  });

  test('sombra, com o anel de 1px do float e do modal', () {
    final dart = {
      'shadow-none': const <BoxShadow>[],
      'shadow-raised': EgeonShadow.raised,
      'shadow-float': EgeonShadow.float,
      'shadow-modal': EgeonShadow.modal,
      'shadow-drag': EgeonShadow.drag,
      'shadow-glass': EgeonShadow.glass,
    };
    final tokens = _list('shadow');
    expect(tokens.length, dart.length);
    for (final t in tokens) {
      final name = t['name'] as String;
      _sameShadow(dart[name]!, _shadow(t['value'] as String), name);
    }
    expect(EgeonShadow.float.last.spreadRadius, 1);
    expect(EgeonShadow.float.last.color, const Color(0xFF2A3036));
    expect(EgeonShadow.modal.last.color, const Color(0xFF2A3036));
  });

  test('desfoque do vidro', () {
    final blur = _list('blur').single;
    expect(EgeonGlass.blurSigma, _px(blur['value']));
  });

  group('tipografia', () {
    final t = _tokens()['type'] as Map<String, dynamic>;
    final families = t['families'] as Map<String, dynamic>;

    (String, List<String>) family(String key) {
      final names = RegExp(r'"([^"]+)"|([-\w]+)')
          .allMatches(families[key] as String)
          .map((m) => m.group(1) ?? m.group(2)!)
          .where((n) => n != 'sans-serif' && n != 'monospace')
          .toList();
      return (names.first, names.skip(1).toList());
    }

    final dart = {
      'display': EgeonType.display,
      'title': EgeonType.title,
      'heading': EgeonType.heading,
      'body': EgeonType.body,
      'label': EgeonType.label,
      'small': EgeonType.small,
      'caption': EgeonType.caption,
      'terminal': EgeonType.terminal,
      'code': EgeonType.code,
      'mono-meta': EgeonType.monoMeta,
    };

    test('os 10 estilos batem com o design system', () {
      final styles = [
        for (final g in t['groups'] as List)
          for (final s in (g as Map<String, dynamic>)['styles'] as List)
            (g['family'] as String, s as Map<String, dynamic>),
      ];
      expect(styles.length, dart.length);
      for (final (key, s) in styles) {
        final name = s['name'] as String;
        final style = dart[name]!;
        final size = _px(s['fontSize']);
        final (primary, fallback) = family(key);
        expect(style.fontFamily, primary, reason: name);
        expect(style.fontFamilyFallback, fallback, reason: name);
        expect(style.fontSize, size, reason: name);
        expect(
          style.height!,
          closeTo(_px(s['lineHeight']) / size, 1e-3),
          reason: name,
        );
        expect(
          style.fontWeight,
          FontWeight(s['fontWeight'] as int),
          reason: name,
        );
        final em = s['letterSpacing'] as String?;
        expect(
          style.letterSpacing ?? 0,
          closeTo(
            em == null ? 0 : double.parse(em.replaceAll('em', '')) * size,
            1e-9,
          ),
          reason: name,
        );
      }
    });

    test('os estilos de código usam algarismos tabulares', () {
      for (final s in [
        EgeonType.terminal,
        EgeonType.code,
        EgeonType.monoMeta,
      ]) {
        expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
    });
  });

  test('o terminal usa as 16 cores ANSI do design system', () {
    final tokens = {
      for (final t in _list('color'))
        t['name'] as String: _color(t['value'] as String),
    };
    const names = [
      'black',
      'red',
      'green',
      'yellow',
      'blue',
      'magenta',
      'cyan',
      'white',
      'bright-black',
      'bright-red',
      'bright-green',
      'bright-yellow',
      'bright-blue',
      'bright-magenta',
      'bright-cyan',
      'bright-white',
    ];
    for (var i = 0; i < 16; i++) {
      expect(
        EgeonTerminalPalette.indexed(i),
        tokens['term-${names[i]}'],
        reason: names[i],
      );
    }
    expect(EgeonTerminalPalette.background, tokens['term-bg']);
    expect(EgeonTerminalPalette.foreground, tokens['term-fg']);
    expect(EgeonTerminalPalette.cursor, tokens['term-cursor']);
    expect(EgeonTerminalPalette.selection, tokens['term-selection']);
    expect(EgeonTerminalPalette.indexed(16), const Color(0xFF000000));
    expect(EgeonTerminalPalette.indexed(231), const Color(0xFFFFFFFF));
    expect(EgeonTerminalPalette.indexed(255), const Color(0xFFEEEEEE));
    expect(EgeonTerminalPalette.rgb(0x112233), const Color(0xFF112233));
  });
}
