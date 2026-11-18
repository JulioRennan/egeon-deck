import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';

/// O rótulo de uma seção de formulário ("BRANCH DA BANCADA", "TEMPLATE"): caixa
/// alta pequena, acima do que descreve.
class FormLabel extends StatelessWidget {
  const FormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: AppColors.white(0.5),
        decoration: TextDecoration.none,
      ),
    ),
  );
}
