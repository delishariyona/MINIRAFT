# MiniRAFT — Distributed Real-Time Drawing Board

A fault-tolerant, real-time collaborative drawing platform built on a Mini-RAFT consensus protocol. Multiple users can draw simultaneously on a shared canvas, with all strokes replicated and committed through a cluster of three replica nodes.


## What This Does

- Multiple users draw on a shared canvas in real time
- A 3-node RAFT cluster maintains a consistent stroke log
- If any replica fails, a new leader is elected automatically within 1 second
- Hot-reloading any replica causes zero downtime for connected clients
- Full failover, catch-up, and log replication as per RAFT spec


## System Architecture

```
  [Browser Tab 1]   [Browser Tab 2]   [Browser Tab N]
        |                  |                  |
        +------------------+------------------+
                           |
                    [GATEWAY :3000]
                    WebSocket Server
                    Leader Registry
                           |
          +----------------+----------------+
          |                |                |
   [REPLICA1 :4001]  [REPLICA2 :4002]  [REPLICA3 :4003]
   Mini-RAFT Node    Mini-RAFT Node    Mini-RAFT Node
   Append-Only Log   Append-Only Log   Append-Only Log
          |                |                |
          +----------------+----------------+
                    raft-net (Docker bridge)
```


## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | HTML, CSS, JavaScript (Canvas API) |
| Gateway | Node.js, Express, ws (WebSocket) |
| Replicas | Node.js, Express, nodemon (hot reload) |
| Containers | Docker, docker-compose |
| Protocol | Mini-RAFT (custom implementation) |


## Project Structure

```
MINIRAFT/
├── frontend/
│   ├── index.html          # Drawing canvas + cluster stats UI
│   └── Dockerfile
├── gateway/
│   ├── index.js            # WebSocket server + leader routing
│   ├── package.json
│   └── Dockerfile
├── replica1/
│   ├── index.js            # RAFT node implementation
│   ├── package.json
│   └── Dockerfile
├── replica2/               # Same as replica1, different env vars
├── replica3/               # Same as replica1, different env vars
├── scripts/
│   ├── kill_leader.sh      # Kill current leader for failover demo
│   ├── restart_replica.sh  # Restart a specific replica
│   ├── chaos_test.sh       # Rapid failure stress test
│   ├── show_status.sh      # Show all replica statuses
│   ├── verify_consistency.sh
│   ├── hot_reload.sh
│   └── watch_logs.sh
└── docker-compose.yml
```

## Getting Started

### Prerequisites
- Docker Desktop (running)
- WSL Ubuntu (Windows) or Terminal (Mac/Linux)
- Git

### Run the Project

```bash
# Clone the repo
git clone https://github.com/delishariyona/MINIRAFT.git
cd MINIRAFT

# Build and start all containers
docker compose up --build
```

First build takes 3-5 minutes. Once you see heartbeat logs, open:

| Service | URL |
|---------|-----|
| Drawing Board | http://localhost:8080 |
| Gateway Status | http://localhost:3000/leader |
| Cluster Status | http://localhost:3000/cluster-status |
| Replica 1 | http://localhost:4001/status |
| Replica 2 | http://localhost:4002/status |
| Replica 3 | http://localhost:4003/status |

### Run in Background

```bash
docker compose up -d
```

### Stop Everything

```bash
docker compose down
```


## Mini-RAFT Protocol

### Node States

| State | Description |
|-------|-------------|
| Follower | Default state. Waits for heartbeats from leader |
| Candidate | Starts election when heartbeat timeout fires |
| Leader | Handles all stroke replication and commits |

### Election Rules
- Election timeout: **random 500–800ms**
- Heartbeat interval: **150ms**
- A node becomes leader on receiving **≥2 votes** (majority of 3)
- Higher term always wins
- Split votes retry with incremented term

### Log Replication Flow
```
Client draws stroke
    → Gateway forwards to Leader
    → Leader appends to log
    → Leader sends AppendEntries to Followers
    → Followers acknowledge
    → Leader commits when majority (2+) ack
    → Leader notifies Gateway
    → Gateway broadcasts to all clients
```

### Catch-Up Protocol (Restarted Node)
```
Node restarts → empty log
    → Receives AppendEntries from leader
    → prevLogIndex check fails
    → Leader pushes all missing entries via /receive-sync
    → Node catches up and participates normally
```


## API Reference

### Replica Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/request-vote` | POST | Request vote during election |
| `/append-entries` | POST | Replicate log entry from leader |
| `/heartbeat` | POST | Leader heartbeat to followers |
| `/receive-sync` | POST | Catch-up sync for restarted nodes |
| `/sync-log` | GET | Get committed entries from index N |
| `/stroke` | POST | Submit stroke to leader |
| `/status` | GET | Current node state and stats |
| `/health` | GET | Liveness check |

### Gateway Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/ws` | WebSocket | Client connection endpoint |
| `/leader` | GET | Current leader URL |
| `/cluster-status` | GET | All replica statuses proxied |
| `/health` | GET | Liveness check |


## Testing Failover

```bash
# Terminal 1 — watch logs
docker compose logs -f

# Terminal 2 — kill the leader
docker stop replica1

# Watch new leader get elected within 1 second
# Draw on canvas — still works with zero downtime

# Restart killed replica — it catches up automatically
docker start replica1
```

### Chaos Testing
```bash
chmod +x scripts/*.sh
./scripts/chaos_test.sh
```

### Hot Reload Test
```bash
# Edit any file in replica2/ and save
# nodemon auto-restarts the container
# System stays live — other replicas maintain quorum
code replica2/index.js
```

## Demo Checklist (Video)

- [ ] Drawing from multiple browser tabs simultaneously
- [ ] Killing the leader — automatic failover shown
- [ ] New leader elected, drawing continues
- [ ] Hot-reloading a replica — system stays live
- [ ] Restarted replica catches up to correct log length
- [ ] Chaos test — multiple rapid failures


## Team

| Member | Responsibility |
|--------|---------------|
| Eshwar R A | Frontend — Canvas drawing, WebSocket client, real-time rendering |
| Diya D Bhat | Gateway — WebSocket server, leader routing, failover handling, logs & strokes handling |
| Delisha Riyona Dsouza | RAFT Core — Leader election, log replication, commit logic |
| Dhanya Prabhu | Docker & DevOps — Containers, hot reload, fault tolerance, catch-up |
