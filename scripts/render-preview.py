#!/usr/bin/env python3
"""Renders the preview images in docs/preview/ (optional dev tool; needs: pip install playwright && playwright install chromium).

What is REAL and what is ILLUSTRATIVE:
  01-app-ui.png            REAL render of app/frontend (the actual HTML/CSS/JS), with the API mocked.
  02/03 grafana-*.png      Layout, titles, units and thresholds come from monitoring/dashboards/orders-red-slo.json;
                           the plotted DATA is synthetic. Not evidence of a real run.
  04-argocd-apps.png       Mock of the Argo CD UI listing the applications defined in argocd/apps/.
  05-jenkins-pipeline.png  Mock of the Jenkins stage view for ci/Jenkinsfile.
  06-alert-notification.png Mock of the Alertmanager message template from monitoring/kube-prometheus-stack/values.yaml.
Replace these with your own screenshots after running the project (see docs/incident-drill.md).
"""
import functools, html, http.server, json, math, os, pathlib, random, socketserver, subprocess, threading
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "preview"
OUT.mkdir(parents=True, exist_ok=True)
BANNER = "ILLUSTRATIVE PREVIEW · synthetic data · not a screenshot of a real run"


# ------------------------------------------------------------------ 01: the real frontend
def shot_app(browser):
    env = {**os.environ, "BUILD_VERSION": "b12-3fa91c2e"}
    subprocess.run(["node", "build.mjs"], cwd=ROOT / "app/frontend", env=env, check=True, capture_output=True)

    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a): pass

    srv = socketserver.TCPServer(("127.0.0.1", 0), functools.partial(Quiet, directory=str(ROOT / "app/frontend/dist")))
    threading.Thread(target=srv.serve_forever, daemon=True).start()

    orders = [
        {"id": 7, "item": "Marine flare kit", "quantity": 12, "created_at": "2026-10-03T09:58:40Z"},
        {"id": 6, "item": "Mooring rope 20m", "quantity": 4, "created_at": "2026-10-03T09:41:12Z"},
        {"id": 5, "item": "Stainless shackle 10mm", "quantity": 40, "created_at": "2026-10-03T09:12:03Z"},
        {"id": 4, "item": "Anchor chain 8mm x 30m", "quantity": 2, "created_at": "2026-10-02T16:25:47Z"},
        {"id": 3, "item": "LED navigation light", "quantity": 6, "created_at": "2026-10-02T14:02:19Z"},
        {"id": 2, "item": "Fender 45cm", "quantity": 8, "created_at": "2026-10-02T11:30:55Z"},
    ]
    n = {"fail": 0}

    def handle(route):
        u, status, body = route.request.url, 200, {}
        if "/api/health" in u: body = {"status": "ok", "version": "b12-3fa91c2e"}
        elif "/api/ready" in u: body = {"status": "ready"}
        elif "/api/orders" in u: body = orders
        elif "/api/fail" in u:
            n["fail"] += 1
            status, body = (500, {"detail": "injected failure"}) if n["fail"] % 5 in (1, 2, 3) else (200, {"injected": False})
        route.fulfill(status=status, content_type="application/json", body=json.dumps(body))

    ctx = browser.new_context(viewport={"width": 1280, "height": 760}, device_scale_factor=1.5, locale="en-GB", timezone_id="Asia/Kolkata")
    page = ctx.new_page()
    page.route("**/api/**", handle)
    page.goto(f"http://127.0.0.1:{srv.server_address[1]}/")
    page.wait_for_function("document.querySelector('#st-ready').textContent==='connected'")
    page.click("#drill button")
    page.wait_for_function("document.querySelector('#drill-out').textContent.includes('requests sent')")
    page.screenshot(path=str(OUT / "01-app-ui.png"), full_page=True)
    ctx.close(); srv.shutdown()


