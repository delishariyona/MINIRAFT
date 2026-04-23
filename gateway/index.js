const express = require("express");
const http = require("http");
const WebSocket = require("ws");
const axios = require("axios");

const app = express();
app.use(express.json());
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  next();
});

const PORT = parseInt(process.env.PORT) || 3000;
const REPLICAS = (process.env.REPLICAS || "").split(",").filter(Boolean);

// ─── Leader Discovery ─────────────────────────────────────────────────────────
let currentLeader = null;
let leaderDiscoveryRunning = false;

async function discoverLeader() {
  for (const replica of REPLICAS) {
    try {
      const res = await axios.get(`${replica}/status`, { timeout: 400 });
      if (res.data.state === "leader") {
        if (currentLeader !== replica) {
          console.log(`[Gateway] New leader discovered: ${replica} (term=${res.data.term})`);
          currentLeader = replica;
        }
        return replica;
      }
    } catch (_) {}
  }
  console.warn("[Gateway] No leader found");
  currentLeader = null;
  return null;
}

// Continuously poll for leader
async function pollLeader() {
  while (true) {
    await discoverLeader();
    await sleep(300);
  }
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// ─── WebSocket Setup ──────────────────────────────────────────────────────────
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const clients = new Set();

wss.on("connection", (ws) => {
  clients.add(ws);
  console.log(`[Gateway] Client connected (total=${clients.size})`);

  // Send current committed log to new client so they see existing canvas
  sendLogToClient(ws);

  ws.on("message", async (data) => {
    let stroke;
    try {
      stroke = JSON.parse(data);
    } catch {
      return;
    }

    // Forward stroke to leader
    let attempts = 0;
    while (attempts < 5) {
      attempts++;
      const leader = currentLeader || (await discoverLeader());

      if (!leader) {
        await sleep(200);
        continue;
      }

      try {
        const res = await axios.post(`${leader}/stroke`, stroke, { timeout: 800 });
        if (res.status === 200 && res.data.ok) {
          // Broadcast committed stroke to all clients
          broadcast(JSON.stringify({ type: "stroke", data: stroke }));
          return;
        }
      } catch (err) {
        if (err.response && err.response.status === 307) {
          // Leader redirect
          currentLeader = null;
          await discoverLeader();
        } else {
          currentLeader = null;
        }
        await sleep(150);
      }
    }
    console.error("[Gateway] Failed to replicate stroke after retries");
  });

  ws.on("close", () => {
    clients.delete(ws);
    console.log(`[Gateway] Client disconnected (total=${clients.size})`);
  });
});

function broadcast(message) {
  for (const client of clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  }
}

// Send full log to a newly connected client
async function sendLogToClient(ws) {
  const leader = currentLeader || (await discoverLeader());
  if (!leader) return;
  try {
    const res = await axios.get(`${leader}/sync-log?from=0`, { timeout: 1000 });
    const entries = res.data.entries || [];
    if (ws.readyState === WebSocket.OPEN && entries.length > 0) {
      ws.send(JSON.stringify({ type: "init", strokes: entries.map((e) => e.entry) }));
    }
  } catch (_) {}
}

// ─── HTTP Routes ──────────────────────────────────────────────────────────────
app.get("/health", (req, res) => res.json({ ok: true }));

app.get("/leader", (req, res) => {
  res.json({ leader: currentLeader });
});

// Cluster status proxy — browser calls this instead of replicas directly
// (browser can't reach replica ports cross-origin, gateway fetches on its behalf)
app.get("/cluster-status", async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  const results = await Promise.allSettled(
    REPLICAS.map((url) =>
      axios.get(`${url}/status`, { timeout: 400 }).then((r) => r.data)
    )
  );
  const statuses = REPLICAS.map((url, i) => {
    const r = results[i];
    const id = url.replace(/.*\/\//, "").split(":")[0]; // e.g. "replica1"
    if (r.status === "fulfilled") return { id, ...r.value, online: true };
    return { id, online: false };
  });
  res.json(statuses);
});

// ─── Boot ─────────────────────────────────────────────────────────────────────
server.listen(PORT, () => {
  console.log(`[Gateway] WebSocket server running on port ${PORT}`);
  pollLeader();
});

process.on("SIGTERM", () => {
  console.log("[Gateway] Shutting down");
  server.close();
  process.exit(0);
});
