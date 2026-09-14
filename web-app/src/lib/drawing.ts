import type { Point, Stroke } from "./notebook";

export function shapePoints(tool: Stroke["tool"], first: Point, last: Point): Point[] {
  if (tool === "rectangle") return [first, { x: last.x, y: first.y }, last, { x: first.x, y: last.y }, first];
  if (tool === "circle") {
    const radius = Math.max(Math.abs(last.x - first.x), Math.abs(last.y - first.y)) / 2;
    const center = { x: first.x + (last.x < first.x ? -radius : radius), y: first.y + (last.y < first.y ? -radius : radius) };
    return Array.from({ length: 65 }, (_, i) => ({ x: center.x + radius * Math.cos(i * Math.PI / 32), y: center.y + radius * Math.sin(i * Math.PI / 32) }));
  }
  if (tool === "arrow") {
    const angle = Math.atan2(last.y - first.y, last.x - first.x);
    const wing = (offset: number) => ({ x: last.x - 14 * Math.cos(angle + offset), y: last.y - 14 * Math.sin(angle + offset) });
    return [first, last, wing(-Math.PI / 6), last, wing(Math.PI / 6)];
  }
  return [first, last];
}

export function strokePoints(stroke: Stroke): Point[] {
  if (stroke.geometry === "polyline" || ["pen", "pencil", "highlighter"].includes(stroke.tool)) return stroke.points;
  const first = stroke.points[0], last = stroke.points[stroke.points.length - 1];
  // Keep the ellipse semantics of the original web v1 documents.
  if (stroke.tool === "circle") return Array.from({ length: 65 }, (_, i) => ({ x: (first.x + last.x) / 2 + Math.abs(last.x - first.x) / 2 * Math.cos(i * Math.PI / 32), y: (first.y + last.y) / 2 + Math.abs(last.y - first.y) / 2 * Math.sin(i * Math.PI / 32) }));
  return shapePoints(stroke.tool, first, last);
}

export function inkColor(stroke: Stroke) {
  const c = stroke.rgba;
  return c ? `rgba(${c.red * 255},${c.green * 255},${c.blue * 255},${c.alpha})` : stroke.color;
}

export function distanceToSegment(p: Point, a: Point, b: Point) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const fraction = dx || dy ? Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy))) : 0;
  return Math.hypot(p.x - a.x - fraction * dx, p.y - a.y - fraction * dy);
}
function intersects(a: Point, b: Point, c: Point, d: Point) {
  const cross = (p: Point, q: Point, r: Point) => (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
  const abC = cross(a, b, c), abD = cross(a, b, d), cdA = cross(c, d, a), cdB = cross(c, d, b);
  if (abC * abD < 0 && cdA * cdB < 0) return true;
  return distanceToSegment(a, c, d) < 0.0001 || distanceToSegment(b, c, d) < 0.0001 || distanceToSegment(c, a, b) < 0.0001 || distanceToSegment(d, a, b) < 0.0001;
}
export function hitStroke(stroke: Stroke, from: Point, to = from, radius = 4) {
  const points = strokePoints(stroke), tolerance = radius + stroke.width / 2;
  return points.some((point, i) => {
    const previous = points[Math.max(0, i - 1)];
    return intersects(previous, point, from, to) || Math.min(distanceToSegment(point, from, to), distanceToSegment(previous, from, to), distanceToSegment(from, previous, point), distanceToSegment(to, previous, point)) <= tolerance;
  });
}
export function pointInPolygon(point: Point, polygon: Point[]) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[i], b = polygon[j];
    if ((a.y > point.y) !== (b.y > point.y) && point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) inside = !inside;
  }
  return inside;
}
export function lassoContains(stroke: Stroke, polygon: Point[]) {
  const points = strokePoints(stroke);
  return points.some((point, index) => pointInPolygon(point, polygon) || polygon.some((edge, i) => intersects(points[Math.max(0, index - 1)], point, edge, polygon[(i + 1) % polygon.length])));
}
export function boundsFor(strokes: Stroke[]) {
  let x = Infinity, y = Infinity, right = -Infinity, bottom = -Infinity;
  for (const stroke of strokes) for (const point of strokePoints(stroke)) {
    x = Math.min(x, point.x - stroke.width / 2); y = Math.min(y, point.y - stroke.width / 2);
    right = Math.max(right, point.x + stroke.width / 2); bottom = Math.max(bottom, point.y + stroke.width / 2);
  }
  return { x, y, width: Math.max(1, right - x), height: Math.max(1, bottom - y) };
}
export function transformStroke(stroke: Stroke, transform: (point: Point) => Point): Stroke {
  return { ...stroke, geometry: "polyline", points: strokePoints(stroke).map(transform) };
}
