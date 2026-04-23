#!/bin/bash
# show_status.sh — prints the state of all 3 replicas in a nice table
# Usage: ./scripts/show_status.sh

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              MINI-RAFT CLUSTER STATUS                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

for port in 4001 4002 4003; do
  replica="replica$((port - 4000))"
  result=$(curl -s --max-time 2 http://localhost:$port/status 2>/dev/null)
  if [ -z "$result" ]; then
    echo "  [$replica : port $port]    OFFLINE / NOT RESPONDING"
  else
    state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
    term=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    logLen=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['logLength'])" 2>/dev/null)
    commitIdx=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['commitIndex'])" 2>/dev/null)

    if [ "$state" = "leader" ]; then
      badge=" LEADER  "
    elif [ "$state" = "candidate" ]; then
      badge=" CANDIDATE"
    else
      badge=" follower "
    fi

    echo "  [$replica : port $port]  $badge  term=$term  log=$logLen entries  committed=$commitIdx"
  fi
done

echo ""
echo "  Gateway WebSocket:  ws://localhost:3000"
echo "  Drawing Board UI:   http://localhost:8080"
echo ""