# ------------------------------------------------------------------ 02/03: Grafana-style dashboard
G, Y, R, B, O, P = "#73BF69", "#FADE2A", "#F2495C", "#5794F2", "#FF9830", "#B877D9"
BG = {"green": "#1a7f40", "yellow": "#8f7400", "red": "#a3232f", "transparent": "#2a2d33"}
N = 120


def synth(incident):
    rnd = random.Random(12 if incident else 11)
    n = lambda a: rnd.uniform(-a, a)
    S = 50
    r = lambda i: min(1, (i - S) / 10) if incident and i >= S else 0
    d = {}
    d["rate"] = [5.2 + 0.5 * math.sin(i / 8) + n(0.3) + 6 * r(i) for i in range(N)]
    d["err"] = [max(0, 0.15 + n(0.1) + 38 * r(i)) for i in range(N)]
    d["p50"] = [0.045 + n(0.004) + 0.18 * r(i) for i in range(N)]
    d["p95"] = [0.115 + n(0.012) + 0.62 * r(i) for i in range(N)]
    d["p99"] = [0.19 + n(0.02) + 1.3 * r(i) for i in range(N)]
    d["sli"] = [min(1, 0.996 + n(0.002) - 0.58 * r(i)) for i in range(N)]
    d["rs_a"] = [1 if incident and i in (53, 64) else 0 for i in range(N)]
    d["rs_b"] = [1 if incident and i in (58, 70) else 0 for i in range(N)]
    d["orders"] = [0.7 * d["rate"][i] + n(0.1) for i in range(N)]
    d["health"] = [0.5 + n(0.03) for _ in range(N)]
    d["ready"] = [0.4 + n(0.03) for _ in range(N)]
    d["fail"] = [5.0 * r(i) + n(0.1) * (1 if r(i) else 0) for i in range(N)]
    d["s200"] = [d["rate"][i] * (1 - d["err"][i] / 100) * 0.8 for i in range(N)]
    d["s201"] = [d["rate"][i] * (1 - d["err"][i] / 100) * 0.2 for i in range(N)]
    d["s500"] = [d["rate"][i] * d["err"][i] / 100 for i in range(N)]
    d["pods"] = 1 if incident else 2
    return d


def fmt(unit, v, dec=None):
    if unit == "reqps": return f"{v:.1f} req/s"
    if unit == "percent": return f"{v:.{2 if dec is None else dec}f}%"
    if unit == "percentunit": return f"{v * 100:.{2 if dec is None else dec}f}%"
    if unit == "s": return f"{v * 1000:.0f} ms" if v < 1 else f"{v:.2f} s"
    return f"{v:.0f}"


def color_for(steps, v):
    c = steps[0]["color"]
    for s in steps:
        if s["value"] is not None and v >= s["value"]: c = s["color"]
    return c


def ts_svg(w, h, lines, ymax, yunit, threshold=None):
    pl, pr, pt, pb = 52, 10, 8, 20
    pw, ph = w - pl - pr, h - pt - pb
    Y_ = lambda v: pt + ph * (1 - max(0, min(v, ymax)) / ymax)
    out = [f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}">']
    for k in range(5):
        v = ymax * k / 4; y = Y_(v)
        out.append(f'<line x1="{pl}" x2="{w - pr}" y1="{y:.1f}" y2="{y:.1f}" stroke="#2c3235"/>')
        out.append(f'<text x="{pl - 6}" y="{y + 4:.1f}" text-anchor="end" fill="#8e8e93" font-size="10">{fmt(yunit, v, 1 if yunit in ("percent", "percentunit") and ymax > 1 else None) if yunit != "percentunit" else f"{v * 100:.0f}%"}</text>')
    for k, t in enumerate(["09:42", "09:57", "10:12", "10:27", "10:42"]):
        x = pl + pw * k / 4
        anchor = "start" if k == 0 else ("end" if k == 4 else "middle")
        out.append(f'<text x="{x:.1f}" y="{h - 5}" text-anchor="{anchor}" fill="#8e8e93" font-size="10">{t}</text>')
    for _, color, vals in lines:
        pts = " ".join(f"{pl + pw * i / (N - 1):.1f},{Y_(v):.1f}" for i, v in enumerate(vals))
        out.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="1.8"/>')
    if threshold is not None:
        y = Y_(threshold)
        out.append(f'<line x1="{pl}" x2="{w - pr}" y1="{y:.1f}" y2="{y:.1f}" stroke="{R}" stroke-width="1.4" stroke-dasharray="5 4"/>')
    out.append("</svg>")
    return "".join(out)


