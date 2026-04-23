#!/bin/bash
# watch_logs.sh — tail logs from all replicas and gateway together
# Usage: ./scripts/watch_logs.sh

echo ""
echo " Streaming logs from all services..."
echo "   (Ctrl+C to stop)"
echo ""

docker compose logs -f --tail=20 replica1 replica2 replica3 gateway
