import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../commons/utils/bench_identity.dart';
import '../../../../commons/widgets/eg/eg_icon.dart';
import '../../../../commons/widgets/eg/icon_button.dart';
import '../../../../commons/widgets/eg/pressable.dart';
import '../../../../commons/widgets/eg/view_switch.dart';
import '../../../../core/adapters/window_chrome.dart';
import '../../../../core/domain/entities/view_mode.dart';
import '../../../../core/domain/entities/workbench.dart';
import '../../../../theme/egeon_colors.dart';
import '../../../../theme/egeon_tokens.dart';
import '../../../../theme/egeon_type.dart';
import '../../../../commons/utils/app_shortcut.dart';

/// A faixa de cima da janela (44, o `size.titlebar`): voltar e avançar
/// (⌘[ ⌘]), Canvas | Chat só ícones (⌥⌘1 ⌥⌘2) e a trilha `projeto / bancada` com o nome
/// da bancada na cor dela; clicar na trilha troca de bancada. Arrasta a janela
/// pela parte vazia e maximiza com duplo clique. No macOS deixa o recuo dos
/// semáforos à esquerda; o runner centra os semáforos nesta mesma altura
/// (`MainFlutterWindow.titlebarHeight`, 44).
class TopBar extends StatelessWidget {
  const TopBar({
    required this.bench,
    required this.chrome,
    required this.canGoBack,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.onSelectView,
    required this.onPickBench,
    this.projectName,
    this.trailing,
    super.key,
  });

  final Workbench? bench;
  final String? projectName;
  final WindowChrome chrome;
  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final ValueChanged<ViewMode> onSelectView;

  /// Clicar na trilha: abre a escolha de bancada.
  final VoidCallback onPickBench;

  /// O canto direito (a pastilha de consumo).
  final Widget? trailing;

  static const height = EgeonSize.titlebar;

  /// O espaço dos três semáforos do macOS até o primeiro botão: 24 de margem (a
  /// linha da borda do trilho, onde o runner põe o primeiro), os três botões
  /// do sistema (14 cada, passo 23: ~59,5) e 18 de respiro, como na v3. O
  /// número é o do macOS de hoje; o runner mantém só o início em 24.
  static const trafficLights = 102.0;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final bench = this.bench;
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final drag = _DragZone(chrome);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(right: EgeonSpace.s4),
        child: Row(
          children: [
            // À esquerda, o lugar dos semáforos (macOS) também arrasta.
            SizedBox(width: mac ? trafficLights : EgeonSpace.s4, child: drag),
            IconButton(
              icon: EgIcons.chevronLeft,
              tooltip: 'Voltar',
              shortcut: appShortcutLabel('['),
              onPressed: canGoBack ? onBack : null,
            ),
            const SizedBox(width: EgeonSpace.s1),
            IconButton(
              icon: EgIcons.chevronRight,
              tooltip: 'Avançar',
              shortcut: appShortcutLabel(']'),
              onPressed: canGoForward ? onForward : null,
            ),
            const SizedBox(width: EgeonSpace.s2),
            ViewSwitch(
              value: switch (bench?.view ?? ViewMode.canvas) {
                ViewMode.canvas => ViewSwitchMode.canvas,
                ViewMode.chat => ViewSwitchMode.chat,
              },
              onChanged: bench == null
                  ? null
                  : (mode) => onSelectView(switch (mode) {
                      ViewSwitchMode.canvas => ViewMode.canvas,
                      ViewSwitchMode.chat => ViewMode.chat,
                    }),
            ),
            if (bench != null) ...[
              SizedBox(
                width: 1 + 2 * 14,
                height: 18,
                child: Center(
                  child: SizedBox(
                    width: 1,
                    height: 18,
                    child: ColoredBox(color: c.line),
                  ),
                ),
              ),
              Flexible(
                child: Breadcrumb(
                  projectName: projectName,
                  benchName: bench.name,
                  colorName: bench.color,
                  onPressed: onPickBench,
                ),
              ),
            ],
            // A parte vazia da faixa arrasta a janela e maximiza no duplo clique.
            Expanded(child: drag),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A parte vazia da faixa: arrasta a janela e, no duplo clique, maximiza. Fica
/// só nos vazios, para o duplo-clique não atrasar o clique dos botões.
class _DragZone extends StatelessWidget {
  const _DragZone(this.chrome);

  final WindowChrome chrome;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onPanStart: (_) => chrome.startDrag(),
    onDoubleTap: chrome.toggleZoom,
    child: const SizedBox.expand(),
  );
}

/// A trilha `projeto / bancada ▾` (o `.ttl` da v3): 32 de altura, respiro de 8,
/// 14/20 w500, vão de 8 entre projeto, `/`, bancada e seta. O projeto em
/// `textSecondary`, a barra em `textDisabled`, o nome em 600 na cor dela.
class Breadcrumb extends StatelessWidget {
  const Breadcrumb({
    required this.benchName,
    required this.onPressed,
    this.projectName,
    this.colorName,
    super.key,
  });

  final String? projectName;
  final String benchName;
  final String? colorName;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final style = EgeonType.label.copyWith(decoration: TextDecoration.none);
    const gap = SizedBox(width: EgeonSpace.s2);
    return Pressable(
      onPressed: onPressed,
      semanticLabel:
          'Projeto ${projectName ?? 'sem projeto'}, bancada $benchName. Trocar bancada',
      builder: (context, s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.pressed
              ? c.steelActive
              : s.hovered
              ? c.steel
              : null,
          borderRadius: BorderRadius.circular(EgeonRadius.md),
          // A borda existe sempre (transparente em repouso): o foco só a
          // recolore e engrossa, sem deslocar o conteúdo.
          border: Border.all(
            color: s.focused ? c.accent : EgeonColors.clear,
            width: EgeonBorder.focus,
          ),
        ),
        child: SizedBox(
          height: EgeonSize.controlSm + 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EgeonSpace.s2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (projectName != null) ...[
                  Flexible(
                    flex: 0,
                    child: Text(
                      projectName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(
                        color: s.hovered ? c.textPrimary : c.textSecondary,
                      ),
                    ),
                  ),
                  gap,
                  Text('/', style: style.copyWith(color: c.textDisabled)),
                  gap,
                ],
                Flexible(
                  child: Text(
                    benchName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style.copyWith(
                      fontWeight: FontWeight.w600,
                      color: BenchIdentity.of(colorName).color(c),
                    ),
                  ),
                ),
                gap,
                EgIcon(EgIcons.chevronDown, size: 12, color: c.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
