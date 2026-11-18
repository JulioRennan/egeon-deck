import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/glass_panel.dart';
import '../../../../commons/widgets/spinner.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/shell_snapshot.dart';

/// "Um instante": cobre o conteúdo enquanto o core faz algo demorado.
class BusyCurtain extends StatelessWidget {
  const BusyCurtain(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.black(0.55),
    child: Center(
      child: GlassPanel(
        radius: 12,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SpinnerBuilder(
                builder: (_, glyph) => Text(
                  glyph,
                  style: const TextStyle(
                    fontFamily: 'Menlo',
                    fontSize: 14,
                    color: Color(0xFFFFFFFF),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFFFFFFF),
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// "Sem acesso à pasta": o macOS negou ou está perguntando.
class AccessCurtain extends StatelessWidget {
  const AccessCurtain({
    required this.lock,
    required this.onOpenSettings,
    required this.onAskAgain,
    super.key,
  });

  final AccessLock lock;
  final VoidCallback onOpenSettings;
  final VoidCallback onAskAgain;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.black(0.7),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: GlassPanel(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sem acesso à pasta',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFFFFFF),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  lock.asking
                      ? 'O macOS está perguntando — responda o aviso dele.'
                      : lock.text,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.white(0.8),
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _Button(
                      'Pedir de novo',
                      enabled: !lock.asking,
                      onTap: onAskAgain,
                    ),
                    const SizedBox(width: 10),
                    _Button(
                      'Abrir Ajustes',
                      enabled: true,
                      onTap: onOpenSettings,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Button extends StatelessWidget {
  const _Button(this.label, {required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 130,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.white(enabled ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.white(enabled ? 0.95 : 0.35),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    ),
  );
}
