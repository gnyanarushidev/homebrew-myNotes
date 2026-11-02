import { dimensions, paperHex, type NotePage, type NotebookDocument, type Stroke } from "@/lib/notebook";
import { inkColor, strokePoints } from "@/lib/drawing";

const fmt = (value: number) => Math.round(value * 100) / 100;

/** Freehand ink is drawn as quadratic curves through segment midpoints, matching the Mac editor. */
function strokePath(stroke: Stroke) {
  const points = strokePoints(stroke);
  const freehand = ["pen", "pencil", "highlighter"].includes(stroke.tool) && stroke.geometry !== "shape";
  if (points.length < 3 || !freehand) return points.map((p, i) => `${i ? "L" : "M"}${fmt(p.x)} ${fmt(p.y)}`).join("");
  let d = `M${fmt(points[0].x)} ${fmt(points[0].y)}`;
  for (let i = 1; i < points.length - 1; i++) d += `Q${fmt(points[i].x)} ${fmt(points[i].y)} ${fmt((points[i].x + points[i + 1].x) / 2)} ${fmt((points[i].y + points[i + 1].y) / 2)}`;
  const last = points[points.length - 1];
  return `${d}L${fmt(last.x)} ${fmt(last.y)}`;
}

function paperLines(template: NotebookDocument["template"], width: number, height: number) {
  let d = "";
  if (template === "ruled" || template === "grid") for (let y = template === "ruled" ? 36 : 0; y <= height; y += 32) d += `M0 ${y}H${width}`;
  if (template === "grid") for (let x = 0; x <= width; x += 32) d += `M${x} 0V${height}`;
  return d;
}

export function SharedPage({ page, document, index }: { page: NotePage; document: NotebookDocument; index: number }) {
  const size = dimensions(page.size);
  const template = page.inheritsStyle ? document.template : page.template;
  const color = page.inheritsStyle ? document.color : page.color;
  const dark = color === "dark";
  const dots: [number, number][] = [];
  if (template === "dots") for (let x = 16; x <= size.width; x += 24) for (let y = 16; y <= size.height; y += 24) dots.push([x, y]);
  const lineColor = dark ? "rgba(115,166,255,.32)" : "rgba(0,0,255,.16)";
  return <svg viewBox={`0 0 ${size.width} ${size.height}`} role="img" aria-label={`Page ${index + 1}`} style={{ width: "100%", height: "auto", display: "block" }}>
    <defs><clipPath id={`clip-${index}`}><rect width={size.width} height={size.height} /></clipPath></defs>
    <g clipPath={`url(#clip-${index})`}>
      <rect width={size.width} height={size.height} fill={paperHex[color]} />
      <path d={paperLines(template, size.width, size.height)} fill="none" stroke={lineColor} strokeWidth={0.7} />
      {dots.map(([x, y]) => <circle key={`${x}-${y}`} cx={x} cy={y} r={0.75} fill={lineColor} />)}
      {page.image && <image href={`data:${page.image.mimeType};base64,${page.image.data}`} x={50} y={60} width={size.width - 100} height={size.height - 120} preserveAspectRatio="xMidYMin meet" />}
      {page.text && <foreignObject x={50} y={35} width={size.width - 100} height={size.height - 70}>
        <div style={{ font: "18px/32px Georgia, serif", color: dark ? "#fff" : "#1f1f1f", whiteSpace: "pre-wrap", overflowWrap: "anywhere" }}>{page.text}</div>
      </foreignObject>}
      {page.strokes.map(stroke => {
        const points = strokePoints(stroke);
        if (points.length === 1) return <circle key={stroke.id} cx={points[0].x} cy={points[0].y} r={stroke.width / 2} fill={inkColor(stroke)} opacity={stroke.opacity} />;
        return <path key={stroke.id} d={strokePath(stroke)} fill="none" stroke={inkColor(stroke)} strokeWidth={stroke.width} strokeOpacity={stroke.opacity} strokeLinecap="round" strokeLinejoin="round" />;
      })}
    </g>
  </svg>;
}
