import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/context_menu.dart';
import '../../../../core/domain/entities/workbench_clock.dart';
import '../../../../theme/app_colors.dart';
import 'clock_text.dart';

/// A pastilha do cronômetro da bancada. Clicar abre o menu de zerar.
class ClockChip extends StatefulWidget {
  const ClockChip({required this.clock, required this.onReset, super.key});

  final WorkbenchClock clock;
  final VoidCallback onReset;

  @override
  State<ClockChip> createState() => _ClockChipState();
}

class _ClockChipState extends State<ClockChip> {
  bool _hovering = false;

  void _menu(TapUpDetails details) => showContextMenu(
    context,
    position: details.globalPosition,
    entries: [MenuEntry('Zerar cronômetro', widget.onReset)],
  );

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovering = true),
    onExit: (_) => setState(() => _hovering = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _menu,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.white(_hovering ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClockText(widget.clock),
      ),
    ),
  );
}
