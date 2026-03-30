// Jedit Stats Worker
// messages.json をプロキシしつつ、日別ユニークユーザー数を記録する

const GITHUB_RAW_URL = "https://raw.githubusercontent.com/cometheart314/Jedit-open/main/messages.json";

// IP アドレスを SHA-256 でハッシュ化（プライバシー保護）
async function hashIP(ip) {
  const data = new TextEncoder().encode(ip);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(hash);
  return Array.from(bytes.slice(0, 8))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// 今日の日付を YYYY-MM-DD で返す（UTC）
function today() {
  return new Date().toISOString().slice(0, 10);
}

// DAU を記録する
async function recordVisit(env, ip) {
  const date = today();
  const ipHash = await hashIP(ip);
  const key = `v:${date}:${ipHash}`;

  // 既に記録済みかチェック
  const existing = await env.STATS.get(key);
  if (existing) return;

  // 新規ユニークユーザーを記録（30日後に自動削除）
  await env.STATS.put(key, "1", { expirationTtl: 30 * 86400 });

  // カウンターを更新（read-increment-write、低トラフィックなら十分正確）
  const countKey = `dau:${date}`;
  const current = parseInt((await env.STATS.get(countKey)) || "0", 10);
  await env.STATS.put(countKey, String(current + 1), {
    expirationTtl: 365 * 86400,
  });
}

// messages.json をGitHubから取得してプロキシ
async function handleMessages(request, env) {
  const ip =
    request.headers.get("CF-Connecting-IP") ||
    request.headers.get("X-Forwarded-For") ||
    "unknown";

  // 統計を非同期で記録（レスポンスをブロックしない）
  const statsPromise = recordVisit(env, ip).catch((e) =>
    console.error("Stats error:", e)
  );

  // GitHub から messages.json を取得
  const response = await fetch(GITHUB_RAW_URL, {
    headers: {
      "User-Agent": "Jedit-Stats-Worker",
    },
  });

  // 統計記録の完了を待つ
  await statsPromise;

  // レスポンスをそのまま返す（CORSヘッダー付き）
  return new Response(response.body, {
    status: response.status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

// 認証チェック
function checkAuth(request, env) {
  const url = new URL(request.url);
  const token = url.searchParams.get("token");
  return token && token === (env.STATS_TOKEN || "jedit-stats-secret");
}

// 直近30日分のDAUデータを取得
async function fetchStats(env) {
  const stats = {};
  const now = new Date();

  for (let i = 0; i < 30; i++) {
    const d = new Date(now);
    d.setDate(d.getDate() - i);
    const date = d.toISOString().slice(0, 10);
    const count = await env.STATS.get(`dau:${date}`);
    stats[date] = count ? parseInt(count, 10) : 0;
  }
  return stats;
}

// JSON API（直近30日分）
async function handleStats(request, env) {
  if (!checkAuth(request, env)) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const stats = await fetchStats(env);

  return new Response(JSON.stringify({ dau: stats }, null, 2), {
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
    },
  });
}

// HTML ダッシュボード
async function handleDashboard(request, env) {
  if (!checkAuth(request, env)) {
    return new Response(unauthorizedHTML(), {
      status: 401,
      headers: { "Content-Type": "text/html; charset=utf-8" },
    });
  }

  const stats = await fetchStats(env);

  // 日付の古い順にソート
  const dates = Object.keys(stats).sort();
  const counts = dates.map((d) => stats[d]);
  const maxCount = Math.max(...counts, 1);
  const totalUsers = counts.reduce((a, b) => a + b, 0);
  const avgUsers = dates.length > 0 ? Math.round(totalUsers / dates.length) : 0;
  const todayCount = stats[new Date().toISOString().slice(0, 10)] || 0;

  const html = `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Jedit DAU Dashboard</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #0f172a; color: #e2e8f0; padding: 24px; min-height: 100vh; }
  h1 { font-size: 22px; font-weight: 600; margin-bottom: 24px; color: #f8fafc; }
  .cards { display: flex; gap: 16px; margin-bottom: 32px; flex-wrap: wrap; }
  .card { background: #1e293b; border-radius: 12px; padding: 20px 24px; flex: 1; min-width: 140px; }
  .card-label { font-size: 12px; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px; }
  .card-value { font-size: 32px; font-weight: 700; color: #38bdf8; }
  .chart-container { background: #1e293b; border-radius: 12px; padding: 24px; }
  .chart-title { font-size: 14px; color: #94a3b8; margin-bottom: 16px; }
  .chart { display: flex; align-items: flex-end; gap: 4px; height: 200px; }
  .bar-group { flex: 1; display: flex; flex-direction: column; align-items: center; min-width: 0; }
  .bar { width: 100%; min-width: 8px; max-width: 28px; background: linear-gradient(to top, #0ea5e9, #38bdf8); border-radius: 4px 4px 0 0; transition: opacity 0.2s; cursor: default; position: relative; }
  .bar:hover { opacity: 0.8; }
  .bar-label { font-size: 10px; color: #64748b; margin-top: 8px; white-space: nowrap; writing-mode: vertical-rl; text-orientation: mixed; max-height: 60px; overflow: hidden; }
  .tooltip { position: absolute; top: -32px; left: 50%; transform: translateX(-50%); background: #334155; color: #f1f5f9; font-size: 12px; padding: 4px 8px; border-radius: 4px; white-space: nowrap; pointer-events: none; opacity: 0; transition: opacity 0.15s; }
  .bar:hover .tooltip { opacity: 1; }
  .table-container { background: #1e293b; border-radius: 12px; padding: 24px; margin-top: 24px; }
  table { width: 100%; border-collapse: collapse; }
  th { text-align: left; font-size: 12px; color: #94a3b8; text-transform: uppercase; letter-spacing: 0.05em; padding: 8px 12px; border-bottom: 1px solid #334155; }
  td { padding: 8px 12px; font-size: 14px; border-bottom: 1px solid #1e293b; }
  tr:nth-child(even) { background: #162032; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  .bar-inline { display: inline-block; height: 14px; background: #0ea5e9; border-radius: 3px; vertical-align: middle; margin-left: 8px; }
  footer { margin-top: 32px; text-align: center; font-size: 12px; color: #475569; }
</style>
</head>
<body>
<h1>Jedit Daily Active Users</h1>

<div class="cards">
  <div class="card">
    <div class="card-label">Today</div>
    <div class="card-value">${todayCount}</div>
  </div>
  <div class="card">
    <div class="card-label">30-Day Avg</div>
    <div class="card-value">${avgUsers}</div>
  </div>
  <div class="card">
    <div class="card-label">30-Day Total</div>
    <div class="card-value">${totalUsers.toLocaleString()}</div>
  </div>
</div>

<div class="chart-container">
  <div class="chart-title">Daily Active Users (past 30 days)</div>
  <div class="chart">
    ${dates
      .map((date, i) => {
        const h = maxCount > 0 ? Math.max((counts[i] / maxCount) * 180, counts[i] > 0 ? 4 : 0) : 0;
        const shortDate = date.slice(5); // MM-DD
        return `<div class="bar-group"><div class="bar" style="height:${h}px"><span class="tooltip">${shortDate}: ${counts[i]}</span></div><span class="bar-label">${shortDate}</span></div>`;
      })
      .join("")}
  </div>
</div>

<div class="table-container">
  <table>
    <thead><tr><th>Date</th><th class="num">Users</th><th>Distribution</th></tr></thead>
    <tbody>
      ${dates
        .slice()
        .reverse()
        .map((date, i) => {
          const c = stats[date];
          const barW = maxCount > 0 ? Math.max((c / maxCount) * 200, c > 0 ? 2 : 0) : 0;
          return `<tr><td>${date}</td><td class="num">${c}</td><td><span class="bar-inline" style="width:${barW}px"></span></td></tr>`;
        })
        .join("")}
    </tbody>
  </table>
</div>

<footer>Jedit Stats Dashboard &mdash; Data retained for 365 days</footer>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-cache",
    },
  });
}

function unauthorizedHTML() {
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Unauthorized</title>
<style>body{font-family:sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;background:#0f172a;color:#e2e8f0;}
.box{text-align:center;}.box h1{font-size:48px;margin-bottom:8px;}.box p{color:#94a3b8;}</style></head>
<body><div class="box"><h1>401</h1><p>Unauthorized &mdash; token required</p></div></body></html>`;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/messages.json" || url.pathname === "/") {
      return handleMessages(request, env);
    }

    if (url.pathname === "/stats") {
      return handleStats(request, env);
    }

    if (url.pathname === "/dashboard") {
      return handleDashboard(request, env);
    }

    return new Response("Not Found", { status: 404 });
  },
};
