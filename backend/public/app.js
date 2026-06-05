const statusEl = document.getElementById("status");
const authPanel = document.getElementById("authPanel");
const accountPanel = document.getElementById("accountPanel");
const householdPanel = document.getElementById("householdPanel");
const syncPanel = document.getElementById("syncPanel");
const accountInfo = document.getElementById("accountInfo");
const householdInfo = document.getElementById("householdInfo");
const logoutBtn = document.getElementById("logoutBtn");
const installBtn = document.getElementById("installBtn");

const loginForm = document.getElementById("loginForm");
const registerForm = document.getElementById("registerForm");
const profileForm = document.getElementById("profileForm");
const passwordForm = document.getElementById("passwordForm");
const createHouseholdForm = document.getElementById("createHouseholdForm");
const joinHouseholdForm = document.getElementById("joinHouseholdForm");

const loadSnapshotBtn = document.getElementById("loadSnapshotBtn");
const saveSnapshotBtn = document.getElementById("saveSnapshotBtn");
const snapshotText = document.getElementById("snapshotText");

const displayNameInput = document.getElementById("displayName");

const API_BASE = window.location.origin;
const TOKEN_KEY = "aura.web.token";

let token = localStorage.getItem(TOKEN_KEY) ?? "";
let deferredPrompt = null;

function setStatus(message, type = "") {
  statusEl.textContent = message;
  statusEl.className = `status ${type}`.trim();
}

async function api(path, options = {}) {
  const headers = {
    "Content-Type": "application/json",
    ...(options.headers ?? {})
  };

  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }

  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers
  });

  const isJson = response.headers.get("content-type")?.includes("application/json");
  const payload = isJson ? await response.json() : await response.text();

  if (!response.ok) {
    const message = typeof payload === "object" && payload && "error" in payload
      ? String(payload.error)
      : `Request failed (${response.status})`;
    throw new Error(message);
  }

  return payload;
}

function setSignedOut() {
  token = "";
  localStorage.removeItem(TOKEN_KEY);
  authPanel.hidden = false;
  accountPanel.hidden = true;
  householdPanel.hidden = true;
  syncPanel.hidden = true;
  logoutBtn.hidden = true;
  accountInfo.textContent = "Signed out";
  householdInfo.textContent = "No household loaded";
}

async function refreshState() {
  if (!token) {
    setSignedOut();
    return;
  }

  authPanel.hidden = true;
  accountPanel.hidden = false;
  householdPanel.hidden = false;
  syncPanel.hidden = false;
  logoutBtn.hidden = false;

  try {
    const me = await api("/me");
    accountInfo.textContent = `${me.user.displayName} (${me.user.email})`;
    displayNameInput.value = me.user.displayName;

    try {
      const current = await api("/households/current");
      const householdName = current.household?.name ?? "Unknown household";
      const role = current.membership?.role ?? "Member";
      const code = current.household?.code ? ` | code: ${current.household.code}` : "";
      householdInfo.textContent = `${householdName} (${role})${code}`;
    } catch {
      householdInfo.textContent = "No household yet. Create or join below.";
    }

    setStatus("Session ready.", "ok");
  } catch (error) {
    setSignedOut();
    setStatus(error.message, "warn");
  }
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const email = document.getElementById("loginEmail").value.trim();
  const password = document.getElementById("loginPassword").value;

  try {
    const response = await api("/auth/login", {
      method: "POST",
      body: JSON.stringify({ email, password })
    });
    token = response.token;
    localStorage.setItem(TOKEN_KEY, token);
    await refreshState();
    setStatus("Logged in.", "ok");
  } catch (error) {
    setStatus(error.message, "warn");
  }
});

registerForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const displayName = document.getElementById("registerName").value.trim();
  const email = document.getElementById("registerEmail").value.trim();
  const password = document.getElementById("registerPassword").value;

  try {
    const response = await api("/auth/register", {
      method: "POST",
      body: JSON.stringify({ displayName, email, password })
    });
    token = response.token;
    localStorage.setItem(TOKEN_KEY, token);
    await refreshState();
    setStatus("Account created and logged in.", "ok");
  } catch (error) {
    setStatus(error.message, "warn");
  }
});

profileForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    const displayName = displayNameInput.value.trim();
    await api("/me/profile", {
      method: "PATCH",
      body: JSON.stringify({ displayName })
    });
    await refreshState();
    setStatus("Profile updated.", "ok");
  } catch (error) {
    setStatus(error.message, "warn");
  }
});

passwordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const currentPassword = document.getElementById("currentPassword").value;
  const newPassword = document.getElementById("newPassword").value;

  try {
    await api("/me/password", {
      method: "PATCH",
      body: JSON.stringify({ currentPassword, newPassword })
    });
    passwordForm.reset();
    setStatus("Password changed.", "ok");
  } catch (error) {
    setStatus(error.message, "warn");
  }
});

createHouseholdForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const name = document.getElementById("householdName").value.trim();

  try {
    await api("/households", {
      method: "POST",
      body: JSON.stringify({ name })
    });
    createHouseholdForm.reset();
    await refreshState();
    setStatus("Household created.", "ok");
  } catch (error) {
    setStatus(error.message, "warn");
  }
});

joinHouseholdForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const code = document.getElementById("joinCode").value.trim();

  try {
    await api("/households/join", {
      method: "POST",
      body: JSON.stringify({ code })
    });
    joinHouseholdForm.reset();
    await refreshState();
    setStatus("Joined household.", "ok");
  } catch (error) {
    setStatus(error.message, "warn");
  }
});

loadSnapshotBtn.addEventListener("click", async () => {
  try {
    const response = await api("/sync/snapshot");
    const payload = response.snapshot?.payload ?? {};
    snapshotText.value = JSON.stringify(payload, null, 2);
    setStatus("Snapshot loaded.", "ok");
  } catch (error) {
    setStatus(error.message, "warn");
  }
});

saveSnapshotBtn.addEventListener("click", async () => {
  try {
    const payload = snapshotText.value.trim() ? JSON.parse(snapshotText.value) : {};
    await api("/sync/snapshot", {
      method: "PUT",
      body: JSON.stringify({ payload })
    });
    setStatus("Snapshot saved.", "ok");
  } catch (error) {
    const message = error instanceof SyntaxError ? "Snapshot JSON is invalid." : error.message;
    setStatus(message, "warn");
  }
});

logoutBtn.addEventListener("click", () => {
  setSignedOut();
  setStatus("Logged out.");
});

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  deferredPrompt = event;
  installBtn.hidden = false;
});

installBtn.addEventListener("click", async () => {
  if (!deferredPrompt) {
    return;
  }
  deferredPrompt.prompt();
  await deferredPrompt.userChoice;
  deferredPrompt = null;
  installBtn.hidden = true;
});

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch(() => {
      setStatus("Service worker registration failed.", "warn");
    });
  });
}

refreshState();
