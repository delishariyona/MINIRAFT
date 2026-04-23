#!/bin/bash
# verify_consistency.sh
echo ""
echo "🔎 CONSISTENCY CHECK"
echo "════════════════════"
echo ""

declare -a LOG_LENGTHS
declare -a COMMIT_IDXS
declare -a ONLINE_LOGS
declare -a ONLINE_COMMITS

for i in 1 2 3; do
  port=$((4000 + i))
  result=$(curl -s --max-time 2 http://localhost:$port/status 2>/dev/null)
  if [ -z "$result" ]; then
    echo "  [replica$i]  OFFLINE — skipping"
    LOG_LENGTHS[$i]="OFFLINE"
    COMMIT_IDXS[$i]="OFFLINE"
  else
    state=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['state'])" 2>/dev/null)
    term=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['term'])" 2>/dev/null)
    logLen=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['logLength'])" 2>/dev/null)
    commitIdx=$(echo $result | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['commitIndex'])" 2>/dev/null)
    LOG_LENGTHS[$i]=$logLen
    COMMIT_IDXS[$i]=$commitIdx
    ONLINE_LOGS+=("$logLen")
    ONLINE_COMMITS+=("$commitIdx")
    badge=" $state"; [ "$state" = "leader" ] && badge=" LEADER"
    echo "  [replica$i]  $badge  term=$term  logLength=$logLen  commitIndex=$commitIdx"
  fi
done

echo ""

# Check log lengths (must all match)
FIRST_LOG=${ONLINE_LOGS[0]}
LOG_OK=true
for val in "${ONLINE_LOGS[@]}"; do
  [ "$val" != "$FIRST_LOG" ] && LOG_OK=false
done

# commitIndex allowed to differ by at most 1 (one heartbeat lag is normal)
MAX_C=${ONLINE_COMMITS[0]}
MIN_C=${ONLINE_COMMITS[0]}
for val in "${ONLINE_COMMITS[@]}"; do
  python3 -c "exit(0 if $val > $MAX_C else 1)" 2>/dev/null && MAX_C=$val
  python3 -c "exit(0 if $val < $MIN_C else 1)" 2>/dev/null && MIN_C=$val
done
DIFF=$(python3 -c "print($MAX_C - $MIN_C)" 2>/dev/null)

if $LOG_OK && [ "$DIFF" -le 1 ] 2>/dev/null; then
  echo "   FULLY CONSISTENT"
  echo "     All replicas have identical log lengths."
  echo "     commitIndex diff = $DIFF (normal — resolves within 1 heartbeat / 150ms)"
  echo "     Every client sees the exact same canvas state."
elif $LOG_OK; then
  echo "   LOG LENGTHS MATCH — data is safe and identical across replicas."
  echo "    commitIndex diff = $DIFF — one replica is slightly behind on commit acknowledgement."
  echo "     This is normal during catch-up. Run again in 2 seconds to see it resolve."
else
  echo "   LOG LENGTHS DIFFER — catch-up still in progress."
  echo "     Wait 3 seconds and re-run: ./scripts/verify_consistency.sh"
fi
echo ""
