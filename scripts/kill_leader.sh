#!/bin/bash
# kill_leader.sh — finds the current leader and kills it
# Usage: ./scripts/kill_leader.sh

echo ""
echo " Finding current leader..."

LEADER_CONTAINER=""
for port in 4001 4002 4003; do
  replica="replica$((port - 4000))"
  result=$(curl -s --max-time 2 http://localhost:$port/status 2>/dev/null)
  state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
  if [ "$state" = "leader" ]; then
    LEADER_CONTAINER=$replica
    LEADER_PORT=$port
    LEADER_TERM=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    break
  fi
done

if [ -z "$LEADER_CONTAINER" ]; then
  echo " No leader found! Is the cluster running?"
  echo "   Run: docker compose up -d"
  exit 1
fi

echo " Current leader: $LEADER_CONTAINER (port $LEADER_PORT, term $LEADER_TERM)"
echo ""
echo " Killing $LEADER_CONTAINER now..."
docker stop $LEADER_CONTAINER

echo ""
echo " Waiting 2 seconds for election to complete..."
sleep 2

echo ""
echo "🗳️  Election result — new cluster state:"
for port in 4001 4002 4003; do
  replica="replica$((port - 4000))"
  result=$(curl -s --max-time 2 http://localhost:$port/status 2>/dev/null)
  if [ -z "$result" ]; then
    echo "  [$replica]   OFFLINE"
  else
    state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
    term=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    if [ "$state" = "leader" ]; then
      echo "  [$replica]   NEW LEADER  (term=$term — went up from $LEADER_TERM)"
    elif [ -z "$state" ]; then
      echo "  [$replica]   OFFLINE"
    else
      echo "  [$replica]   $state  (term=$term)"
    fi
  fi
done

echo ""
echo " Failover complete! Draw on http://localhost:8080 — system should still work."
echo ""
echo "To restart the killed replica:   docker start $LEADER_CONTAINER"
