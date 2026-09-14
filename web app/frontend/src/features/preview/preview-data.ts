export type PaperTemplate = "blank" | "ruled" | "grid" | "dots";
export type CoverColor = "sage" | "sand" | "blue" | "rose";

export type PreviewNotebook = {
  id: string;
  title: string;
  description: string;
  cover: CoverColor;
  template: PaperTemplate;
  pageCount: number;
  order: number;
  sample: boolean;
};

export type PreviewMember = {
  id: string;
  name: string;
  email: string;
  role: "Admin" | "Member";
  status: "Active" | "Invited" | "Revoked";
};

// Public, fictional fixtures. No account information is loaded into the preview.
export const previewNotebooks: PreviewNotebook[] = [
  { id: "everyday-ideas", title: "Everyday ideas", description: "The little things that turn into something.", cover: "sage", template: "ruled", pageCount: 3, order: 3, sample: true },
  { id: "work-in-progress", title: "Work in progress", description: "A place for plans, sketches, and next steps.", cover: "sand", template: "grid", pageCount: 5, order: 2, sample: true },
  { id: "learning-journal", title: "Learning journal", description: "New ideas. Fresh perspectives.", cover: "blue", template: "dots", pageCount: 2, order: 1, sample: true },
];

export const previewMembers: PreviewMember[] = [
  { id: "demo-admin", name: "Demo administrator", email: "admin@example.com", role: "Admin", status: "Active" },
  { id: "demo-member", name: "Alex Morgan", email: "alex@example.com", role: "Member", status: "Active" },
  { id: "demo-invite", name: "Invitation pending", email: "sam@example.com", role: "Member", status: "Invited" },
];

export const paperTemplates: { value: PaperTemplate; label: string }[] = [
  { value: "blank", label: "Blank" },
  { value: "ruled", label: "Ruled" },
  { value: "grid", label: "Grid" },
  { value: "dots", label: "Dotted" },
];
