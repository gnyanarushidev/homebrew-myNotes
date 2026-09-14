"use client";

import { memo, useEffect, useRef, useState, type PointerEvent } from "react";
import { Stage, Layer, Line, Rect, Circle, Text, Image as CanvasImage, Shape } from "react-konva";
import { boundsFor, hitStroke, inkColor, lassoContains, shapePoints, strokePoints, transformStroke } from "@/lib/drawing";
import { dimensions, paperHex, type NotePage, type PaperColor, type Point, type Stroke, type Template, type Tool } from "@/lib/notebook";
import styles from "./notebook-editor.module.css";

export type EditorTool = Tool | "text";
export type Selection = { pageId: string; ids: string[] };
type Props = { page: NotePage; index: number; zoom: number; template: Template; paperColor: PaperColor; tool: EditorTool; color: string; width: number; opacity: number; selection: Selection; select: (selection: Selection) => void; commit: (strokes: Stroke[]) => void; text: (value: string) => void; focus: () => void };
type Gesture = { pointer: number; mode: "ink" | "erase" | "lasso" | "move" | "resize" | "rotate"; first: Point; last: Point; points: Point[]; original: Stroke[]; strokes: Stroke[]; stroke?: Stroke; bounds?: ReturnType<typeof boundsFor>; selected: Set<string> };

const StrokeInk = memo(function StrokeInk({ stroke }: { stroke: Stroke }) {
  const points = strokePoints(stroke);
  if (points.length === 1) return <Circle x={points[0].x} y={points[0].y} radius={stroke.width / 2} fill={inkColor(stroke)} opacity={stroke.opacity} listening={false} />;
  return <Line points={points.flatMap(p => [p.x, p.y])} stroke={inkColor(stroke)} strokeWidth={stroke.width} opacity={stroke.opacity} lineCap="round" lineJoin="round" listening={false} perfectDrawEnabled={false} />;
});

