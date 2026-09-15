"use client";

import { useEffect, useRef, type ReactNode } from "react";

/** Native disclosure semantics with outside-click/Escape dismissal. */
export function DisclosureMenu({ label, name, className, panelClassName, children, closeOnButtons = true }: { label: ReactNode; name: string; className: string; panelClassName: string; children: ReactNode; closeOnButtons?: boolean }) {
  const ref = useRef<HTMLDetailsElement>(null);
  useEffect(() => {
    const outside = (event: PointerEvent) => { if (ref.current && !ref.current.contains(event.target as Node)) ref.current.open = false; };
    const escape = (event: KeyboardEvent) => {
      if (event.key === "Escape" && ref.current?.open) {
        ref.current.open = false;
        ref.current.querySelector("summary")?.focus();
        event.preventDefault();
      }
    };
    document.addEventListener("pointerdown", outside);
    document.addEventListener("keydown", escape);
    return () => { document.removeEventListener("pointerdown", outside); document.removeEventListener("keydown", escape); };
  }, []);
  return <details ref={ref} className={className} onBlur={event => {
    if (event.relatedTarget && !event.currentTarget.contains(event.relatedTarget as Node)) event.currentTarget.open = false;
  }}>
    <summary aria-label={name}>{label}</summary>
    <div className={panelClassName} onClick={event => {
      const action = (event.target as Element).closest(closeOnButtons ? "a,button:not(:disabled)" : "a");
      if (action && ref.current) ref.current.open = false;
    }}>{children}</div>
  </details>;
}
