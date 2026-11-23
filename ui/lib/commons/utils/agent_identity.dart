import '../widgets/eg/identity.dart';

/// A cor de identidade de um agente, uma só para o canvas e o chat: sai do id
/// (o mesmo do nó e do endereço de dispatch), então o mesmo agente tem a mesma
/// cor em qualquer lugar e em qualquer sessão. Provisório, como o mapa de
/// bancada, até o core guardar a cor do agente.
Identity agentIdentity(String id) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return Identity.values[hash % Identity.values.length];
}
