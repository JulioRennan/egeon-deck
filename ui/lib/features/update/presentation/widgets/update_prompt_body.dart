import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/app_dialog.dart';
import '../../../../theme/app_colors.dart';
import '../../domain/entities/app_effect.dart';

/// O que o aviso devolve: atualizar ou depois, e a caixa de "atualizar
/// sozinho" como ficou.
typedef UpdateChoice = ({bool accept, bool auto});

/// O aviso de versão nova: título, texto, a caixa de atualizar sozinho e os
/// dois botões. Tudo vem pronto do core; aqui só se desenha.
class UpdatePromptBody extends StatefulWidget {
  const UpdatePromptBody({
    required this.prompt,
    required this.close,
    super.key,
  });

  final UpdatePrompt prompt;
  final void Function([UpdateChoice? result]) close;

  @override
  State<UpdatePromptBody> createState() => _UpdatePromptBodyState();
}

class _UpdatePromptBodyState extends State<UpdatePromptBody> {
  late bool _auto = widget.prompt.auto;

  @override
  Widget build(BuildContext context) => DialogBody(
    title: widget.prompt.title,
    message: widget.prompt.text,
    actions: [
      DialogButton(
        widget.prompt.laterLabel,
        onTap: () => widget.close((accept: false, auto: _auto)),
      ),
      DialogButton(
        widget.prompt.acceptLabel,
        primary: true,
        onTap: () => widget.close((accept: true, auto: _auto)),
      ),
    ],
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const ValueKey('update-auto'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _auto = !_auto),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              key: const ValueKey('update-auto-box'),
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: _auto ? AppColors.accent : null,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(
                  color: _auto ? AppColors.accent : AppColors.white(0.4),
                ),
              ),
              alignment: Alignment.center,
              child: _auto
                  ? const Text(
                      '✓',
                      style: TextStyle(
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFFFFFF),
                        decoration: TextDecoration.none,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.prompt.autoLabel,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: AppColors.white(0.85),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
