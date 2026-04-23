const express = require("express");
const axios = require("axios");

const app = express();
app.use(express.json());

const REPLICA_ID = process.env.REPLICA_ID || "replica1";
const PORT = parseInt(process.env.PORT) || 4001;
const PEERS = (process.env.PEERS || "").split(",").filter(Boolean);

let state = "follower";
let currentTerm = 0;
let votedFor = null;
let raftLog = [];
let commitIndex = -1;
let leaderId = null;
let electionTimer = null;
let heartbeatTimer = null;

function randomElectionTimeout() { return 500 + Math.floor(Math.random() * 300); }
function ts() { return new Date().toISOString().substr(11,12); }
function log_msg(msg) { console.log(`[${ts()}][${REPLICA_ID}][term=${currentTerm}][${state.toUpperCase()}] ${msg}`); }

function resetElectionTimer() {
  clearTimeout(electionTimer);
  electionTimer = setTimeout(startElection, randomElectionTimeout());
}
function stopElectionTimer() { clearTimeout(electionTimer); }
function stopHeartbeatTimer() { clearInterval(heartbeatTimer); }

async function startElection() {
  if (state === "leader") return;
  state = "candidate";
  currentTerm += 1;
  votedFor = REPLICA_ID;
  let votes = 1;
  log_msg(`ELECTION started for term ${currentTerm}`);

  const lastLogIndex = raftLog.length - 1;
  const lastLogTerm = lastLogIndex >= 0 ? raftLog[lastLogIndex].term : 0;

  const requests = PEERS.map(async (peer) => {
    try {
      const res = await axios.post(`${peer}/request-vote`,
        { term: currentTerm, candidateId: REPLICA_ID, lastLogIndex, lastLogTerm },
        { timeout: 300 });
      if (res.data.voteGranted) { log_msg(`VOTE GRANTED by ${peer}`); return true; }
      if (res.data.term > currentTerm) stepDown(res.data.term);
    } catch (_) {}
    return false;
  });

  const results = await Promise.allSettled(requests);
  results.forEach(r => { if (r.status === "fulfilled" && r.value) votes++; });
  const majority = Math.floor((PEERS.length + 1) / 2) + 1;

  if (state === "candidate" && votes >= majority) {
    becomeLeader();
  } else {
    log_msg(`ELECTION LOST (votes=${votes}/${PEERS.length+1}), back to follower`);
    stepDown(currentTerm);
    resetElectionTimer();
  }
}

function becomeLeader() {
  state = "leader";
  leaderId = REPLICA_ID;
  log_msg(`BECAME LEADER — heartbeat interval 150ms`);
  stopElectionTimer();
  sendHeartbeats();
  heartbeatTimer = setInterval(sendHeartbeats, 150);
}

async function sendHeartbeats() {
  if (state !== "leader") return;
  for (const peer of PEERS) {
    try {
      await axios.post(`${peer}/heartbeat`, { term: currentTerm, leaderId: REPLICA_ID }, { timeout: 200 });
    } catch (_) {}
  }
}

function stepDown(term) {
  const was = state;
  if (term > currentTerm) { currentTerm = term; votedFor = null; }
  state = "follower";
  leaderId = null;
  stopHeartbeatTimer();
  if (was !== "follower") log_msg(`STEPPED DOWN to follower (term=${term})`);
}

async function replicateEntry(entry) {
  if (state !== "leader") throw new Error("Not leader");
  const newIndex = raftLog.length;
  const logEntry = { term: currentTerm, index: newIndex, entry };
  raftLog.push(logEntry);
  log_msg(`APPEND entry[${newIndex}], replicating...`);

  let acks = 1;
  const majority = Math.floor((PEERS.length + 1) / 2) + 1;

  const replicatePromises = PEERS.map(async (peer) => {
    try {
      const prevLogIndex = newIndex - 1;
      const prevLogTerm = prevLogIndex >= 0 ? raftLog[prevLogIndex].term : 0;
      const res = await axios.post(`${peer}/append-entries`, {
        term: currentTerm, leaderId: REPLICA_ID,
        prevLogIndex, prevLogTerm,
        entries: [logEntry], leaderCommit: commitIndex
      }, { timeout: 500 });

      if (res.data.success) return true;

      // Per spec §4.5: follower sends back its logLength, leader pushes missing entries
      if (res.data.success === false && res.data.logLength !== undefined) {
        log_msg(`SYNC PUSH to ${peer} (peer has ${res.data.logLength} entries)`);
        await pushSyncToPeer(peer, res.data.logLength);
      }
      if (res.data.term > currentTerm) stepDown(res.data.term);
    } catch (_) {}
    return false;
  });

  const results = await Promise.allSettled(replicatePromises);
  results.forEach(r => { if (r.status === "fulfilled" && r.value) acks++; });

  if (acks >= majority) {
    commitIndex = newIndex;
    log_msg(`COMMITTED entry[${newIndex}] (acks=${acks}/${PEERS.length+1})`);
    return logEntry;
  } else {
    raftLog.pop();
    throw new Error(`No majority (acks=${acks})`);
  }
}

async function pushSyncToPeer(peer, fromIndex) {
  try {
    const missing = raftLog.slice(fromIndex).filter(e => e.index <= commitIndex);
    if (missing.length === 0) return;
    await axios.post(`${peer}/receive-sync`, { entries: missing, commitIndex }, { timeout: 1000 });
    log_msg(`SYNC PUSH ${missing.length} entries to ${peer}`);
  } catch (_) {}
}

