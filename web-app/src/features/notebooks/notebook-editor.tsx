"use client";

import dynamic from "next/dynamic";
import { useEffect, useRef, useState, type PointerEvent } from "react";
import { ActionLink, EmptyState } from "@/components/ui/ui";
import { Icon } from "@/components/ui/icon";
import { Dialog } from "@/components/ui/dialog";
import { DisclosureMenu } from "@/components/ui/disclosure-menu";
import { dimensions, effectiveStyle, newPage, paperColors, pageSizes, templates, type NotebookDocument, type NotePage, type PaperColor, type PageSize, type Template } from "@/lib/notebook";
import { FloatingTools } from "./floating-tools";
import { WorkspaceSidebarToggle } from "./workspace-shell";
import type { EditorTool, Selection } from "./page-canvas";
import { useNotebook } from "./use-notebook";
import { exportDocument, exportPDF } from "./transfer";
import styles from "./notebook-editor.module.css";

const PageCanvas = dynamic(() => import("./page-canvas"), { ssr: false });

export function NotebookEditor({ userId, notebookId }: { userId: string; notebookId: string }) {
  const notebook = useNotebook(userId, notebookId);
  if (!notebook.document) return <EmptyState title={notebook.error ? "Unable to open this notebook" : "Loading notebook…"}>{notebook.error && <p role="alert">{notebook.error}</p>}<ActionLink href="/notebooks">Back to notebooks</ActionLink></EmptyState>;
  return <NotebookSurface {...notebook} document={notebook.document} />;
}

