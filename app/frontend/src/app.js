// The browser only talks to /api/*; nginx proxies that to the api Service (see nginx.conf).
const $ = (s) => document.querySelector(s);

async function api(path, opts) {
  const res = await fetch(`/api${path}`, opts);
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(body.detail || res.statusText), { status: res.status });
  return body;
}

function setStatus(el, text, ok) {
  el.textContent = text;
  el.className = ok ? "ok" : "bad";
}

async function refreshStatus() {
  try {
    const h = await api("/health");
    setStatus($("#st-health"), "up", true);
    $("#st-version").textContent = h.version;
  } catch { setStatus($("#st-health"), "unreachable", false); }
  try { await api("/ready"); setStatus($("#st-ready"), "connected", true); }
  catch { setStatus($("#st-ready"), "unavailable", false); }
}

async function loadOrders() {
  const tbody = $("#orders");
  try {
    const rows = await api("/orders");
    if (!rows.length) return;
    tbody.replaceChildren(...rows.map((r) => {
      const tr = document.createElement("tr");
      [r.id, r.item, r.quantity, new Date(r.created_at).toLocaleString()].forEach((v, i) => {
        const td = document.createElement("td");
        td.textContent = v;            // textContent, never innerHTML: item names are user input
        if (i === 2) td.className = "num";
        tr.append(td);
      });
      return tr;
    }));
  } catch (e) { $("#order-msg").textContent = `Could not load orders: ${e.message}`; }
}

$("#order-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const f = new FormData(ev.target);
  try {
    await api("/orders", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ item: f.get("item"), quantity: Number(f.get("quantity")) }),
    });
    $("#order-msg").textContent = "Order placed.";
    ev.target.reset();
    loadOrders();
  } catch (e) { $("#order-msg").textContent = `Order failed: ${e.message}`; }
});

$("#drill").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const f = new FormData(ev.target);
  const btn = ev.submitter; btn.disabled = true;
  const url = `/fail?rate=${Number(f.get("rate"))}&delay_ms=${Number(f.get("delay"))}`;
  const n = Number(f.get("count"));
  let failed = 0;
  await Promise.all(Array.from({ length: n }, () => api(url).catch(() => { failed++; })));
  $("#drill-out").textContent = `${n} requests sent: ${failed} failed, ${n - failed} succeeded.`;
  btn.disabled = false;
});

refreshStatus(); loadOrders();
setInterval(refreshStatus, 10000);
