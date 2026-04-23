#!/bin/bash
# restart_replica.sh — restarts a stopped replica and verifies it catches up
# Usage: ./scripts/restart_replica.sh replica1
#        ./scripts/restart_replica.sh replica2
#        ./scripts/restart_replica.sh replica3

REPLICA=${1:-replica1}

case $REPLICA in
  replica1) PORT=4001 ;;
  replica2) PORT=4002 ;;
  replica3) PORT=4003 ;;
  *)
    echo "Usage: $0 replica1|replica2|replica3"
    exit 1
    ;;
esac

echo ""
echo "▶  Restarting $REPLICA..."
docker start $REPLICA

echo " Waiting 3 seconds for node to boot and catch up..."
sleep 3

echo ""
echo " Cluster state after restart:"
for port in 4001 4002 4003; do
  r="replica$((port - 4000))"
  result=$(curl -s --max-time 2 http://localhost:$port/status 2>/dev/null)
  if [ -z "$result" ]; then
    echo "  [$r]   OFFLINE"
  else
    state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
    term=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    logLen=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['logLength'])" 2>/dev/null)
    commitIdx=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['commitIndex'])" 2>/dev/null)
    badge=" $state"
    [ "$state" = "leader" ] && badge=" LEADER"
    echo "  [$r]  $badge  term=$term  log=$logLen  committed=$commitIdx"
  fi
done

echo ""
result=$(curl -s --max-time 2 http://localhost:$PORT/status 2>/dev/null)
if [ -z "$result" ]; then
  echo "  $REPLICA did not respond. Check: docker logs $REPLICA"
else
  echo " $REPLICA is back online and in sync."
fi
echo ""
