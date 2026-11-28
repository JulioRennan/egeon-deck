import 'package:flutter/widgets.dart';

/// Com "reduzir movimento" ligado, a transição vira troca direta.
Duration egDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
