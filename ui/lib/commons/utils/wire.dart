/// Leitura tolerante do que chega do core: lista ausente é lista vazia.
List<T> mapList<T>(Object? raw, T Function(Map<String, Object?>) read) => [
  for (final item in (raw as List<Object?>? ?? const []))
    read(item! as Map<String, Object?>),
];