function NotebookSurface({ document, update, status, error, conflict, copying, save, keepBoth, editing, remoteGeneration }: Omit<ReturnType<typeof useNotebook>, "document"> & { document: NotebookDocument }) {
  const [currentPage, setCurrentPage] = useState(0);
  const [zoom, setZoom] = useState(85);
  const [tool, setTool] = useState<EditorTool>("pen");
  const [color, setColor] = useState("#000000");
  const [width, setWidth] = useState(3);
  const [opacity, setOpacity] = useState(1);
  const [selection, select] = useState<Selection>({ pageId: "", ids: [] });
  const [savedHistory, setHistory] = useState<{ past: NotebookDocument[]; future: NotebookDocument[]; generation: number }>({ past: [], future: [], generation: remoteGeneration });
  const history = savedHistory.generation === remoteGeneration ? savedHistory : { past: [], future: [], generation: remoteGeneration };
  const [settings, setSettings] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState("");
  const [title, setTitle] = useState<string | null>(null);
  const viewport = useRef<HTMLDivElement>(null);
  const pan = useRef<{ pointer: number; x: number; y: number; left: number; top: number } | null>(null);
  const appendedAfter = useRef("");
  const initialFit = useRef(false);
  const inkSettings = useRef<Record<string, { color: string; width: number; opacity: number }>>({ pen: { color: "#000000", width: 3, opacity: 1 }, pencil: { color: "#61616b", width: 1.5, opacity: .9 }, highlighter: { color: "#facc15", width: 14, opacity: .35 }, eraser: { color: "#000000", width: 12, opacity: 1 } });
  const page = document.pages[Math.min(currentPage, document.pages.length - 1)];
  const paper = effectiveStyle(document, page);
  const size = dimensions(page.size);

  function commit(next: NotebookDocument) {
    setHistory({ past: [...history.past.slice(-39), document], future: [], generation: remoteGeneration });
    update(next);
  }
  function changePage(id: string, change: Partial<NotePage>) { commit({ ...document, pages: document.pages.map(item => item.id === id ? { ...item, ...change } : item) }); }
  function undo() { const previous = history.past.at(-1); if (previous) { setHistory({ past: history.past.slice(0, -1), future: [document, ...history.future], generation: remoteGeneration }); update(previous); setCurrentPage(value => Math.min(value, previous.pages.length - 1)); select({ pageId: "", ids: [] }); } }
  function redo() { const next = history.future[0]; if (next) { setHistory({ past: [...history.past, document], future: history.future.slice(1), generation: remoteGeneration }); update(next); select({ pageId: "", ids: [] }); } }
  function removeSelection() { if (!selection.ids.length) return; const selectedPage = document.pages.find(item => item.id === selection.pageId); if (selectedPage) changePage(selectedPage.id, { strokes: selectedPage.strokes.filter(stroke => !selection.ids.includes(stroke.id)) }); select({ pageId: "", ids: [] }); }
  function choose(next: EditorTool) {
    const group = (value: EditorTool) => ["pencil", "highlighter", "eraser"].includes(value) ? value : "pen";
    if (!["hand", "lasso", "text"].includes(tool)) inkSettings.current[group(tool)] = { color, width, opacity };
    const settings = inkSettings.current[group(next)];
    setTool(next); setColor(settings.color); setWidth(settings.width); setOpacity(settings.opacity);
    if (next !== "lasso") select({ pageId: "", ids: [] });
  }
  function goTo(index: number) {
    setCurrentPage(index);
    requestAnimationFrame(() => viewport.current?.querySelectorAll<HTMLElement>("[data-page-frame]")[index]?.scrollIntoView({ block: "start", inline: "center" }));
  }
  function addPage() { if (document.pages.length < 300) { commit({ ...document, pages: [...document.pages, newPage(page.size)] }); goTo(document.pages.length); } }
  function fit() {
    const node = viewport.current;
    if (node) setZoom(Math.max(20, Math.min(150, Math.floor(Math.min((node.clientWidth - 60) / size.width, (node.clientHeight - 145) / size.height) * 100))));
    goTo(currentPage);
  }
  useEffect(() => {
    const node = viewport.current;
    if (!node || initialFit.current) return;
    const observer = new ResizeObserver(() => {
      if (node.clientWidth > 0 && node.clientHeight > 0 && !initialFit.current) {
        initialFit.current = true;
        setZoom(Math.max(20, Math.min(150, Math.floor(Math.min((node.clientWidth - 60) / size.width, (node.clientHeight - 145) / size.height) * 100))));
        observer.disconnect();
      }
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, [size.width, size.height]);
  function changeZoom(next: number, pointer?: { x: number; y: number }) {
    const node = viewport.current;
    if (!node) return;
    const viewportBox = node.getBoundingClientRect();
    const anchor = pointer ?? { x: viewportBox.left + node.clientWidth / 2, y: viewportBox.top + node.clientHeight / 2 };
    const frames = [...node.querySelectorAll<HTMLElement>("[data-page-frame]")];
    const frame = frames.find(frame => { const box = frame.getBoundingClientRect(); return box.top <= anchor.y && box.bottom >= anchor.y; }) ?? frames[currentPage];
    const box = frame?.getBoundingClientRect();
    const nextZoom = Math.max(20, Math.min(250, next));
    setZoom(nextZoom);
    if (frame && box) {
      const logical = { x: (anchor.x - box.left) / (zoom / 100), y: (anchor.y - box.top) / (zoom / 100) };
      requestAnimationFrame(() => { const nextBox = frame.getBoundingClientRect(); node.scrollBy(nextBox.left + logical.x * nextZoom / 100 - anchor.x, nextBox.top + logical.y * nextZoom / 100 - anchor.y); });
    }
  }
  useEffect(() => {
    const node = viewport.current;
    if (!node) return;
    const wheel = (event: WheelEvent) => { if (event.ctrlKey || event.metaKey) { event.preventDefault(); changeZoom(zoom * Math.exp(-event.deltaY * .008), { x: event.clientX, y: event.clientY }); } };
    node.addEventListener("wheel", wheel, { passive: false });
    return () => node.removeEventListener("wheel", wheel);
    // Zoom's coordinate conversion must use the current viewport scale.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [zoom, currentPage]);
  function beginPan(event: PointerEvent<HTMLDivElement>) {
    if (tool !== "hand" || event.button !== 0 || (event.target as HTMLElement).closest("button,input,textarea,select")) return;
    const node = viewport.current!; event.preventDefault();
    pan.current = { pointer: event.pointerId, x: event.clientX, y: event.clientY, left: node.scrollLeft, top: node.scrollTop };
    node.setPointerCapture(event.pointerId);
  }
  async function pdf(currentOnly = false) { setExporting(true); setExportError(""); try { await exportPDF(document, currentOnly ? currentPage : undefined); } catch (error) { setExportError((error as Error).message); } finally { setExporting(false); } }

  return <div className={styles.editor} inert={copying} aria-busy={copying} onKeyDown={event => {
    if ((event.target as HTMLElement).closest("input,textarea,select")) return;
    if ([" ", "Enter"].includes(event.key) && (event.target as HTMLElement).closest("button,summary,a")) return;
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "z") { event.preventDefault(); if (event.shiftKey) redo(); else undo(); }
    else if ((event.metaKey || event.ctrlKey) && event.key === "s") { event.preventDefault(); void save(); }
    else if (event.key === "Delete" || event.key === "Backspace") { event.preventDefault(); removeSelection(); }
    else if (event.key === "Escape") select({ pageId: "", ids: [] });
    else if (!event.metaKey && !event.ctrlKey && !event.altKey) { const next = ({ p: "pen", "2": "pencil", h: "highlighter", e: "eraser", v: "lasso", r: "rectangle", c: "circle", l: "line", a: "arrow", " ": "hand", t: "text" } as Record<string, EditorTool>)[event.key.toLowerCase()]; if (next) { event.preventDefault(); choose(next); } }
  }}>
    <h1 className="sr-only">Notebook editor</h1>
    <Dialog open={settings} title="Paper & page" onClose={() => setSettings(false)}>
      <div className={styles.paperSettings}>
        <p>Customize page {currentPage + 1} or use the notebook’s default paper.</p>
        <label>Paper style<select aria-label="Paper template" value={paper.template} onChange={event => page.inheritsStyle ? commit({ ...document, template: event.target.value as Template }) : changePage(page.id, { template: event.target.value as Template })}>{templates.map(value => <option key={value}>{value}</option>)}</select></label>
        <label>Paper color<select aria-label="Paper color" value={paper.color} onChange={event => page.inheritsStyle ? commit({ ...document, color: event.target.value as PaperColor }) : changePage(page.id, { color: event.target.value as PaperColor })}>{paperColors.map(value => <option key={value}>{value}</option>)}</select></label>
        <label>Page size<select aria-label="Page size" value={page.size} onChange={event => changePage(page.id, { size: event.target.value as PageSize })}>{pageSizes.map(value => <option key={value} value={value}>{value === "letterPortrait" ? "US Letter" : "A4"}</option>)}</select></label>
        <label className={styles.inheritStyle}><input type="checkbox" checked={page.inheritsStyle} onChange={event => changePage(page.id, { inheritsStyle: event.target.checked, ...paper })} />Use notebook style</label>
      </div>
    </Dialog>
    <div className={styles.canvasArea} onWheelCapture={event => {
      const node = viewport.current!, last = document.pages.at(-1)!;
      if (node.contains(event.target as Node) && !event.ctrlKey && !event.metaKey && event.deltaY > 0 && node.scrollTop + node.clientHeight >= node.scrollHeight - 2 && last.strokes.length && appendedAfter.current !== last.id && document.pages.length < 300) { appendedAfter.current = last.id; addPage(); }
    }}>
      <FloatingTools tool={tool} choose={choose} color={color} setColor={setColor} width={width} setWidth={setWidth} opacity={opacity} setOpacity={setOpacity} canDelete={selection.ids.length > 0} remove={removeSelection} undo={undo} redo={redo} canUndo={history.past.length > 0} canRedo={history.future.length > 0} />
      {(error || exportError) && <div className={styles.notice} role="alert">{error || exportError} {conflict && <button type="button" onClick={() => void keepBoth()}>Save conflict copy</button>}</div>}
      <div ref={viewport} className={styles.viewport} aria-label="Notebook canvas" style={{ touchAction: tool === "hand" ? "none" : "auto" }} onPointerDown={beginPan} onPointerMove={event => { if (pan.current?.pointer === event.pointerId) { viewport.current!.scrollLeft = pan.current.left - event.clientX + pan.current.x; viewport.current!.scrollTop = pan.current.top - event.clientY + pan.current.y; } }} onPointerUp={() => { pan.current = null; }} onPointerCancel={() => { pan.current = null; }} onScroll={() => {
        const node = viewport.current!;
        const frames = [...node.querySelectorAll<HTMLElement>("[data-page-frame]")];
        const center = node.getBoundingClientRect().top + node.clientHeight / 2;
        const index = frames.findIndex(frame => frame.getBoundingClientRect().bottom > center);
        if (index >= 0) setCurrentPage(index);
      }}>
        <div className={styles.pages}>{document.pages.map((item, index) => { const style = effectiveStyle(document, item); return <section key={item.id} className={styles.pageFrame} data-page-frame aria-label={`Page ${index + 1}`}><PageCanvas page={item} index={index} zoom={zoom} template={style.template} paperColor={style.color} tool={tool} color={color} width={width} opacity={opacity} selection={selection} select={select} commit={strokes => changePage(item.id, { strokes })} text={text => changePage(item.id, { text })} focus={() => setCurrentPage(index)} editing={editing} /><span className={styles.pageNumber}>{index + 1}</span></section>; })}<button type="button" className={styles.addPage} disabled={document.pages.length >= 300} onClick={addPage}><Icon name="plus" width="15" />Add page</button></div>
      </div>
    </div>
    <footer className={styles.statusbar}>
      <WorkspaceSidebarToggle />
      <DisclosureMenu name="Notebook menu" className={styles.notebookMenu} panelClassName={styles.documentPanel} label={<><Icon name="book" width="16" height="16" /><span className={styles.footerTitle}>{document.title}</span><Icon name="chevronDown" width="12" height="12" /></>}>
        <div className={styles.documentIdentity}><label>NOTEBOOK NAME<input aria-label="Notebook title" value={title ?? document.title} maxLength={120} onChange={event => { setTitle(event.target.value); if (event.target.value.trim()) commit({ ...document, title: event.target.value.trim() }); }} onBlur={() => setTitle(null)} /></label><span>{document.pages.length} {document.pages.length === 1 ? "page" : "pages"} · {size.width} × {size.height} pt</span><span>{status}</span></div>
        <div className={styles.documentActions}>
          <button type="button" aria-label="Add page" disabled={document.pages.length >= 300} onClick={addPage}><Icon name="plus" />Add page</button>
          <button type="button" onClick={() => setSettings(true)}><Icon name="settings" />Paper & page</button>
          <button type="button" disabled={document.pages.length === 1} onClick={() => { commit({ ...document, pages: document.pages.filter(item => item.id !== page.id) }); goTo(Math.max(0, currentPage - 1)); select({ pageId: "", ids: [] }); }}><Icon name="trash" />Delete page</button>
          <span className={styles.menuDivider} />
          <button type="button" disabled={exporting} onClick={() => void pdf()}><Icon name="download" />Export PDF</button>
          <button type="button" disabled={exporting} onClick={() => void pdf(true)}><Icon name="download" />Current page as PDF</button>
          <button type="button" onClick={() => exportDocument(document)}><Icon name="export" />Export JSON</button>
          <span className={styles.menuDivider} />
          <button type="button" onClick={fit}><Icon name="monitor" />Fit page</button>
          <button type="button" onClick={() => changeZoom(100)}><Icon name="monitor" />Actual size</button>
          <button type="button" onClick={() => void save()}><Icon name="cloud" />Save now</button>
        </div>
      </DisclosureMenu>
      <span className={styles.saveStatus} role="status" title={status} data-state={error ? "error" : status === "Saved to cloud" || status === "Updated from cloud" ? "saved" : "pending"}><span className={styles.statusDot} /><span className={styles.statusText}>{status}</span></span>
      <div className={styles.footerSpacer} />
      <label className={styles.pagePicker}><span>Page</span><select aria-label="Current page" value={Math.min(currentPage, document.pages.length - 1)} onChange={event => goTo(Number(event.target.value))}>{document.pages.map((item, index) => <option key={item.id} value={index}>{index + 1} / {document.pages.length}</option>)}</select></label>
      <span className="sr-only" role="status">Page {currentPage + 1} of {document.pages.length}</span>
      <div className={styles.zoomControls}><button type="button" className={styles.fitButton} onClick={fit}>Fit page</button><button type="button" aria-label="Zoom out" onClick={() => changeZoom(zoom - 10)}>−</button><output aria-label="Zoom level">{Math.round(zoom)}%</output><button type="button" aria-label="Zoom in" onClick={() => changeZoom(zoom + 10)}>+</button></div>
    </footer>
  </div>;
}
