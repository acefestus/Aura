const statusEl = document.getElementById("status");
const authScreen = document.getElementById("authScreen");
const appShell = document.getElementById("appShell");
const welcomeText = document.getElementById("welcomeText");

const accountInfo = document.getElementById("accountInfo");
const householdInfo = document.getElementById("householdInfo");
const displayNameInput = document.getElementById("displayName");

const loginForm = document.getElementById("loginForm");
const registerForm = document.getElementById("registerForm");
const profileForm = document.getElementById("profileForm");
const passwordForm = document.getElementById("passwordForm");
const createHouseholdForm = document.getElementById("createHouseholdForm");
const joinHouseholdForm = document.getElementById("joinHouseholdForm");

const loadSnapshotBtn = document.getElementById("loadSnapshotBtn");
const saveSnapshotBtn = document.getElementById("saveSnapshotBtn");
const snapshotText = document.getElementById("snapshotText");
const agendaSearch = document.getElementById("agendaSearch");
const agendaList = document.getElementById("agendaList");

const calendarGrid = document.getElementById("calendarGrid");
const calendarLabel = document.getElementById("calendarLabel");
const prevMonthBtn = document.getElementById("prevMonthBtn");
const nextMonthBtn = document.getElementById("nextMonthBtn");

const kpiUpcoming = document.getElementById("kpiUpcoming");
const kpiToday = document.getElementById("kpiToday");
const kpiOverdue = document.getElementById("kpiOverdue");
const nextEvent = document.getElementById("nextEvent");

const modeSignIn = document.getElementById("modeSignIn");
const modeCreate = document.getElementById("modeCreate");
const onboardingNextBtn = document.getElementById("onboardingNextBtn");
const onboardingVisual = document.getElementById("onboardingVisual");
const onboardingTitle = document.getElementById("onboardingTitle");
const onboardingText = document.getElementById("onboardingText");
const onboardingDots = document.getElementById("onboardingDots");

const logoutBtn = document.getElementById("logoutBtn");
const installBtn = document.getElementById("installBtn");

const tabButtons = Array.from(document.querySelectorAll(".tab"));
const pages = Array.from(document.querySelectorAll("[data-page]"));

const API_BASE = window.location.origin;
const TOKEN_KEY = "aura.web.token";

const onboardingPages = [
  {
    title: "Built For Your Family",
    text: "Events, lists, routines, and memories in one premium daily hub.",
    visual: "linear-gradient(155deg, rgba(240,138,93,0.95), rgba(15,108,189,0.95))"
  },
  {
    title: "Private By Design",
    text: "Choose visibility per activity and keep your household coordinated.",
    visual: "linear-gradient(155deg, rgba(17,35,53,0.92), rgba(64,98,130,0.9))"
  },
  {
    title: "Real-Time Household Sync",
    text: "Stay in sync across devices with one account and one shared household.",
    visual: "linear-gradient(155deg, rgba(15,108,189,0.92), rgba(37,160,124,0.9))"
  }
];

let token = localStorage.getItem(TOKEN_KEY) ?? "";
let deferredPrompt = null;
let onboardingIndex = 0;
let onboardingTimer = null;
let currentTab = "home";
let snapshotPayload = {};
let events = [];
let currentMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1);

function setStatus(message, type = "") {
  statusEl.textContent = message;
  statusEl.className = `status ${type}`.trim();
}

function setAuthMode(mode) {
  const showCreate = mode === "create";
  registerForm.hidden = !showCreate;
  loginForm.hidden = showCreate;
  modeCreate.classList.toggle("active", showCreate);
  modeSignIn.classList.toggle("active", !showCreate);
}

function renderOnboarding(index) {
  const page = onboardingPages[index % onboardingPages.length];
  onboardingVisual.style.background = `radial-gradient(circle at 20% 20%, rgba(255,255,255,0.22), transparent 45%), ${page.visual}`;
  onboardingTitle.textContent = page.title;
  onboardingText.textContent = page.text;

  onboardingDots.innerHTML = "";
  onboardingPages.forEach((_, dotIndex) => {
    const dot = document.createElement("span");
    dot.className = `dot ${dotIndex === index ? "active" : ""}`.trim();
    onboardingDots.appendChild(dot);
  });
}

function startOnboardingAuto() {
  if (onboardingTimer) {
    clearInterval(onboardingTimer);
  }
  onboardingTimer = setInterval(() => {
    onboardingIndex = (onboardingIndex + 1) % onboardingPages.length;
    renderOnboarding(onboardingIndex);
  }, 5000);
}