// ── Routes ──────────────────────────────────────────────────────────────────

app.get("/health", (req, res) => res.json({ ok: true, id: REPLICA_ID, state, term: currentTerm }));

app.get("/status", (req, res) => res.json({
  id: REPLICA_ID, state, term: currentTerm, leaderId,
  logLength: raftLog.length, commitIndex, peers: PEERS
}));

app.post("/request-vote", (req, res) => {
  const { term, candidateId, lastLogIndex, lastLogTerm } = req.body;
  if (term > currentTerm) stepDown(term);

  const myLast = raftLog.length - 1;
  const myLastTerm = myLast >= 0 ? raftLog[myLast].term : 0;
  const logOk = lastLogTerm > myLastTerm || (lastLogTerm === myLastTerm && lastLogIndex >= myLast);
  const canVote = term >= currentTerm && (votedFor === null || votedFor === candidateId) && logOk;

  if (canVote) {
    votedFor = candidateId;
    currentTerm = term;
    resetElectionTimer();
    log_msg(`VOTED for ${candidateId} in term ${term}`);
    return res.json({ term: currentTerm, voteGranted: true });
  }
  res.json({ term: currentTerm, voteGranted: false });
});

let heartbeatCount = 0;
app.post("/heartbeat", (req, res) => {
  const { term, leaderId: newLeader } = req.body;
  if (term >= currentTerm) {
    if (term > currentTerm || state !== "follower") stepDown(term);
    currentTerm = term;
    leaderId = newLeader;
    resetElectionTimer();
    heartbeatCount++;
    if (heartbeatCount % 10 === 0) {
      log_msg(`HEARTBEAT #${heartbeatCount} received from ${newLeader} (term=${term}) — election timer reset`);
    }
  }
  res.json({ term: currentTerm, ok: true });
});

app.post("/append-entries", (req, res) => {
  const { term, leaderId: newLeader, prevLogIndex, prevLogTerm, entries, leaderCommit } = req.body;
  if (term < currentTerm) return res.json({ term: currentTerm, success: false });

  if (term > currentTerm || state !== "follower") stepDown(term);
  currentTerm = term;
  leaderId = newLeader;
  resetElectionTimer();

  if (prevLogIndex >= 0) {
    if (raftLog.length <= prevLogIndex || raftLog[prevLogIndex].term !== prevLogTerm) {
      log_msg(`LOG MISMATCH at prevLogIndex=${prevLogIndex}, my logLength=${raftLog.length}`);
      return res.json({ term: currentTerm, success: false, logLength: raftLog.length });
    }
  }

  for (const e of entries) {
    if (raftLog.length > e.index) {
      if (raftLog[e.index].term !== e.term) { raftLog = raftLog.slice(0, e.index); raftLog.push(e); }
    } else {
      raftLog.push(e);
    }
  }

  if (leaderCommit > commitIndex) commitIndex = Math.min(leaderCommit, raftLog.length - 1);
  res.json({ term: currentTerm, success: true });
});

app.get("/sync-log", (req, res) => {
  const from = parseInt(req.query.from) || 0;
  const entries = raftLog.slice(from).filter(e => e.index <= commitIndex);
  res.json({ entries, commitIndex, totalEntries: raftLog.length });
});

// Leader pushes missing entries to catching-up follower
app.post("/receive-sync", (req, res) => {
  const { entries, commitIndex: leaderCommit } = req.body;
  for (const e of entries) {
    if (raftLog.length <= e.index) raftLog.push(e);
  }
  if (leaderCommit > commitIndex) commitIndex = Math.min(leaderCommit, raftLog.length - 1);
  log_msg(`RECEIVED SYNC: ${raftLog.length} entries total, commitIndex=${commitIndex}`);
  res.json({ ok: true });
});

app.post("/stroke", async (req, res) => {
  if (state !== "leader") return res.status(307).json({ error: "Not leader", leaderId });
  try {
    const committed = await replicateEntry(req.body);
    res.json({ ok: true, entry: committed });
  } catch (err) {
    log_msg(`STROKE FAILED: ${err.message}`);
    res.status(500).json({ error: err.message });
  }
});

// ── Startup catch-up ─────────────────────────────────────────────────────────
async function catchUpOnStart() {
  log_msg("Checking for existing leader to sync from...");
  for (const peer of PEERS) {
    try {
      const s = await axios.get(`${peer}/status`, { timeout: 500 });
      if (s.data.state === "leader") {
        const sync = await axios.get(`${peer}/sync-log?from=0`, { timeout: 1000 });
        raftLog = sync.data.entries;
        commitIndex = sync.data.commitIndex;
        log_msg(`SYNCED from ${peer}: ${raftLog.length} entries`);
        return;
      }
    } catch (_) {}
  }
  log_msg("No leader found on startup — starting fresh");
}

app.listen(PORT, async () => {
  log_msg(`STARTED on port ${PORT}`);
  await catchUpOnStart();
  resetElectionTimer();
});

process.on("SIGTERM", () => {
  log_msg("SIGTERM — graceful shutdown");
  stopElectionTimer();
  stopHeartbeatTimer();
  process.exit(0);
});
