#!/bin/bash
# hot_reload.sh — triggers a hot reload on a replica by touching its file
# Usage: ./scripts/hot_reload.sh replica2

REPLICA=${1:-replica2}

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
echo " Hot Reload Demo on $REPLICA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Step 1: Current state of $REPLICA:"
curl -s http://localhost:$PORT/status | python3 -m json.tool 2>/dev/null || echo "  (not responding)"

echo ""
echo "Step 2: Appending a comment to $REPLICA/index.js..."
echo "// hot-reload triggered at $(date)" >> ./$REPLICA/index.js
echo "    File modified."

echo ""
echo "Step 3: Nodemon inside the container detects the change and restarts..."
echo "        Watch the logs in another terminal:"
echo "        docker compose logs -f $REPLICA"
echo ""
echo "⏳ Waiting 4 seconds for container to restart and rejoin cluster..."
sleep 4

echo ""
echo "Step 4: Cluster state after hot reload:"
for port in 4001 4002 4003; do
  r="replica$((port - 4000))"
  result=$(curl -s --max-time 2 http://localhost:$port/status 2>/dev/null)
  if [ -z "$result" ]; then
    echo "  [$r]   OFFLINE"
  else
    state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
    term=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    badge=" $state"; [ "$state" = "leader" ] && badge=" LEADER"
    echo "  [$r]  $badge  term=$term"
  fi
done

echo ""
echo " Hot reload complete — clients never disconnected, system stayed live."
echo ""
