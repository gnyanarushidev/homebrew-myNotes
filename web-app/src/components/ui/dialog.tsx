"use client";

import { useEffect, useId, useRef, type ReactNode } from "react";
import { Button } from "./ui";
import { Icon } from "./icon";
import styles from "./dialog.module.css";

export function Dialog({ open, title, onClose, children }: { open: boolean; title: string; onClose: () => void; children: ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();

  useEffect(() => {
    const dialog = ref.current;
    if (open && !dialog?.open) dialog?.showModal();
    if (!open && dialog?.open) dialog.close();
  }, [open]);

  return (
    <dialog ref={ref} className={styles.dialog} aria-labelledby={titleId} onCancel={onClose} onClose={onClose} onClick={event => { if (event.target === event.currentTarget) onClose(); }}>
      <header><h2 id={titleId}>{title}</h2><Button variant="ghost" aria-label="Close dialog" onClick={onClose}><Icon name="close" /></Button></header>
      <div className={styles.body}>{children}</div>
    </dialog>
  );
}
