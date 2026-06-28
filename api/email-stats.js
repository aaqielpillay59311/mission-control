// ════════════════════════════════════════════════════════════
// /api/email-stats  ·  Mission Control · server-side Resend proxy
// ════════════════════════════════════════════════════════════
// The Resend API key lives ONLY in the RESEND_API_KEY env var and is never
// shipped to the browser. The dashboard calls this endpoint, which fetches the
// recent emails from Resend, computes a small summary, and returns JSON.
//
// A warm-instance in-memory cache (5 min) keeps us well under Resend's rate
// limits even if several tabs hit the endpoint. The browser also caches the
// response for 5 min in sessionStorage, so the API is rarely touched.
//
// Set the key once:  vercel env add RESEND_API_KEY production
// (Vercel zero-config picks up this file as a Node Serverless Function.)

let _cache = { at: 0, payload: null };
const TTL  = 5 * 60 * 1000;          // 5 minutes
const SAST = 2 * 60 * 60 * 1000;     // UTC+2 (South Africa) — for "today" boundary

// Best-effort friendly company name from the recipient address.
function companyFromTo(to) {
  const addr = Array.isArray(to) ? to[0] : to;
  if (!addr) return "Unknown";
  const dom = String(addr).split("@")[1] || String(addr);
  const label = (dom.split(".")[0] || dom).replace(/[-_]+/g, " ").trim();
  return label ? label.charAt(0).toUpperCase() + label.slice(1) : String(addr);
}

// Normalise Resend's last_event into one of our status words.
function normStatus(ev) {
  const e = String(ev || "").toLowerCase();
  if (e.includes("complain") || e.includes("bounce")) return "bounced";
  if (e.includes("click"))  return "clicked";
  if (e.includes("open"))   return "opened";
  if (e.includes("deliver"))return "delivered";
  if (e.includes("sent") || e.includes("queue") || e.includes("schedul")) return "sent";
  return e || "sent";
}

module.exports = async (req, res) => {
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");

  const key = process.env.RESEND_API_KEY;
  if (!key) {
    res.statusCode = 500;
    res.end(JSON.stringify({ ok: false, error: "RESEND_API_KEY is not configured on the server" }));
    return;
  }

  // Serve the warm-instance cache when it's still fresh.
  if (_cache.payload && (Date.now() - _cache.at) < TTL) {
    res.statusCode = 200;
    res.end(JSON.stringify(Object.assign({}, _cache.payload, { cached: true })));
    return;
  }

  try {
    const r = await fetch("https://api.resend.com/emails", {
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    });

    if (!r.ok) {
      const detail = await r.text().catch(() => "");
      res.statusCode = 502;
      res.end(JSON.stringify({ ok: false, error: `Resend responded ${r.status}`, detail: detail.slice(0, 200) }));
      return;
    }

    const body = await r.json();
    const list = Array.isArray(body) ? body
      : (body && Array.isArray(body.data))   ? body.data
      : (body && Array.isArray(body.emails)) ? body.emails
      : [];

    const now = Date.now();
    const todayStart = (() => { const d = new Date(now + SAST); d.setUTCHours(0, 0, 0, 0); return d.getTime() - SAST; })();
    const weekStart  = now - 7 * 24 * 60 * 60 * 1000;

    let today = 0, week = 0, delivered = 0, opened = 0, clicked = 0, bounced = 0;

    const items = list.map((e) => {
      const at = e.created_at || e.createdAt || e.sent_at || null;
      const ms = at ? Date.parse(at) : NaN;
      if (!isNaN(ms)) {
        if (ms >= todayStart) today++;
        if (ms >= weekStart)  week++;
      }
      const status = normStatus(e.last_event || e.status);
      if (status === "delivered" || status === "opened" || status === "clicked") delivered++;
      if (status === "opened"    || status === "clicked") opened++;
      if (status === "clicked")  clicked++;
      if (status === "bounced")  bounced++;
      return {
        company: companyFromTo(e.to),
        to: Array.isArray(e.to) ? e.to[0] : (e.to || ""),
        subject: e.subject || "",
        status,
        // Normalise to clean ISO so every browser (incl. Safari) can parse it —
        // Resend returns e.g. "2026-06-27 23:26:25.588816+00".
        at: isNaN(ms) ? at : new Date(ms).toISOString(),
      };
    });

    items.sort((a, b) => (Date.parse(b.at) || 0) - (Date.parse(a.at) || 0));

    const total = items.length;
    const payload = {
      ok: true,
      totals: { today, week, total },
      rates: {
        open:      delivered ? opened / delivered  : 0,   // opened ÷ delivered
        click:     delivered ? clicked / delivered : 0,   // clicked ÷ delivered
        bounce:    total ? bounced / total : 0,           // bounced ÷ sampled
        delivered: total ? delivered / total : 0,
      },
      recent: items.slice(0, 5),
      sample_size: total,        // computed from the most recent emails Resend returns
      fetched_at: new Date(now).toISOString(),
      cached: false,
    };

    _cache = { at: now, payload };
    res.statusCode = 200;
    res.end(JSON.stringify(payload));
  } catch (err) {
    res.statusCode = 502;
    res.end(JSON.stringify({ ok: false, error: String((err && err.message) || err) }));
  }
};
