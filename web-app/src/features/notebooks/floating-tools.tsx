"use client";

import { useRef, useState } from "react";
import { Icon, type IconName } from "@/components/ui/icon";
import type { EditorTool } from "./page-canvas";
import styles from "./notebook-editor.module.css";

const tools: { tool: EditorTool; label: string; icon: IconName; key: string }[] = [
  { tool: "pen", label: "Pen", icon: "pen", key: "P" }, { tool: "pencil", label: "Pencil", icon: "pencil", key: "2" }, { tool: "highlighter", label: "Highlighter", icon: "highlighter", key: "H" }, { tool: "eraser", label: "Eraser", icon: "eraser", key: "E" }, { tool: "lasso", label: "Lasso", icon: "lasso", key: "V" }, { tool: "rectangle", label: "Rectangle", icon: "rectangle", key: "R" }, { tool: "circle", label: "Circle", icon: "circle", key: "C" }, { tool: "line", label: "Line", icon: "line", key: "L" }, { tool: "arrow", label: "Arrow", icon: "arrow", key: "A" }, { tool: "hand", label: "Hand", icon: "hand", key: "Space" }, { tool: "text", label: "Text", icon: "text", key: "T" },
];
export function FloatingTools({ tool, choose, color, setColor, width, setWidth, opacity, setOpacity, canDelete, remove }: { tool: EditorTool; choose: (tool: EditorTool) => void; color: string; setColor: (color: string) => void; width: number; setWidth: (width: number) => void; opacity: number; setOpacity: (opacity: number) => void; canDelete: boolean; remove: () => void }) {
  const palette = useRef<HTMLDivElement>(null);
  const drag = useRef<{ x: number; y: number; left: number; top: number } | null>(null);
  const [position, setPosition] = useState<{ left: number; top: number } | null>(null);
  return <div ref={palette} className={styles.floatingTools} style={position ? { left: position.left, top: position.top, transform: "none" } : undefined} aria-label="Writing toolbar">
    <div className={styles.toolsRow}><button type="button" className={styles.dragHandle} aria-label="Move writing toolbar" title="Drag to move writing toolbar" onPointerDown={event => { const box = palette.current!.getBoundingClientRect(), parent = palette.current!.parentElement!.getBoundingClientRect(); drag.current = { x: event.clientX, y: event.clientY, left: box.left - parent.left, top: box.top - parent.top }; event.currentTarget.setPointerCapture(event.pointerId); }} onPointerMove={event => { if (!drag.current) return; const node = palette.current!, parent = node.parentElement!; setPosition({ left: Math.max(4, Math.min(parent.clientWidth - node.offsetWidth - 4, drag.current.left + event.clientX - drag.current.x)), top: Math.max(4, Math.min(parent.clientHeight - node.offsetHeight - 4, drag.current.top + event.clientY - drag.current.y)) }); }} onPointerUp={() => { drag.current = null; }} onPointerCancel={() => { drag.current = null; }}><Icon name="menu" width="15" /></button>
      {tools.map(item => <button key={item.tool} type="button" aria-label={item.label} aria-pressed={tool === item.tool} title={`${item.label} (${item.key})`} onClick={() => choose(item.tool)}><Icon name={item.icon} width="19" /></button>)}
      <button type="button" aria-label="Delete selection" title="Delete selection" disabled={!canDelete} onClick={remove}><Icon name="trash" width="18" /></button>
    </div>
    <div className={styles.inkRow}>{["#000000", "#ffffff", "#797980", "#ef4444", "#fb923c", "#facc15", "#22c55e", "#3b82f6", "#a855f7"].map(value => <button key={value} type="button" className={styles.swatch} aria-label={`Ink ${value}`} aria-pressed={color === value} style={{ background: value }} onClick={() => setColor(value)} />)}<input type="color" aria-label="Ink color" value={color} onChange={event => setColor(event.target.value)} /><label>Width<input aria-label="Stroke width" type="range" min="1" max={tool === "eraser" ? "40" : "24"} step=".5" value={width} onChange={event => setWidth(Number(event.target.value))} /></label><label>Opacity<input aria-label="Ink opacity" type="range" min=".05" max="1" step=".05" value={opacity} onChange={event => setOpacity(Number(event.target.value))} /></label></div>
  </div>;
}
