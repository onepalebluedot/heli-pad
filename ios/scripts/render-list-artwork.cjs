// Build-time conversion only; the app has no SVG rendering dependency.
// npm install --prefix /tmp/helipad-list-artwork @resvg/resvg-js
// NODE_PATH=/tmp/helipad-list-artwork/node_modules node scripts/render-list-artwork.cjs
const fs = require('node:fs');
const path = require('node:path');
const { Resvg } = require('@resvg/resvg-js');
const root = path.resolve(__dirname, '..');
for (const [source, asset] of [
  ['to-do-detailed-accent', 'ListsTodoArtwork'],
  ['grocery-list', 'ListsGroceryArtwork'],
]) {
  // Resolve the supplied CSS variable to its declared fallback: resvg does
  // not resolve custom properties. The source SVGs remain byte-for-byte intact.
  const svg = fs.readFileSync(path.join(root, 'HeliPad/ArtworkSources', source + '.svg'), 'utf8')
    .replaceAll('var(--td-accent, currentColor)', 'currentColor');
  const png = new Resvg(svg, {
    fitTo: { mode: 'width', value: 1200 },
    font: { loadSystemFonts: true },
  }).render().asPng();
  fs.writeFileSync(path.join(root, 'HeliPad/HeliPad/Assets.xcassets', asset + '.imageset/artwork.png'), png);
}
