import type { NotebookDocument, NotebookRecord } from "./notebook";

export type Draft = { record: NotebookRecord; document: NotebookDocument; mutationId: string; savedAt: number; conflictCopy?: { id: string; mutationId: string } };
let database: Promise<IDBDatabase> | undefined;
function open() {
  database ??= new Promise((resolve, reject) => {
    const request = indexedDB.open("mynotes-recovery", 1);
    request.onupgradeneeded = () => request.result.createObjectStore("drafts");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => { database = undefined; reject(new Error("Local recovery storage is unavailable.")); };
  });
  return database;
}
export async function readDraft(userId: string, id: string): Promise<Draft | undefined> {
  const db = await open();
  return new Promise((resolve, reject) => {
    const request = db.transaction("drafts").objectStore("drafts").get(`${userId}:${id}`);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(new Error("Unable to read the local recovery draft."));
  });
}
export async function writeDraft(userId: string, id: string, draft?: Draft) {
  const db = await open();
  return new Promise<void>((resolve, reject) => {
    const transaction = db.transaction("drafts", "readwrite");
    const store = transaction.objectStore("drafts");
    if (draft) store.put(draft, `${userId}:${id}`); else store.delete(`${userId}:${id}`);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(new Error("Local recovery storage is full or unavailable. Export a backup."));
    transaction.onabort = () => reject(new Error("The local draft could not be saved. Export a backup."));
  });
}