def dashboard(incident, fname):
    dash = json.load(open(ROOT / "monitoring/dashboards/orders-red-slo.json"))
    d = synth(incident)
    W, PAD, RH = 1500, 14, 34
    cw = (W - 2 * PAD) / 24
    sli_mean = sum(d["sli"]) / N
    budget = max(0.0, 1 - (1 - sli_mean) / 0.01)
    stat_vals = {1: d["rate"][-1], 2: d["err"][-1], 3: d["p95"][-1], 4: sli_mean, 5: budget, 6: d["pods"]}
    ts_data = {
        10: ([("/orders", B, d["orders"]), ("/health", G, d["health"]), ("/ready", P, d["ready"])] + ([("/fail", R, d["fail"])] if incident else []), None, "reqps", None),
        11: ([("5xx %", R, d["err"])], 5, "percent", 6),
        12: ([("p50", G, d["p50"]), ("p95", Y, d["p95"]), ("p99", O, d["p99"])], 0.3, "s", 0.5),
        13: ([("SLI", B, d["sli"]), ("target 99%", G, [0.99] * N)], None, "percentunit", 1.0),
        14: ([("api-7d9c5b-x2k4q", R, d["rs_a"]), ("api-7d9c5b-m8v2z", O, d["rs_b"])], None, "short", 4),
        15: ([("200", G, d["s200"]), ("201", B, d["s201"]), ("500", R, d["s500"])], None, "reqps", None),
    }
    cells = []
    for p in dash["panels"]:
        g = p["gridPos"]
        x, y, w, h = PAD + g["x"] * cw + 4, 74 + g["y"] * RH + 4, g["w"] * cw - 8, g["h"] * RH - 8
        cfg = p["fieldConfig"]["defaults"]
        body = ""
        style = f"left:{x:.0f}px;top:{y:.0f}px;width:{w:.0f}px;height:{h:.0f}px;"
        if p["id"] in stat_vals:
            v = stat_vals[p["id"]]
            unit, dec = cfg.get("unit", "short"), cfg.get("decimals")
            col = BG[color_for(cfg["thresholds"]["steps"], v)]
            if p["type"] == "gauge":
                pct = max(0, min(1, v)); ang = math.pi * (1 - pct)
                cx, cy, rr = w / 2, h - 26, min(w / 2 - 14, h - 52)
                ex, ey = cx + rr * math.cos(ang), cy - rr * math.sin(ang)
                big = 1 if pct > 0.5 else 0
                body = (f'<svg width="{w:.0f}" height="{h - 28:.0f}"><path d="M {cx - rr:.0f} {cy:.0f} A {rr:.0f} {rr:.0f} 0 0 1 {cx + rr:.0f} {cy:.0f}" stroke="#2c3235" stroke-width="10" fill="none"/>'
                        f'<path d="M {cx - rr:.0f} {cy:.0f} A {rr:.0f} {rr:.0f} 0 {big} 1 {ex:.0f} {ey:.0f}" stroke="{G if pct > 0.5 else (Y if pct > 0.25 else R)}" stroke-width="10" fill="none"/>'
                        f'<text x="{cx:.0f}" y="{cy - 4:.0f}" text-anchor="middle" fill="#d8d9da" font-size="20" font-weight="600">{pct * 100:.0f}%</text></svg>')
                cells.append(f'<div class="panel" style="{style}"><div class="pt">{html.escape(p["title"])}</div>{body}</div>')
            else:
                cells.append(f'<div class="panel stat" style="{style}background:{col}"><div class="pt">{html.escape(p["title"])}</div>'
                             f'<div class="big">{fmt(unit, v, dec)}</div></div>')
            continue
        lines, thr, unit, ymax = ts_data[p["id"]]
        ymax = ymax or max(max(l[2]) for l in lines) * 1.2
        if p["id"] == 12: ymax = max(0.5, max(d["p99"]) * 1.1)
        if p["id"] == 11: ymax = max(6, max(d["err"]) * 1.2)
        legend = "".join(f'<span><i style="background:{c}"></i>{html.escape(n_)}</span>' for n_, c, _ in lines)
        body = ts_svg(int(w) - 20, int(h) - 58, lines, ymax, unit, thr) + f'<div class="legend">{legend}</div>'
        cells.append(f'<div class="panel" style="{style}"><div class="pt">{html.escape(p["title"])}</div>{body}</div>')

    firing = ('<span class="pill red">● FIRING 4: OrdersHighErrorRate · OrdersPodCrashLooping · OrdersHighLatencyP95 · OrdersLatencySLOFastBurn</span>'
              if incident else '<span class="pill green">● No alerts firing</span>')
    page = f"""<html><head><meta charset="utf-8"><style>
    body{{margin:0;background:#111217;color:#d8d9da;font-family:Inter,Helvetica,Arial,sans-serif;width:{W}px;height:{74 + 26 * RH + 20}px;position:relative}}
    .banner{{background:#3d3200;color:#ffd866;font-size:12px;text-align:center;padding:4px;letter-spacing:.3px}}
    .top{{height:34px;display:flex;align-items:center;justify-content:space-between;padding:0 16px;border-bottom:1px solid #2c3235;font-size:13px}}
    .top .crumb{{color:#8e8e93}} .top b{{color:#d8d9da}}
    .tools{{display:flex;gap:10px;align-items:center;font-size:12px}} .btn{{border:1px solid #2c3235;padding:3px 8px;border-radius:3px;color:#c7c7cc}}
    .pill{{padding:2px 9px;border-radius:10px;font-size:12px;font-weight:600}} .pill.red{{background:#4a1b21;color:#ff8c99}} .pill.green{{background:#173b25;color:#8fd39a}}
    .panel{{position:absolute;background:#181b1f;border:1px solid #2c3235;border-radius:3px;overflow:hidden}}
    .pt{{font-size:12.5px;padding:7px 10px;color:#d8d9da;font-weight:500}}
    .stat{{border:0}} .stat .pt{{color:#e9e9ec}} .big{{font-size:30px;font-weight:600;text-align:center;margin-top:2px;color:#fff}}
    .legend{{display:flex;gap:14px;font-size:11px;color:#c7c7cc;padding:0 12px}} .legend i{{display:inline-block;width:10px;height:3px;margin-right:5px;vertical-align:middle}}
    svg{{display:block;margin:0 auto}}
    </style></head><body>
    <div class="banner">{BANNER} · layout from monitoring/dashboards/orders-red-slo.json</div>
    <div class="top"><div class="crumb">Dashboards › Orders › <b>{html.escape(dash["title"])}</b></div>
    <div class="tools">{firing}<span class="btn">Last 1 hour</span><span class="btn">⟳ 15s</span></div></div>
    {''.join(cells)}</body></html>"""
    return page


