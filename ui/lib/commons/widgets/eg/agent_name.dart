import 'package:flutter/widgets.dart';

import '../../../theme/egeon_colors.dart';
import '../../../theme/egeon_tokens.dart';
import '../../../theme/egeon_type.dart';
import 'identity.dart';

enum AgentNameSize { sm, md, lg }

/// A identidade de um agente ou bancada é o nome escrito na cor dele, e nada
/// mais: dot redondo é sempre estado. O endereço (`bancada/id`) vem em mono ao
/// lado, em `textSecondary`.
class AgentName extends StatelessWidget {
  const AgentName(
    this.name, {
    this.identity,
    this.address,
    this.size = AgentNameSize.md,
    super.key,
  });

  final String name;
  final Identity? identity;
  final String? address;
  final AgentNameSize size;

  @override
  Widget build(BuildContext context) {
    final c = context.eg;
    final base = switch (size) {
      AgentNameSize.sm => EgeonType.small,
      AgentNameSize.md => EgeonType.label,
      AgentNameSize.lg => EgeonType.heading,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base.copyWith(
              color: identityColor(c, identity),
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        if (address != null) ...[
          const SizedBox(width: EgeonSpace.s2),
          Flexible(
            child: Text(
              address!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EgeonType.monoMeta.copyWith(
                fontWeight: FontWeight.w400,
                color: c.textMuted,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
