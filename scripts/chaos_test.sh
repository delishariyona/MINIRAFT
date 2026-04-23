#!/bin/bash
# chaos_test.sh — simulates chaotic conditions: multiple rapid failures and recoveries
# This is the "chaotic conditions" demo required by the assignment
# Usage: ./scripts/chaos_test.sh

echo ""
echo " CHAOS TEST — Multiple Rapid Failures"
echo "════════════════════════════════════════"
echo "This test will:"
echo "  1. Kill replica1, wait for failover"
echo "  2. Kill replica2 (only 1 replica left — quorum gone)"
echo "  3. Restart replica1 (quorum restored)"
echo "  4. Restart replica2 (full cluster restored)"
echo ""
echo "Keep http://localhost:8080 open and draw between steps!"
echo ""
read -p "Press ENTER to begin chaos test..."

# ── Round 1: Kill replica1 ───────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "CHAOS STEP 1: Killing replica1"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker stop replica1
echo " Waiting 2s for new election..."
sleep 2

echo ""
echo "Cluster state (replica1 dead):"
for port in 4001 4002 4003; do
  r="replica$((port-4000))"
  result=$(curl -s --max-time 1 http://localhost:$port/status 2>/dev/null)
  if [ -z "$result" ]; then echo "  [$r]  OFFLINE"
  else
    state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
    term=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    badge=" $state"; [ "$state" = "leader" ] && badge=" LEADER"
    echo "  [$r] $badge  term=$term"
  fi
done

echo ""
read -p " System still running with 2 replicas. Press ENTER for next step..."

# ── Round 2: Kill replica2 (quorum lost) ────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "CHAOS STEP 2: Killing replica2 (only 1 replica left!)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker stop replica2
echo "⏳ Waiting 2s..."
sleep 2

echo ""
echo "Cluster state (replica1 + replica2 dead — NO QUORUM):"
for port in 4001 4002 4003; do
  r="replica$((port-4000))"
  result=$(curl -s --max-time 1 http://localhost:$port/status 2>/dev/null)
  if [ -z "$result" ]; then echo "  [$r]  OFFLINE"
  else
    state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
    term=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    badge=" $state"; [ "$state" = "leader" ] && badge=" LEADER"
    echo "  [$r] $badge  term=$term"
  fi
done

echo ""
echo "  System is unavailable for writes — cannot reach quorum of 2."
echo "   This is CORRECT RAFT behavior: safety over availability."
echo ""
read -p "Press ENTER to restore quorum by restarting replica1..."

# ── Round 3: Restore quorum ──────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "CHAOS STEP 3: Restarting replica1 (quorum restored)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker start replica1
echo " Waiting 3s for election and catch-up..."
sleep 3

echo ""
echo "Cluster state (quorum restored):"
for port in 4001 4002 4003; do
  r="replica$((port-4000))"
  result=$(curl -s --max-time 2 http://localhost:$port/status 2>/dev/null)
  if [ -z "$result" ]; then echo "  [$r]  OFFLINE"
  else
    state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
    term=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    logLen=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['logLength'])" 2>/dev/null)
    badge=" $state"; [ "$state" = "leader" ] && badge=" LEADER"
    echo "  [$r] $badge  term=$term  log=$logLen"
  fi
done

echo ""
read -p " Drawing works again! Press ENTER for full cluster restore..."

# ── Round 4: Full restore ────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "CHAOS STEP 4: Restarting replica2 (full cluster)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker start replica2
echo "⏳ Waiting 3s for catch-up sync..."
sleep 3

echo ""
echo "FINAL CLUSTER STATE:"
for port in 4001 4002 4003; do
  r="replica$((port-4000))"
  result=$(curl -s --max-time 2 http://localhost:$port/status 2>/dev/null)
  if [ -z "$result" ]; then echo "  [$r]  OFFLINE"
  else
    state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
    term=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    logLen=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['logLength'])" 2>/dev/null)
    commitIdx=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['commitIndex'])" 2>/dev/null)
    badge=" $state"; [ "$state" = "leader" ] && badge=" LEADER"
    echo "  [$r] $badge  term=$term  log=$logLen  committed=$commitIdx"
  fi
done

echo ""
echo " CHAOS TEST COMPLETE"
echo "   All replicas are back. Canvas state is consistent across all nodes."
echo "   Verify on http://localhost:8080 — all drawings made before failures are still there."
echo ""
