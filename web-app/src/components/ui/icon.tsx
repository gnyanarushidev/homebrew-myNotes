import type { SVGProps } from "react";

const paths = {
  book: "M4 3h13a3 3 0 0 1 3 3v15H7a3 3 0 0 1-3-3V3Zm0 14h16M8 3v14M11 7h5",
  arrow: "M5 12h14m-5-5 5 5-5 5",
  back: "M19 12H5m5-5-5 5 5 5",
  search: "m21 21-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0Z",
  plus: "M12 5v14M5 12h14",
  close: "m6 6 12 12M6 18 18 6",
  users: "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2m20 0v-2a4 4 0 0 0-3-3.87M13 3.13a4 4 0 0 1 0 7.75M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z",
  mail: "M3 5h18v14H3V5Zm0 1 9 7 9-7",
  cloud: "M6 18a5 5 0 1 1 1-9.9A7 7 0 0 1 20 11a3.5 3.5 0 0 1-1 7H6Z",
  pen: "m15 4 5 5M4 20l4-1L21 6a2 2 0 0 0-3-3L5 16l-1 4Z",
  lock: "M5 10h14v11H5V10Zm3 0V6a4 4 0 0 1 8 0v4m-4 5v2",
  grid: "M3 3h7v7H3V3Zm11 0h7v7h-7V3ZM3 14h7v7H3v-7Zm11 0h7v7h-7v-7Z",
  list: "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01",
  undo: "M3 10h11a6 6 0 0 1 0 12M3 10l5-5m-5 5 5 5",
  eraser: "m16 3 5 5a2 2 0 0 1 0 3L11 21H6l-4-4a2 2 0 0 1 0-3L13 3a2 2 0 0 1 3 0ZM8 8l8 8m-5 5h11",
  monitor: "M2 3h20v14H2V3Zm6 18h8m-4-4v4",
  check: "m5 12 4 4L19 6",
  menu: "M4 6h16M4 12h16M4 18h16",
  trash: "M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7",
  pencil: "m4 20 3-8L17 2l5 5-10 10-8 3Zm3-8 5 5M4 20l4-1",
  highlighter: "m8 15 8-11 5 4-9 10-4-3Zm0 0-3 4 4 2 3-3M3 23h13",
  lasso: "M9 18c-5 0-7-3-7-7s4-8 10-8 10 3 10 7-4 7-10 7c-3 0-5 1-5 3s3 3 5 1",
  rectangle: "M3 5h18v14H3Z",
  circle: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
  line: "M4 20 20 4",
  hand: "M8 13V5a2 2 0 0 1 4 0v7-9a2 2 0 0 1 4 0v9-7a2 2 0 0 1 4 0v8c0 6-3 9-7 9-3 0-5-2-7-5l-3-5c-1-2 2-4 4-1l1 2Z",
  text: "M4 4h16M12 4v16M8 20h8",
  redo: "M21 10H10a6 6 0 0 0 0 12m11-12-5-5m5 5-5 5",
  export: "M12 16V2m-4 4 4-4 4 4M4 12v9h16v-9",
  sidebar: "M3 4h18v16H3ZM9 4v16",
  chevronLeft: "m14 6-6 6 6 6",
  chevronRight: "m10 6 6 6-6 6",
  chevronDown: "m6 9 6 6 6-6",
  chevrons: "m8 8 4-4 4 4m-8 8 4 4 4-4",
  settings: "M4 7h10m4 0h2M4 17h2m4 0h10M18 7a2 2 0 1 1-4 0 2 2 0 0 1 4 0ZM10 17a2 2 0 1 1-4 0 2 2 0 0 1 4 0Z",
  logout: "M9 4H4v16h5m5-4 4-4-4-4m-6 4h12",
  download: "M12 3v12m-4-4 4 4 4-4M4 17v4h16v-4",
} as const;

export type IconName = keyof typeof paths;

export function Icon({ name, ...props }: SVGProps<SVGSVGElement> & { name: IconName }) {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" {...props}>
      <path d={paths[name]} />
    </svg>
  );
}
