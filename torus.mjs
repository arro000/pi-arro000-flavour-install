const width = 38;
export const height = 13;
const tau = 2 * Math.PI;
const points = [];
for (let u = 0; u < tau; u += 0.09) {
  for (let v = 0; v < tau; v += 0.16) {
    const r = 1.8 + 0.7 * Math.cos(v);
    points.push([u / tau, r * Math.cos(u), r * Math.sin(u), 0.7 * Math.sin(v),
      Math.cos(v) * Math.sin(u), Math.sin(v)]);
  }
}

export function torus(frame, fill) {
  const cells = Array(width * height).fill(' ');
  const depth = new Float64Array(cells.length).fill(-Infinity);
  const ca = Math.cos(frame * 0.10), sa = Math.sin(frame * 0.10);
  const cb = Math.cos(frame * 0.06), sb = Math.sin(frame * 0.06);
  for (const [fraction, x, y, z, ny, nz] of points) {
    const yy = y * ca - z * sa, zz = y * sa + z * ca;
    const col = Math.floor(19 + (x * cb - yy * sb) * 7);
    const row = Math.floor(6 + (x * sb + yy * cb) * 2.4);
    if (col < 0 || col >= width || row < 0 || row >= height) continue;
    const index = row * width + col;
    if (zz <= depth[index]) continue;
    depth[index] = zz;
    const light = Math.max(0, Math.min(5, Math.floor((ny * sa + nz * ca + 1) * 2.5)));
    cells[index] = fraction < fill ? 'oO0%@#'[light] : '.';
  }
  return Array.from({ length: height }, (_, row) => cells.slice(row * width, (row + 1) * width).join(''));
}
