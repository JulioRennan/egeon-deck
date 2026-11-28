# desktop_multi_window 0.3.1, com um ajuste

Cópia do pacote [desktop_multi_window](https://pub.dev/packages/desktop_multi_window)
0.3.1 (Apache-2.0, `LICENSE` ao lado), sem o `example/`. Única mudança:
`windows/flutter_window.cc` pede a GPU de baixo consumo ao motor da janela
secundária (`SecondaryGpuPreference`), para que ele não divida com o motor
principal o display e o dispositivo D3D11 do ANGLE. O porquê está no comentário
do código. `EGEON_SECONDARY_GPU=none` volta ao comportamento do pacote; `=high` pede a de
alto desempenho. Se a configuração com LUID falhar (máquina sem D3D11 de
hardware, que cai no WARP), o motor volta aos atributos do principal e os dois
dividem o display de novo, sem aviso.
O runner (`EgeonReportGpu`, em `windows/runner/window_channel.cpp`) anota em
`%LOCALAPPDATA%\<appid>\gpu.log` o adaptador de cada motor e se a janela
secundária ficou com display próprio ou compartilhado.

Também sai a linha `resolution: workspace` do `pubspec.yaml`.

Voltar ao pacote do pub.dev: restaurar `desktop_multi_window: ^0.3.1` no
`pubspec.yaml` e apagar esta pasta, quando o motor passar a aceitar duas janelas
sem dividir o dispositivo.
