import { torus } from './torus.mjs';

const screen = document.querySelector('#torus');
const button = document.querySelector('#motion');
const preference = matchMedia('(prefers-reduced-motion: reduce)');
let timer, frame = 0;
function draw() {
  screen.textContent = torus(frame, (1 - Math.cos(frame++ / 15)) / 2).join('\n');
}
function animate(enabled) {
  clearInterval(timer);
  timer = enabled ? setInterval(draw, 80) : undefined;
  if (!enabled && frame === 0) screen.textContent = torus(7, 1).join('\n');
  button.textContent = enabled ? 'Pause animation' : 'Play animation';
}
button.hidden = false;
button.addEventListener('click', () => animate(!timer));
preference.addEventListener('change', () => animate(!preference.matches));
if (!preference.matches) draw();
animate(!preference.matches);

const list = document.querySelector('#packages');
try {
  const response = await fetch('./packages.json');
  if (!response.ok) throw new Error('Package list unavailable');
  for (const source of await response.json()) {
    const name = source.slice(4);
    const item = document.createElement('li');
    const link = document.createElement('a');
    link.href = `https://www.npmjs.com/package/${name}`;
    link.textContent = name;
    item.append(link);
    list.append(item);
  }
} catch {
  const item = document.createElement('li');
  item.textContent = 'Extension list unavailable.';
  list.append(item);
}