function formatDateLabel(input) {
  if (!input) {
    return "No date";
  }
  const date = new Date(input);
  if (Number.isNaN(date.getTime())) {
    return "No date";
  }
  return date.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit"
  });
}

function normalizeEvent(raw, index) {
  const title = typeof raw.title === "string" && raw.title.trim() ? raw.title.trim() : `Event ${index + 1}`;
  const startDate = raw.startDate ?? raw.date ?? raw.start ?? null;
  const endDate = raw.endDate ?? raw.end ?? startDate;
  const notes = typeof raw.notes === "string" ? raw.notes : "";
  return {
    id: typeof raw.id === "string" ? raw.id : `evt-${index}`,
    title,
    startDate,
    endDate,
    notes
  };
}

function extractEventsFromPayload(payload) {
  const list = Array.isArray(payload?.events) ? payload.events : [];
  return list
    .map((item, index) => normalizeEvent(item, index))
    .sort((left, right) => {
      const leftTime = left.startDate ? new Date(left.startDate).getTime() : Number.POSITIVE_INFINITY;
      const rightTime = right.startDate ? new Date(right.startDate).getTime() : Number.POSITIVE_INFINITY;
      return leftTime - rightTime;
    });
}

function renderHome() {
  const now = Date.now();
  const sevenDays = now + 7 * 24 * 60 * 60 * 1000;

  let upcoming = 0;
  let today = 0;
  let overdue = 0;
  let nearest = null;

  events.forEach((event) => {
    if (!event.startDate) {
      return;
    }
    const when = new Date(event.startDate).getTime();
    if (Number.isNaN(when)) {
      return;
    }

    if (when < now) {
      overdue += 1;
    }
    if (when >= now && when <= sevenDays) {
      upcoming += 1;
    }
    const date = new Date(event.startDate);
    if (date.toDateString() === new Date().toDateString()) {
      today += 1;
    }
    if (when >= now && (!nearest || when < nearest.when)) {
      nearest = { when, event };
    }
  });

  kpiUpcoming.textContent = String(upcoming);
  kpiToday.textContent = String(today);
  kpiOverdue.textContent = String(overdue);

  nextEvent.textContent = nearest
    ? `${nearest.event.title} - ${formatDateLabel(nearest.event.startDate)}`
    : "No upcoming events yet.";
}

function renderAgenda() {
  const query = agendaSearch.value.trim().toLowerCase();
  const filtered = events.filter((event) => {
    if (!query) {
      return true;
    }
    return event.title.toLowerCase().includes(query) || event.notes.toLowerCase().includes(query);
  });

  if (filtered.length === 0) {
    agendaList.innerHTML = '<li class="event-item"><strong>No matching events.</strong><span>Load snapshot or adjust search.</span></li>';
    return;
  }

  agendaList.innerHTML = filtered
    .map((event) => {
      const note = event.notes ? event.notes : "No notes";
      return `<li class="event-item"><strong>${event.title}</strong><span>${formatDateLabel(event.startDate)}</span><span>${note}</span></li>`;
    })
    .join("");
}

function renderCalendar() {
  const year = currentMonth.getFullYear();
  const month = currentMonth.getMonth();
  const firstDay = new Date(year, month, 1);
  const firstWeekday = (firstDay.getDay() + 6) % 7;
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const prevMonthDays = new Date(year, month, 0).getDate();

  calendarLabel.textContent = currentMonth.toLocaleDateString(undefined, { month: "long", year: "numeric" });

  const cells = [];
  for (let i = 0; i < firstWeekday; i += 1) {
    const day = prevMonthDays - firstWeekday + i + 1;
    cells.push({ day, inMonth: false, keyDate: new Date(year, month - 1, day) });
  }

  for (let day = 1; day <= daysInMonth; day += 1) {
    cells.push({ day, inMonth: true, keyDate: new Date(year, month, day) });
  }

  while (cells.length % 7 !== 0) {
    const day = cells.length - (firstWeekday + daysInMonth) + 1;
    cells.push({ day, inMonth: false, keyDate: new Date(year, month + 1, day) });
  }

  const countByDay = new Map();
  events.forEach((event) => {
    if (!event.startDate) {
      return;
    }
    const date = new Date(event.startDate);
    if (Number.isNaN(date.getTime())) {
      return;
    }
    const key = new Date(date.getFullYear(), date.getMonth(), date.getDate()).toISOString();
    countByDay.set(key, (countByDay.get(key) ?? 0) + 1);
  });

  calendarGrid.innerHTML = cells
    .map((cell) => {
      const key = new Date(cell.keyDate.getFullYear(), cell.keyDate.getMonth(), cell.keyDate.getDate()).toISOString();
      const count = countByDay.get(key) ?? 0;
      const countLabel = count > 0 ? `${count} event${count > 1 ? "s" : ""}` : "";
      return `<article class="calendar-cell ${cell.inMonth ? "" : "muted"}"><div class="day">${cell.day}</div><div class="count">${countLabel}</div></article>`;
    })
    .join("");
}