export default function PageCanvas({ page, index, zoom, template, paperColor, tool, color, width, opacity, selection, select, commit, text, focus }: Props) {
  const size = dimensions(page.size), scale = zoom / 100;
  const wrapper = useRef<HTMLDivElement>(null);
  const gesture = useRef<Gesture | null>(null);
  const [preview, setPreview] = useState<{ strokes: Stroke[]; lasso?: Point[] } | null>(null);
  const [visible, setVisible] = useState(index < 2);
  const [image, setImage] = useState<HTMLImageElement | null>(null);
  useEffect(() => {
    if (!wrapper.current) return;
    const observer = new IntersectionObserver(entries => setVisible(entries[0].isIntersecting), { rootMargin: "500px" });
    observer.observe(wrapper.current);
    return () => observer.disconnect();
  }, []);
  useEffect(() => {
    if (!page.image) return;
    let cancelled = false;
    const image = new window.Image();
    image.onload = () => { if (!cancelled) setImage(image); };
    image.src = `data:${page.image.mimeType};base64,${page.image.data}`;
    return () => { cancelled = true; };
  }, [page.image]);
  const strokes = preview?.strokes ?? page.strokes;
  const selected = selection.pageId === page.id ? strokes.filter(stroke => selection.ids.includes(stroke.id)) : [];
  const bounds = selected.length ? boundsFor(selected) : null;

  function point(event: { clientX: number; clientY: number }): Point {
    const box = wrapper.current!.getBoundingClientRect();
    return { x: Math.max(-10000, Math.min(10000, (event.clientX - box.left) / scale)), y: Math.max(-10000, Math.min(10000, (event.clientY - box.top) / scale)) };
  }
  function down(event: PointerEvent<HTMLDivElement>) {
    if (tool === "hand" || tool === "text" || event.button !== 0 || gesture.current) return;
    event.preventDefault(); event.stopPropagation(); event.currentTarget.focus(); focus();
    event.currentTarget.setPointerCapture(event.pointerId);
    const p = point(event), ids = new Set(selected.map(stroke => stroke.id));
    let mode: Gesture["mode"] = tool === "eraser" ? "erase" : tool === "lasso" ? "lasso" : "ink";
    if (tool === "lasso" && bounds) {
      if (Math.hypot(p.x - (bounds.x + bounds.width / 2), p.y - (bounds.y - 24 / scale)) < 10 / scale) mode = "rotate";
      else if (Math.hypot(p.x - (bounds.x + bounds.width), p.y - (bounds.y + bounds.height)) < 12 / scale) mode = "resize";
      else if (p.x >= bounds.x && p.x <= bounds.x + bounds.width && p.y >= bounds.y && p.y <= bounds.y + bounds.height) mode = "move";
    }
    if (mode === "lasso") select({ pageId: page.id, ids: [] });
    if (mode === "ink" || mode === "erase") select({ pageId: page.id, ids: [] });
    const stroke: Stroke | undefined = mode === "ink" ? { id: crypto.randomUUID(), tool: tool as Stroke["tool"], geometry: "polyline", points: [p], color, width, opacity } : undefined;
    gesture.current = { pointer: event.pointerId, mode, first: p, last: p, points: [p], original: page.strokes, strokes: page.strokes, stroke, bounds: bounds ?? undefined, selected: ids };
    move(event);
  }
  function move(event: PointerEvent<HTMLDivElement>) {
    const g = gesture.current;
    if (!g || g.pointer !== event.pointerId) return;
    event.preventDefault();
    const samples = event.nativeEvent.getCoalescedEvents?.() ?? [];
    for (const sample of samples.length ? samples : [event]) {
      const p = point(sample);
      if (g.mode === "ink" && g.stroke) {
        if (["pen", "pencil", "highlighter"].includes(g.stroke.tool)) {
          if (Math.hypot(p.x - g.last.x, p.y - g.last.y) > .3 && g.points.length < 50000) g.points.push(p);
          g.stroke = { ...g.stroke, points: [...g.points] };
        } else g.stroke = { ...g.stroke, points: shapePoints(g.stroke.tool, g.first, p) };
        g.strokes = [...g.original, g.stroke];
      } else if (g.mode === "erase") {
        g.strokes = g.strokes.filter(stroke => !hitStroke(stroke, g.last, p, width / scale));
      } else if (g.mode === "lasso") {
        if (Math.hypot(p.x - g.last.x, p.y - g.last.y) > 1 / scale) g.points.push(p);
      } else if (g.bounds) {
        const box = g.bounds, center = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
        const angle = Math.atan2(p.y - center.y, p.x - center.x) - Math.atan2(g.first.y - center.y, g.first.x - center.x);
        const transform = (point: Point) => g.mode === "move" ? { x: point.x + p.x - g.first.x, y: point.y + p.y - g.first.y }
          : g.mode === "resize" ? { x: box.x + (point.x - box.x) * Math.max(.05, (p.x - box.x) / box.width), y: box.y + (point.y - box.y) * Math.max(.05, (p.y - box.y) / box.height) }
            : { x: center.x + (point.x - center.x) * Math.cos(angle) - (point.y - center.y) * Math.sin(angle), y: center.y + (point.x - center.x) * Math.sin(angle) + (point.y - center.y) * Math.cos(angle) };
        const transformed = g.original.map(stroke => g.selected.has(stroke.id) ? transformStroke(stroke, transform) : stroke);
        if (transformed.every(stroke => stroke.points.every(point => Math.abs(point.x) <= 10000 && Math.abs(point.y) <= 10000))) g.strokes = transformed;
      }
      g.last = p;
    }
    setPreview({ strokes: g.strokes, lasso: g.mode === "lasso" ? [...g.points] : undefined });
  }
  function finish(event: PointerEvent<HTMLDivElement>, cancelled = false) {
    const g = gesture.current;
    if (!g || g.pointer !== event.pointerId) return;
    if (!cancelled) move(event);
    gesture.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
    if (!cancelled) {
      if (g.mode === "lasso") {
        const ids = g.points.length > 2 ? page.strokes.filter(stroke => lassoContains(stroke, g.points)).map(stroke => stroke.id) : page.strokes.filter(stroke => hitStroke(stroke, g.first, g.first, 6 / scale)).slice(-1).map(stroke => stroke.id);
        select({ pageId: page.id, ids });
      } else if (g.strokes !== g.original && g.strokes.length <= 20000) commit(g.strokes);
    }
    setPreview(null);
  }
  const imageScale = image ? Math.min((size.width - 100) / image.width, (size.height - 120) / image.height) : 1;
  return <div ref={wrapper} className={styles.paper} style={{ width: size.width * scale, height: size.height * scale, cursor: tool === "hand" ? "grab" : tool === "text" ? "text" : "crosshair", touchAction: tool === "hand" || tool === "text" ? "auto" : "none" }} role="application" aria-label={`Drawing page ${index + 1}`} tabIndex={0} data-page-id={page.id} data-stroke-count={page.strokes.length} onPointerDown={down} onPointerMove={move} onPointerUp={event => finish(event)} onPointerCancel={event => finish(event, true)} onLostPointerCapture={event => finish(event, true)}>
    {(visible || preview) && <Stage width={size.width * scale} height={size.height * scale} scaleX={scale} scaleY={scale} listening={false}>
      <Layer clipX={0} clipY={0} clipWidth={size.width} clipHeight={size.height} listening={false}>
        <Rect width={size.width} height={size.height} fill={paperHex[paperColor]} />
        <Shape sceneFunc={ctx => {
          ctx.strokeStyle = ctx.fillStyle = paperColor === "dark" ? "rgba(115,166,255,.32)" : "rgba(0,0,255,.16)"; ctx.lineWidth = .7;
          if (template === "ruled" || template === "grid") {
            ctx.beginPath();
            for (let y = template === "ruled" ? 36 : 0; y <= size.height; y += 32) { ctx.moveTo(0, y); ctx.lineTo(size.width, y); }
            if (template === "grid") for (let x = 0; x <= size.width; x += 32) { ctx.moveTo(x, 0); ctx.lineTo(x, size.height); }
            ctx.stroke();
          } else if (template === "dots") for (let x = 16; x <= size.width; x += 24) for (let y = 16; y <= size.height; y += 24) { ctx.beginPath(); ctx.arc(x, y, .75, 0, Math.PI * 2, false); ctx.fill(); }
        }} />
        {image && <CanvasImage image={image} x={(size.width - image.width * imageScale) / 2} y={60} width={image.width * imageScale} height={image.height * imageScale} />}
        {tool !== "text" && <Text x={50} y={35} width={size.width - 100} height={size.height - 70} text={page.text} fontSize={18} lineHeight={32 / 18} fontFamily="Georgia" fill={paperColor === "dark" ? "white" : "#1f1f1f"} />}
        {strokes.map(stroke => <StrokeInk key={stroke.id} stroke={stroke} />)}
      </Layer>
      <Layer listening={false}>
        {preview?.lasso && <Line points={preview.lasso.flatMap(p => [p.x, p.y])} closed stroke="#529bff" strokeWidth={1 / scale} dash={[6 / scale, 4 / scale]} fill="#529bff12" />}
        {bounds && tool === "lasso" && <><Rect {...bounds} stroke="#529bff" strokeWidth={1 / scale} dash={[5 / scale, 4 / scale]} /><Line points={[bounds.x + bounds.width / 2, bounds.y, bounds.x + bounds.width / 2, bounds.y - 24 / scale]} stroke="#529bff" strokeWidth={1 / scale} /><Circle x={bounds.x + bounds.width / 2} y={bounds.y - 24 / scale} radius={5 / scale} fill="#529bff" /><Rect x={bounds.x + bounds.width - 5 / scale} y={bounds.y + bounds.height - 5 / scale} width={10 / scale} height={10 / scale} stroke="#529bff" strokeWidth={1 / scale} fill="white" /></>}
      </Layer>
    </Stage>}
    {tool === "text" && <textarea className={styles.pageText} aria-label={`Page ${index + 1} text`} style={{ width: size.width - 100, height: size.height - 70, transform: `scale(${scale})`, left: 50 * scale, top: 35 * scale, color: paperColor === "dark" ? "white" : "#1f1f1f" }} value={page.text} maxLength={100000} onFocus={focus} onChange={event => text(event.target.value)} />}
  </div>;
}
