/// A ligação entre dois nós como a tela mostra: uma linha com ponta em cada
/// extremidade que tem sentido — `───▶`, `◀───` ou `◀───▶`. O core manda as
/// ligações já colapsadas; a UI só desenha.
///
/// Guarda o par em ordem de nome para ter identidade estável — quem é a origem
/// do TRAÇADO é decidido na hora de desenhar, pela posição dos cards, senão uma
/// linha que podia ser reta viraria volta por baixo só por causa do alfabeto.
class EdgeLink {
  const EdgeLink({
    required this.a,
    required this.b,
    this.aToB = true,
    this.bToA = false,
    this.maxSends = 2,
  });

  final String a;
  final String b;

  /// `a` pode acionar `b`. Na tela, ponta do lado de `b`.
  final bool aToB;

  /// `b` pode acionar `a`. Na tela, ponta do lado de `a`.
  final bool bToA;

  /// Limite da ligação. Nulo = sem limite próprio, vale só o teto da bancada.
  final int? maxSends;

  bool get isBidirectional => aToB && bToA;

  factory EdgeLink.fromMap(Map<String, Object?> map) => EdgeLink(
    a: map['a']! as String,
    b: map['b']! as String,
    aToB: map['a_to_b'] as bool? ?? false,
    bToA: map['b_to_a'] as bool? ?? false,
    maxSends: (map['max_sends'] as num?)?.toInt(),
  );

  Map<String, Object?> toMap() => {
    'a': a,
    'b': b,
    'a_to_b': aToB,
    'b_to_a': bToA,
    'max_sends': maxSends,
  };

  /// Igualdade só pelo par: é o que identifica a linha na tela. Trocar a
  /// direção não faz dela outra ligação — é a mesma linha mudando de estado, e
  /// o realce sob o cursor precisa sobreviver ao clique no botão.
  @override
  bool operator ==(Object other) =>
      other is EdgeLink && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}
