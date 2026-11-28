import 'package:egeon_deck/features/node/agent/domain/entities/agent_status.dart';
import 'package:egeon_deck/features/node/agent/domain/entities/context_reading.dart';
import 'package:flutter_test/flutter_test.dart';

/// Porte de ContextGaugeTests (a parte de mostrar; o catálogo é do core).
void main() {
  test('mostra a fatia em uso, arredondada para cima', () {
    const reading = ContextReading(used: 170500, window: 1000000);
    expect(reading.usedPercent, 18);
    expect(reading.text, '18%');
    expect(reading.detail, '170K de 1M em uso');
    expect(const ContextReading(used: 1, window: 1000000).text, '1%');
  });

  test('o matiz vai do verde ao vermelho conforme a janela enche', () {
    double hue(int tokens) => ContextReading(used: tokens, window: 100000).hue;
    expect(hue(0), 120);
    expect(hue(50000), 60);
    expect(hue(100000), 0);
    expect(hue(80000), greaterThan(hue(90000)));
  });

  test('janela cheia para em 100%', () {
    const full = ContextReading(used: 1200000, window: 1000000);
    expect(full.usedPercent, 100);
    expect(full.hue, 0);
  });

  test('números curtos', () {
    expect(ContextReading.short(900), '900');
    expect(ContextReading.short(200000), '200K');
    expect(ContextReading.short(1000000), '1M');
    expect(ContextReading.short(1500000), '1.5M');
  });

  test('o estado do agente vai e volta pelo mapa', () {
    final status = AgentStatus.fromMap({
      'model_title': 'Opus 5.5',
      'models': [
        {
          'label': 'Opus 5.5',
          'value': 'claude-opus-5-5',
          'group': 'featured',
          'selected': true,
        },
      ],
      'offers_model': true,
      'dial': {
        'levels': ['low', 'high'],
        'index': 1,
        'auto': true,
        'pending': false,
        'label': 'high',
      },
      'ultracode': {'on': true, 'available': false},
      'context': {'used': 10, 'window': 100},
    });
    expect(status.offersModel, isTrue);
    expect(status.dial.levels, ['low', 'high']);
    expect(status.dial.label, 'high');
    expect(status.ultracode!.on, isTrue);
    expect(status.context, const ContextReading(used: 10, window: 100));
    expect(AgentStatus.fromMap(status.toMap()).toMap(), status.toMap());
  });

  test(
    'sem leitura do transcript (used e window nulos) o estado ainda chega',
    () {
      // O retrato que o core manda de um agente recém-aberto: a regra de não
      // quebrar aqui é o que faz a faixa do maestro aparecer de primeira.
      final status = AgentStatus.fromMap({
        'model_title': 'padrão',
        'offers_model': true,
        'offers_effort': true,
        'dial': {
          'levels': ['low', 'medium', 'high'],
          'index': 0,
          'auto': true,
          'pending': false,
          'label': '',
        },
        'context': {'used': null, 'window': null},
        'clearable': true,
      });
      expect(status.context, isNull);
      expect(status.modelTitle, 'padrão');
      expect(status.offersModel, isTrue);
    },
  );
}
