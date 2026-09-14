"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { Button, EmptyState } from "@/components/ui/ui";
import { Dialog } from "@/components/ui/dialog";
import { Icon } from "@/components/ui/icon";
import { usePreview } from "@/features/preview/preview-provider";
import { paperTemplates, type CoverColor, type PaperTemplate } from "@/features/preview/preview-data";
import ui from "@/components/ui/ui.module.css";
import styles from "./notebooks.module.css";

const covers: { value: CoverColor; label: string }[] = [
  { value: "sage", label: "Sage" }, { value: "sand", label: "Sand" },
  { value: "blue", label: "Blue" }, { value: "rose", label: "Rose" },
];

export function NotebookLibrary() {
  const { notebooks, createNotebook } = usePreview();
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState("recent");
  const [view, setView] = useState<"grid" | "list">("grid");
  const [creating, setCreating] = useState(false);
  const [title, setTitle] = useState("");
  const [cover, setCover] = useState<CoverColor>("sage");
  const [template, setTemplate] = useState<PaperTemplate>("blank");

  const visible = notebooks.filter(notebook => notebook.title.toLowerCase().includes(query.trim().toLowerCase()))
    .sort((a, b) => sort === "title" ? a.title.localeCompare(b.title) : b.order - a.order);

  function create(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!title.trim()) return;
    const id = createNotebook(title, cover, template);
    setCreating(false);
    setTitle("");
    router.push(`/notebooks/${id}`);
  }

  return (
    <>
      <div className={styles.heading}>
        <div><p className={ui.eyebrow}>A PLACE FOR YOUR IDEAS</p><h1>Your notebooks</h1><p>Pick up a thought, or start with a fresh page.</p></div>
        <Button onClick={() => setCreating(true)}><Icon name="plus" />New notebook</Button>
      </div>

      <div className={styles.libraryToolbar}>
        <label className={styles.search}><Icon name="search" /><span className="sr-only">Search notebooks</span><input value={query} onChange={event => setQuery(event.target.value)} placeholder="Search your notebooks…" type="search" /></label>
        <div className={styles.viewControls}>
          <label><span className="sr-only">Sort notebooks</span><select value={sort} onChange={event => setSort(event.target.value)}><option value="recent">Recently added</option><option value="title">Name A–Z</option></select></label>
          <div className={styles.viewToggle} role="group" aria-label="Notebook view"><button type="button" aria-label="Grid view" aria-pressed={view === "grid"} onClick={() => setView("grid")}><Icon name="grid" width="16" height="16" /></button><button type="button" aria-label="List view" aria-pressed={view === "list"} onClick={() => setView("list")}><Icon name="list" width="18" height="18" /></button></div>
        </div>
      </div>
      <p className={styles.count} role="status">{visible.length} {visible.length === 1 ? "notebook" : "notebooks"}{query && " found"}</p>

      {visible.length === 0 ? <EmptyState title="A thought waiting to be found."><p>No notebooks match your search. Try a different name or start a new notebook.</p><Button variant="secondary" onClick={() => setQuery("")}>Clear search</Button></EmptyState> : (
        <div className={view === "grid" ? styles.notebookGrid : styles.notebookList}>
          {visible.map(notebook => (
            <Link href={`/notebooks/${notebook.id}`} className={styles.notebookCard} key={notebook.id}>
              <div className={`${styles.cover} ${styles[notebook.cover]}`}>
                <div className={styles.coverBinding} />
                <span className={styles.coverBrand}>MYNOTES</span>
                <span className={styles.coverTitle}>{notebook.title || "Untitled notebook"}</span>
                <span className={styles.coverFooter}><Icon name="book" width="17" height="17" />SPACE TO THINK</span>
              </div>
              <div className={styles.notebookInfo}><h2>{notebook.title || "Untitled notebook"}</h2><p>{notebook.description}</p><div><span>{notebook.pageCount} {notebook.pageCount === 1 ? "page" : "pages"} <span aria-hidden="true">·</span> {paperTemplates.find(item => item.value === notebook.template)?.label}</span><span className={styles.sampleTag}>{notebook.sample ? "Sample" : "Preview only"}</span></div></div>
              <span className={styles.openNotebook}><Icon name="arrow" /></span>
            </Link>
          ))}
        </div>
      )}
      <div className={styles.libraryFooter}><Icon name="lock" width="15" height="15" /><span>These are example notebooks. Your private library will be connected after sign-in is implemented.</span></div>

      <Dialog open={creating} title="A fresh notebook" onClose={() => setCreating(false)}>
        <form onSubmit={create} className={styles.createForm}>
          <p>Give your next idea a little space. This notebook will live in the preview session.</p>
          <label className={ui.field} htmlFor="notebook-name">Notebook name<input id="notebook-name" className={ui.input} required maxLength={80} value={title} onChange={event => setTitle(event.target.value)} placeholder="Something worth remembering" /></label>
          <fieldset className={styles.colorField}><legend>Cover color</legend><div>{covers.map(item => <button type="button" key={item.value} className={`${styles.colorChoice} ${styles[item.value]}`} aria-label={item.label} aria-pressed={cover === item.value} onClick={() => setCover(item.value)}>{cover === item.value && <Icon name="check" width="16" height="16" />}</button>)}</div></fieldset>
          <label className={ui.field} htmlFor="paper-template">Paper template<select id="paper-template" className={ui.input} value={template} onChange={event => setTemplate(event.target.value as PaperTemplate)}>{paperTemplates.map(item => <option key={item.value} value={item.value}>{item.label}</option>)}</select></label>
          <div className={styles.dialogActions}><Button variant="secondary" onClick={() => setCreating(false)}>Cancel</Button><Button type="submit" disabled={!title.trim()}>Create preview notebook<Icon name="arrow" /></Button></div>
        </form>
      </Dialog>
    </>
  );
}