# ------------------------------------------------------------------ 04-06: mocks
CSS_LIGHT = """body{margin:0;font-family:Inter,Helvetica,Arial,sans-serif;color:#1b2430;background:#eef1f4}
.banner{background:#fff4c2;color:#6b5600;font-size:12px;text-align:center;padding:5px}
.pad{padding:20px 28px}h1{font-size:20px;margin:0 0 4px}.muted{color:#5d6b7c;font-size:13px}
.card{background:#fff;border:1px solid #d5dce4;border-radius:6px;padding:14px 16px}
.badge{display:inline-block;font-size:11px;font-weight:600;padding:2px 8px;border-radius:10px;margin-right:6px}
.ok{background:#dff3e6;color:#16703d}.warn{background:#fdecc8;color:#8a5a00}.bad{background:#fbe0e0;color:#a3232f}
code{background:#eef1f4;padding:1px 5px;border-radius:3px;font-size:12px}"""


def argocd_html():
    apps = [("root", "default", "argocd/apps", "git"), ("orders-staging", "orders", "k8s/overlays/staging", "git"),
            ("sealed-secrets", "platform", "sealed-secrets 2.16.2", "helm"), ("kube-prometheus-stack", "platform", "kube-prometheus-stack 81.4.2", "helm"),
            ("trivy-operator", "platform", "trivy-operator 0.24.1", "helm"), ("monitoring-config", "platform", "monitoring/ (kustomize)", "git")]
    cards = "".join(f'<div class="card app"><div class="bar"></div><div class="nm">{n}</div><div class="muted">project: {p} · {s}</div>'
                    f'<div style="margin-top:8px"><span class="badge ok">● Healthy</span><span class="badge ok">✓ Synced</span><span class="badge" style="background:#e6ecf5;color:#34507a">auto-sync · self-heal · prune</span></div>'
                    f'<div class="muted" style="margin-top:6px">Last sync: {2 + i} minutes ago · target: main</div></div>' for i, (n, p, s, _) in enumerate(apps))
    tree = [(0, "App", "orders-staging", ""), (1, "cm", "api-config-8k2m5h", ""), (1, "svc", "api · frontend · postgres", ""), (1, "ing", "orders", ""),
            (1, "pdb", "api", ""), (1, "netpol", "default-deny-all · allow-dns-egress · frontend · api · postgres", ""),
            (1, "deploy", "api", "2/2"), (2, "rs", "api-7d9c5b6f4", "2/2"), (3, "pod", "api-7d9c5b6f4-x2k4q", "Running"), (3, "pod", "api-7d9c5b6f4-m8v2z", "Running"),
            (1, "deploy", "frontend", "2/2"), (2, "rs", "frontend-5c8d9f7b6", "2/2"), (3, "pod", "frontend-5c8d9f7b6-q7w4t", "Running"), (3, "pod", "frontend-5c8d9f7b6-h2n9d", "Running"),
            (1, "sts", "postgres", "1/1"), (2, "pod", "postgres-0", "Running")]
    rows = "".join(f'<div class="row" style="padding-left:{14 + lvl * 26}px"><span class="kind">{k}</span><b>{n}</b> <span class="muted">{info}</span><span class="dot">●</span></div>' for lvl, k, n, info in tree)
    return f"""<html><head><meta charset="utf-8"><style>{CSS_LIGHT}
    .layout{{display:flex;min-height:900px}} .side{{width:60px;background:#1f2d3d}} .main{{flex:1}}
    .grid{{display:grid;grid-template-columns:repeat(3,1fr);gap:14px;margin:16px 0 22px}}
    .app{{position:relative;padding-left:22px}} .app .bar{{position:absolute;left:0;top:0;bottom:0;width:6px;background:#2fa75b;border-radius:6px 0 0 6px}} .nm{{font-size:16px;font-weight:700;margin-bottom:2px}}
    .tree{{padding:6px 0}} .row{{padding:6px 14px;border-bottom:1px solid #eef1f4;font-size:13px;display:flex;align-items:center;gap:8px}} .dot{{margin-left:auto;color:#2fa75b}}
    .kind{{display:inline-block;min-width:44px;text-align:center;font-size:10px;font-weight:700;background:#e6ecf5;color:#34507a;border-radius:3px;padding:2px 4px}}
    </style></head><body style="width:1400px"><div class="banner">{BANNER}</div><div class="layout"><div class="side"></div><div class="main"><div class="pad">
    <h1>Applications</h1><div class="muted">Argo CD · app-of-apps · all applications defined in <code>argocd/apps/</code> · <b>6</b> Healthy · <b>6</b> Synced</div>
    <div class="grid">{cards}</div>
    <h1 style="margin-bottom:8px">orders-staging <span class="muted" style="font-weight:400">resource tree</span></h1>
    <div class="card tree">{rows}</div></div></div></div></body></html>"""


