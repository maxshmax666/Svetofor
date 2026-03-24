const OUTBOX_DB_NAME = "gps-logger-outbox";
const OUTBOX_STORE_NAME = "requests";
const OUTBOX_SYNC_TAG = "gps-outbox-sync";
const MAX_FLUSH_ITEMS = 100;

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

function openOutboxDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(OUTBOX_DB_NAME, 1);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(OUTBOX_STORE_NAME)) {
        const store = db.createObjectStore(OUTBOX_STORE_NAME, { keyPath: "id" });
        store.createIndex("createdAt", "createdAt", { unique: false });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error("SW: IndexedDB open failed"));
  });
}

async function getOutboxItems(limit = MAX_FLUSH_ITEMS) {
  const db = await openOutboxDb();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(OUTBOX_STORE_NAME, "readonly");
    const index = tx.objectStore(OUTBOX_STORE_NAME).index("createdAt");
    const items = [];
    const req = index.openCursor();

    req.onsuccess = () => {
      const cursor = req.result;
      if (!cursor || items.length >= limit) {
        resolve(items);
        return;
      }
      items.push(cursor.value);
      cursor.continue();
    };
    req.onerror = () => reject(req.error || new Error("SW: IndexedDB cursor failed"));
  });
}

async function deleteOutboxItem(id) {
  const db = await openOutboxDb();
  await new Promise((resolve, reject) => {
    const tx = db.transaction(OUTBOX_STORE_NAME, "readwrite");
    tx.objectStore(OUTBOX_STORE_NAME).delete(id);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error || new Error("SW: IndexedDB delete failed"));
  });
}

async function postOutboxItem(item) {
  const res = await fetch(item.endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(item.payload),
    keepalive: true,
  });

  if (res.ok) {
    return true;
  }

  if (res.status >= 400 && res.status < 500) {
    return "drop";
  }

  return false;
}

async function flushOutbox() {
  const items = await getOutboxItems(MAX_FLUSH_ITEMS);

  for (const item of items) {
    try {
      const result = await postOutboxItem(item);
      if (result === true || result === "drop") {
        await deleteOutboxItem(item.id);
        continue;
      }
      break;
    } catch {
      break;
    }
  }
}

self.addEventListener("sync", (event) => {
  if (event.tag === OUTBOX_SYNC_TAG) {
    event.waitUntil(flushOutbox());
  }
});
