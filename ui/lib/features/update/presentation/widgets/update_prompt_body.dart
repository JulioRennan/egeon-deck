import 'package:flutter/widgets.dart';

import '../../../../commons/widgets/form_dialog.dart';
import '../../../../commons/widgets/form_kit.dart';
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
  Widget build(BuildContext context) => FormDialogBody(
    title: widget.prompt.title,
    message: widget.prompt.text,
    actions: [
      FormDialogButton(
        widget.prompt.laterLabel,
        onTap: () => widget.close((accept: false, auto: _auto)),
      ),
      FormDialogButton(
        widget.prompt.acceptLabel,
        primary: true,
        onTap: () => widget.close((accept: true, auto: _auto)),
      ),
    ],
    child: FormCheckbox(
      key: const ValueKey('update-auto'),
      label: widget.prompt.autoLabel,
      on: _auto,
      onChanged: (v) => setState(() => _auto = v),
    ),
  );
}