def jenkins_html():
    stages = [("Checkout", "4s"), ("Unit Test", "38s"), ("Docker Build", "1m 12s"), ("Trivy Scan", "49s"), ("Push Images", "31s"), ("Update Manifests", "6s")]
    boxes = "".join(f'<div class="stage"><div class="sn">{n}</div><div class="sd">{t}</div><div class="sb"></div></div>' for n, t in stages)
    arts = ["reports/trivy-api.json", "reports/trivy-frontend.json", "reports/sbom-api.cdx.json", "reports/sbom-frontend.cdx.json", "reports/unit-tests.log", "reports/image-digests.txt", "reports/trivy-config.json"]
    return f"""<html><head><meta charset="utf-8"><style>{CSS_LIGHT}
    .stages{{display:flex;gap:10px;margin:14px 0}} .stage{{flex:1;background:#fff;border:1px solid #d5dce4;border-radius:5px;overflow:hidden}}
    .sn{{font-weight:600;font-size:13px;padding:10px 12px 2px}} .sd{{color:#5d6b7c;font-size:12px;padding:0 12px 10px}} .sb{{height:7px;background:#2fa75b}}
    pre{{background:#10151c;color:#c9d4e3;padding:14px;border-radius:6px;font-size:12px;line-height:1.5;margin:0}} .g{{color:#6ee09a}} .two{{display:grid;grid-template-columns:1fr 1fr;gap:14px}}
    ul{{margin:6px 0 0;padding-left:18px;font-size:13px;line-height:1.8}}
    </style></head><body style="width:1300px"><div class="banner">{BANNER}</div><div class="pad">
    <h1>orders-platform <span class="badge ok">● #12 Success</span></h1><div class="muted">Started by SCM polling · commit 3fa91c2e · duration 3 min 20 s · image tag <code>b12-3fa91c2e</code></div>
    <div class="stages">{boxes}</div>
    <div class="two"><div class="card"><b>Build Artifacts</b><ul>{''.join(f'<li><code>{a}</code></li>' for a in arts)}</ul></div>
    <div class="card"><b>Pipeline result</b><ul><li>Trivy gate (api): <span class="badge ok">0 fixable HIGH/CRITICAL</span></li><li>Trivy gate (frontend): <span class="badge ok">0 fixable HIGH/CRITICAL</span></li>
    <li>Images pushed to <code>ghcr.io/adityasurve123/orders-*</code></li><li>Cluster access from Jenkins: <span class="badge ok">none (Git only)</span></li></ul></div></div>
    <div style="margin-top:14px"><pre><span class="g">[Trivy Scan]</span> === Trivy gate: api ===
Total: 0 (HIGH: 0, CRITICAL: 0)
<span class="g">[Update Manifests]</span> kustomize edit set image orders-api=ghcr.io/adityasurve123/orders-api:b12-3fa91c2e ...
<span class="g">[Update Manifests]</span> [main 9c1e7a2] chore(release): deploy b12-3fa91c2e to staging [skip ci]
<span class="g">[Update Manifests]</span> To github.com:ADITYASURVE123/secure-observable-gitops-platform.git   main -> main
Finished: <span class="g">SUCCESS</span></pre></div></div></body></html>"""


