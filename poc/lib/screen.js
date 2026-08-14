// screen.js — imprime a visibleFrame de um display em coordenadas de tela
// (origem no canto superior esquerdo do display principal, que e o espaco
// usado tanto pela Accessibility API quanto pelo `bounds` do Terminal.app).
//
// Uso: osascript -l JavaScript screen.js <indice>   ->  "x y w h"

ObjC.import('AppKit');

function run(argv) {
  var screens = $.NSScreen.screens;
  var mainHeight = screens.objectAtIndex(0).frame.size.height;
  var i = Math.max(0, Math.min(parseInt(argv[0] || '0', 10) || 0, screens.count - 1));
  var v = screens.objectAtIndex(i).visibleFrame;

  var x = Math.round(v.origin.x);
  var y = Math.round(mainHeight - (v.origin.y + v.size.height));
  var w = Math.round(v.size.width);
  var h = Math.round(v.size.height);

  return [x, y, w, h].join(' ');
}