function renderAppData() {
  renderHome();
  renderAgenda();
  renderCalendar();
}

function switchTab(tabId) {
  currentTab = tabId;
  tabButtons.forEach((button) => {
    button.classList.toggle("active", button.dataset.tab === tabId);
  });
  pages.forEach((page) => {
    page.hidden = page.dataset.page !== tabId;
  });
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
  snapshotPayload = {};
  events = [];
  localStorage.removeItem(TOKEN_KEY);
  authScreen.hidden = false;
  appShell.hidden = true;
  accountInfo.textContent = "Signed out";
  householdInfo.textContent = "No household loaded";
  welcomeText.textContent = "Welcome";
  snapshotText.value = "";
  switchTab("home");
  setAuthMode("signin");
}

async function refreshState() {
  if (!token) {
    setSignedOut();
    return;
  }

  authScreen.hidden = true;
  appShell.hidden = false;

  try {
    const me = await api("/me");
    accountInfo.textContent = `${me.user.displayName} (${me.user.email})`;
    welcomeText.textContent = `Welcome, ${me.user.displayName}`;
    displayNameInput.value = me.user.displayName;

    try {
      const current = await api("/households/current");
      const householdName = current.household?.name ?? "Unknown household";
      const role = current.membership?.role ?? "Member";
      const code = current.household?.code ? ` | code: ${current.household.code}` : "";
      householdInfo.textContent = `${householdName} (${role})${code}`;
    } catch {
      householdInfo.textContent = "No household yet. Create or join in Settings.";
    }

    try {
      const snapshot = await api("/sync/snapshot");
      snapshotPayload = snapshot.snapshot?.payload ?? {};
      snapshotText.value = JSON.stringify(snapshotPayload, null, 2);
      events = extractEventsFromPayload(snapshotPayload);
    } catch {
      snapshotPayload = {};
      events = [];
      snapshotText.value = "";
    }

    renderAppData();
    switchTab(currentTab);
    setStatus("Session ready.", "ok");
  } catch (error) {
    setSignedOut();
    setStatus(error.message, "warn");
  }
}

modeSignIn.addEventListener("click", () => setAuthMode("signin"));
modeCreate.addEventListener("click", () => setAuthMode("create"));

onboardingNextBtn.addEventListener("click", () => {
  onboardingIndex = (onboardingIndex + 1) % onboardingPages.length;
  renderOnboarding(onboardingIndex);
});

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
    setStatus("Signed in.", "ok");
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
    setStatus("Account created.", "ok");
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
    snapshotPayload = response.snapshot?.payload ?? {};
    snapshotText.value = JSON.stringify(snapshotPayload, null, 2);
    events = extractEventsFromPayload(snapshotPayload);
    renderAppData();
    setStatus("Snapshot loaded.", "ok");
  } catch (error) {
    setStatus(error.message, "warn");
  }
});

saveSnapshotBtn.addEventListener("click", async () => {
  try {
    snapshotPayload = snapshotText.value.trim() ? JSON.parse(snapshotText.value) : {};
    await api("/sync/snapshot", {
      method: "PUT",
      body: JSON.stringify({ payload: snapshotPayload })
    });
    events = extractEventsFromPayload(snapshotPayload);
    renderAppData();
    setStatus("Snapshot saved.", "ok");
  } catch (error) {
    const message = error instanceof SyntaxError ? "Snapshot JSON is invalid." : error.message;
    setStatus(message, "warn");
  }
});

agendaSearch.addEventListener("input", renderAgenda);

prevMonthBtn.addEventListener("click", () => {
  currentMonth = new Date(currentMonth.getFullYear(), currentMonth.getMonth() - 1, 1);
  renderCalendar();
});

nextMonthBtn.addEventListener("click", () => {
  currentMonth = new Date(currentMonth.getFullYear(), currentMonth.getMonth() + 1, 1);
  renderCalendar();
});

tabButtons.forEach((button) => {
  button.addEventListener("click", () => switchTab(button.dataset.tab));
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

setAuthMode("signin");
renderOnboarding(0);
startOnboardingAuto();
refreshState();
