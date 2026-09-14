"use client";

import Link from "next/link";
import { useState } from "react";
import { ActionLink, Button, EmptyState } from "@/components/ui/ui";
import { Icon } from "@/components/ui/icon";
import { usePreview } from "@/features/preview/preview-provider";
import { paperTemplates, type PaperTemplate } from "@/features/preview/preview-data";
import styles from "./editor-preview.module.css";

export function EditorPreview({ notebookId }: { notebookId: string }) {
  const { notebooks, updateNotebook } = usePreview();
  const notebook = notebooks.find(item => item.id === notebookId);
  const [currentPage, setCurrentPage] = useState(0);
  const [zoom, setZoom] = useState(85);

  if (!notebook) return <EmptyState title="This preview notebook isn’t here."><p>Preview notebooks exist only in the current workspace session. Open a sample notebook or create a new one.</p><ActionLink href="/notebooks">Back to notebooks</ActionLink></EmptyState>;

  function addPage() {
    if (!notebook) return;
    updateNotebook(notebook.id, { pageCount: notebook.pageCount + 1 });
    setCurrentPage(notebook.pageCount);
  }

  return (
    <div className={styles.editor}>
      <div className={styles.heading}>
        <Link href="/notebooks" className={styles.back} aria-label="Back to notebooks"><Icon name="back" /></Link>
        <div className={styles.title}><h1 className="sr-only">Notebook editor preview</h1><label htmlFor="notebook-title" className="sr-only">Notebook title</label><input id="notebook-title" value={notebook.title} maxLength={80} onChange={event => updateNotebook(notebookId, { title: event.target.value })} onBlur={() => updateNotebook(notebookId, { title: notebook.title.trim() || "Untitled notebook" })} /><span>Preview session · Cloud saving coming next</span></div>
        <Button variant="secondary" disabled title="PDF export will be connected with the drawing editor">Export PDF</Button>
      </div>

      <div className={styles.toolbar}>
        <div className={styles.drawingTools} role="group" aria-label="Drawing tools preview">
          <Button variant="ghost" disabled aria-label="Pen — coming soon" title="Drawing tools are coming in the next editor milestone"><Icon name="pen" /></Button>
          <Button variant="ghost" disabled aria-label="Eraser — coming soon"><Icon name="eraser" /></Button>
          <Button variant="ghost" disabled aria-label="Undo — coming soon"><Icon name="undo" /></Button>
          <span className={styles.toolbarDivider} />
          <label>Paper<select aria-label="Paper template" value={notebook.template} onChange={event => updateNotebook(notebookId, { template: event.target.value as PaperTemplate })}>{paperTemplates.map(item => <option key={item.value} value={item.value}>{item.label}</option>)}</select></label>
        </div>
        <div className={styles.pageAndZoom}>
          <label>Page<select aria-label="Current page" value={currentPage} onChange={event => setCurrentPage(Number(event.target.value))}>{Array.from({ length: notebook.pageCount }, (_, index) => <option key={index} value={index}>{index + 1}</option>)}</select></label>
          <div className={styles.zoom}><button type="button" onClick={() => setZoom(value => Math.max(50, value - 10))} disabled={zoom <= 50} aria-label="Zoom out">−</button><output aria-label="Zoom level">{zoom}%</output><button type="button" onClick={() => setZoom(value => Math.min(150, value + 10))} disabled={zoom >= 150} aria-label="Zoom in">+</button></div>
        </div>
      </div>

      <div className={styles.editorBody}>
        <aside className={styles.pages} aria-label="Notebook pages"><div className={styles.pagesHeading}><span>PAGES</span><button type="button" onClick={addPage} aria-label="Add page"><Icon name="plus" width="16" height="16" /></button></div><div className={styles.thumbnails}>{Array.from({ length: notebook.pageCount }, (_, index) => <button type="button" key={index} className={styles.thumbnailButton} aria-label={`Go to page ${index + 1}`} aria-current={currentPage === index ? "page" : undefined} onClick={() => setCurrentPage(index)}><span className={styles.thumbnail} data-template={notebook.template}><span>{notebook.sample && index === 0 ? "Ideas…" : ""}</span></span><span>{String(index + 1).padStart(2, "0")}</span></button>)}</div></aside>
        <div className={styles.canvas}>
          <div className={styles.canvasScroll}>
            <div className={styles.paperStage}>
              <div style={{ width: 612 * zoom / 100, height: 792 * zoom / 100 }}>
                <div className={styles.paper} data-template={notebook.template} style={{ transform: `scale(${zoom / 100})` }} aria-label={`Page ${currentPage + 1}, ${notebook.template} paper`}>
                  <div className={styles.paperMeta}><span>MYNOTES / {notebook.title || "Untitled notebook"}</span><span>{String(currentPage + 1).padStart(2, "0")}</span></div>
                  {notebook.sample && currentPage === 0 ? <div className={styles.sampleContent}><p className={styles.sampleLabel}>A FEW THINGS WORTH EXPLORING</p><h2>Ideas have a way<br />of finding their space.</h2><p>Start small. Stay curious.<br />Make something worth keeping.</p><svg viewBox="0 0 420 90" fill="none" aria-hidden="true"><path d="M12 55C60 3 93 92 145 50s83-52 107-15 44 31 99-1m-25-6 27 6-17 19" stroke="#557650" strokeWidth="2.2" strokeLinecap="round" /></svg><ul><li>Collect the little sparks.</li><li>Connect a few unexpected dots.</li><li>Leave room for the next idea.</li></ul><span className={styles.sampleCaption}>Sample page artwork · drawing capture comes next</span></div> : <div className={styles.blankPage}><Icon name="pen" width="30" height="30" /><p>Your next idea starts here.</p><span>Drawing will be enabled in a later editor step.</span></div>}
                  <span className={styles.paperFooter}>A LITTLE SPACE FOR BIG IDEAS</span>
                </div>
              </div>
            </div>
          </div>
          <footer className={styles.canvasFooter}><span>Letter · 612 × 792 pt</span><span role="status">Page {currentPage + 1} of {notebook.pageCount}</span><button type="button" onClick={addPage}><Icon name="plus" width="14" height="14" />Add page</button></footer>
        </div>
      </div>
    </div>
  );
}