def alert_html():
    def msg(kind, title, lines, t):
        col = "#c0392b" if kind == "f" else "#2e8b57"
        label = "FIRING" if kind == "f" else "RESOLVED"
        body = "".join(f"<div>{html.escape(l)}</div>" for l in lines)
        return (f'<div class="m"><div class="av">AM</div><div class="mb"><div><b>Alertmanager</b> <span class="tag">APP</span> <span class="muted">{t}</span></div>'
                f'<div class="att" style="border-left:4px solid {col}"><div class="tt"><span style="color:{col}">● [{label}]</span> {title}</div>{body}<div class="rb">Runbook</div></div></div></div>')
    msgs = (msg("f", "OrdersHighErrorRate", ["CRITICAL API error rate is 31.4% (threshold 5%)", "More than 5% of API requests returned 5xx for 5 minutes."], "10:37")
            + msg("f", "OrdersPodCrashLooping", ["CRITICAL Pod api-7d9c5b6f4-x2k4q is crash-looping", "Container api in orders/api-7d9c5b6f4-x2k4q restarted repeatedly in the last 10 minutes."], "10:38")
            + msg("f", "OrdersLatencySLOFastBurn", ["CRITICAL Latency SLO is burning error budget 14x too fast", "Both the 5m and 1h windows exceed 14.4x the allowed share of requests slower than 300ms."], "10:40")
            + '<div class="div"><span>Later, after the fix</span></div>'
            + msg("r", "OrdersHighErrorRate", ["CRITICAL API error rate is 0.2% (threshold 5%)", "More than 5% of API requests returned 5xx for 5 minutes."], "11:02")
            + msg("r", "OrdersPodCrashLooping", ["CRITICAL Pod api-7d9c5b6f4-x2k4q is crash-looping", "Container api in orders/api-7d9c5b6f4-x2k4q restarted repeatedly in the last 10 minutes."], "11:04"))
    return f"""<html><head><meta charset="utf-8"><style>{CSS_LIGHT}
    body{{background:#fff;width:900px}} .head{{padding:12px 24px;border-bottom:1px solid #d5dce4;font-weight:700}} .m{{display:flex;gap:12px;padding:12px 24px}}
    .av{{width:38px;height:38px;border-radius:6px;background:#34507a;color:#fff;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700}}
    .mb{{flex:1;font-size:14px}} .tag{{font-size:10px;background:#e6ecf5;border-radius:3px;padding:1px 4px;color:#34507a}} .att{{margin-top:6px;padding:4px 12px;line-height:1.6}}
    .tt{{font-weight:700}} .rb{{color:#1264a3;margin-top:2px}} .div{{text-align:center;margin:8px 0;color:#5d6b7c;font-size:12px;border-top:1px solid #d5dce4;position:relative}} .div span{{background:#fff;position:relative;top:-9px;padding:0 10px}}
    </style></head><body><div class="banner">{BANNER} · text from the Alertmanager template in values.yaml</div><div class="head"># alerts <span class="muted" style="font-weight:400"> · chat channel receiving the Alertmanager webhook</span></div>{msgs}</body></html>"""


def shoot_html(browser, name, content, width):
    ctx = browser.new_context(viewport={"width": width, "height": 600}, device_scale_factor=1.5)
    page = ctx.new_page()
    page.set_content(content)
    page.screenshot(path=str(OUT / name), full_page=True)
    ctx.close()


if __name__ == "__main__":
    with sync_playwright() as pw:
        b = pw.chromium.launch()
        shot_app(b)
        shoot_html(b, "02-grafana-healthy.png", dashboard(False, ""), 1500)
        shoot_html(b, "03-grafana-incident.png", dashboard(True, ""), 1500)
        shoot_html(b, "04-argocd-apps.png", argocd_html(), 1400)
        shoot_html(b, "05-jenkins-pipeline.png", jenkins_html(), 1300)
        shoot_html(b, "06-alert-notification.png", alert_html(), 900)
        b.close()
    print("wrote", *sorted(p.name for p in OUT.glob("*.png")))
